# frozen_string_literal: true

require 'net/http'
require 'json'

module Outreach
  # GenerationService: Writes a 3-sentence Partner Program email from prospect research.
  class GenerationService
    class Result
      attr_reader :prospect, :success, :error

      def initialize(prospect:, success:, error: nil)
        @prospect = prospect
        @success = success
        @error = error
      end

      def success?
        success
      end

      def failed?
        !success
      end
    end

    SOCIAL_PROOF_LINK = 'https://www.yourgreenpal.com/partner-program'
    MAX_WORDS = 90
    REWRITE_THRESHOLD_WORDS = 100

    EMAIL_SYSTEM_PROMPT = <<~PROMPT.freeze
      Write a B2B cold email for GreenPal's Partner Program outreach.

      HARD CONSTRAINTS:
      - The email body MUST be under 90 words.
      - Use a calm, professional tone. Avoid exclamation points, "I hope this finds you well," and marketing hype.
      - You MUST include this link: #{SOCIAL_PROOF_LINK}

      LINK INTEGRATION (critical):
      - Do NOT use a standard footer or the same Partner Program paragraph at the end of every email.
      - Integrate the link naturally into the flow of the email. Use varied phrasing for the call-to-action.
      - Examples of varied phrasing:
        * "I thought this link on our partner program might be a useful resource for your team: [Link]"
        * "We've been helping other dealers streamline this—details are here if you're curious: [Link]"
        * "Since you focus on [Specific Product], this partner resource might be relevant: [Link]"
      - NEVER use "enhance your service offerings" or "drive growth"—it sounds like a marketing brochure. Keep it peer-to-peer.

      Structure:
      1. Subject line: One short, catchy line (under 60 chars). Use the observation to make it specific.
      2. Sentence 1 (The Hook): MUST start with "Hi {{first_name}},". Then use the observation—a specific technical detail or product mention.
      3. Sentence 2 (The Value): Connect their business to our free Partner Program. Contextualize based on job_title.
      4. Sentence 3 (The CTA): Low-friction close. Weave the link in with varied phrasing—never a generic footer.

      OUTPUT FORMAT (mandatory):
      SUBJECT: [Text]
      BODY: [Text]
    PROMPT

    def initialize(prospect)
      @prospect = prospect
    end

    def self.call(prospect)
      new(prospect).call
    end

    def call
      return Result.new(prospect: prospect, success: false, error: 'Missing observation') if prospect.observation.blank?

      raw = generate_email
      return Result.new(prospect: prospect, success: false, error: 'OpenAI generation failed') if raw.blank?

      subject, body = parse_subject_and_body(raw)
      return Result.new(prospect: prospect, success: false, error: 'OpenAI generation failed') if body.blank?

      body = body.strip.gsub('{{first_name}}', prospect.first_name.presence || 'there')

      if word_count(body) > REWRITE_THRESHOLD_WORDS
        body = rewrite_shorter(body)
        return Result.new(prospect: prospect, success: false, error: 'OpenAI generation failed') if body.blank?
      end

      prospect.generated_email_subject = subject.to_s.strip.presence
      prospect.generated_email_body = body
      prospect.status = 'ready_for_review'
      prospect.save!
      Result.new(prospect: prospect, success: true)
    rescue StandardError => e
      Rails.logger.warn("[GenerationService] Error for prospect #{prospect.id}: #{e.message}")
      Result.new(prospect: prospect, success: false, error: e.message)
    end

    private

    attr_reader :prospect

    def openai_api_key
      credentials(:openai_api_key) || ENV['OPENAI_API_KEY']
    end

    def credentials(key)
      return nil unless Rails.application.respond_to?(:credentials) && Rails.application.credentials
      Rails.application.credentials[key]
    end

    def generate_email
      return nil if openai_api_key.blank?

      prompt = build_prompt
      openai_request(openai_api_key, prompt)
    end

    def build_prompt
      signals_context = signals_context_for_prompt
      <<~PROMPT
        first_name: #{prospect.first_name.presence || 'there'}
        job_title: #{prospect.job_title.presence || 'N/A'}

        Observation (use this for sentence 1 after the greeting): #{prospect.observation}

        Company / research context: #{prospect.research_summary.to_s.truncate(400)}

        Company: #{prospect.company_name.presence || 'Unknown'}

        #{signals_context}

        Write the subject line and email body (under 90 words). Start with "Hi [first_name]," using the first_name above.
        Use the observation to make the subject catchy. Integrate #{SOCIAL_PROOF_LINK} naturally into the flow—no standard footer. Vary the CTA phrasing. Never use "enhance your service offerings" or "drive growth."
        Return in this exact format:
        SUBJECT: [your subject line]
        BODY: [your email body]
      PROMPT
    end

    def signals_context_for_prompt
      return '' unless prospect.respond_to?(:signals_detected) && prospect.signals_detected.present?

      signals = prospect.signals_detected.to_s.split(/,\s*/).map(&:strip).reject(&:blank?)
      return '' if signals.empty?

      signal_label = signals.map { |s| s.downcase.gsub(/_/, ' ') }.join(', ')
      score_str = prospect.respond_to?(:look_alike_score) && prospect.look_alike_score.present? ? " Score: #{prospect.look_alike_score}." : ''
      "Broad signals: #{signal_label}.#{score_str} Weave \"We noticed your scalable approach to [signal]\" into the hook if it fits."
    end

    def parse_subject_and_body(raw)
      text = raw.to_s.strip
      subject = nil
      body = nil

      if text =~ /Subject:\s*(.+?)\s*[\r\n]+\s*Body:\s*([\s\S]+)/mi
        subject = Regexp.last_match(1).to_s.strip
        body = Regexp.last_match(2).to_s.strip
      elsif text =~ /SUBJECT:\s*(.+?)\s*[\r\n]+\s*BODY:\s*([\s\S]+)/mi
        subject = Regexp.last_match(1).to_s.strip
        body = Regexp.last_match(2).to_s.strip
      end

      if subject.blank? || body.blank?
        subject = fallback_subject
        body = text
      end

      [subject.presence, body.presence || text]
    end

    def word_count(text)
      text.to_s.split(/\s+/).count
    end

    def rewrite_shorter(body)
      return body if openai_api_key.blank?

      prompt = "Rewrite this email body to be under #{MAX_WORDS} words. Keep the same message and tone. Keep it peer-to-peer—no 'enhance your service offerings' or 'drive growth.' Return ONLY the rewritten body, no subject.\n\n#{body}"
      result = openai_request(openai_api_key, prompt)
      result.to_s.strip.presence || body
    end

    def fallback_subject
      base = prospect.observation.to_s.strip
      return "#{base[0, 57]}..." if base.length > 60
      return base if base.present?

      'Quick question – GreenPal Partner Program'
    end

    def openai_request(api_key, prompt)
      uri = URI('https://api.openai.com/v1/chat/completions')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Authorization'] = "Bearer #{api_key}"
      request['Content-Type'] = 'application/json'
      request.body = {
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: EMAIL_SYSTEM_PROMPT },
          { role: 'user', content: prompt }
        ],
        max_tokens: 350,
        temperature: 0.4
      }.to_json

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      json = JSON.parse(response.body)
      json.dig('choices', 0, 'message', 'content')
    end
  end
end

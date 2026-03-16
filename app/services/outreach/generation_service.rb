# frozen_string_literal: true

require 'net/http'
require 'json'

module Outreach
  # GenerationService: Writes a Partner Program pitch email from prospect research.
  # Follows dynamic structure: Observation → Program Explanation → Tangible Benefit → Remove Skepticism → Low-Friction Close.
  # Emails feel human-written and contextually relevant, with a matched partner link as social proof.
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

    DEFAULT_PERKS_URL = 'https://www.yourgreenpal.com/partners/perks/mowmore-2-discount'
    DEFAULT_REF_PARTNER_NAME = 'MowMore'

    # Maps prospect accept_category (from research) to ReferencePartner category
    ACCEPT_TO_REF_CATEGORY = {
      'parts' => 'supplies',
      'supplies' => 'supplies',
      'accessories' => 'supplies',
      'software' => 'saas',
      'tools' => 'hardware',
      'hardware' => 'hardware',
      'equipment' => 'hardware',
      'trailer' => 'hardware',
      'insurance' => 'finance'
    }.freeze

    EMAIL_SYSTEM_PROMPT = <<~PROMPT.freeze
      Write a B2B cold email for GreenPal's Partners Program outreach.

      TONE: Calm, professional, peer-to-peer. No exclamation points, no "I hope this finds you well," no "I wanted to reach out," no "I came across your company." No marketing hype. Never use "enhance your service offerings" or "drive growth."

      CONTEXTUAL RELEVANCE (critical): The recipient must believe a human sat down and wrote this specifically for them. Pull specific details from the research: product names, service focus, niche, pain points. The opening should reference something only someone who looked at their site/business would know. Connect their specific offering to the contractor pain point we solve. No generic filler.

      THE PITCH MUST FOLLOW THIS STRUCTURE:

      1. GREETING — Hi [first_name],

      2. OBSERVATION (2 sentences) — Prove we know who they are. Choose structure based on prospect type:
         - Product/catalog: "I was looking through your [specific product]. For landscape operators [relevant scenario], [pain point] is critical..."
         - Service: "I was reviewing your [service] for landscapers. For operators [pain point], [benefit] can make a major difference."
         - Training/organization: "Landscape professionals are always looking for [pain point]. You've built that through [Company]'s [specific offering]."
         NO generic praise. Be specific.

      3. INTRO — "I'm Gene Caballero, Co-Founder of GreenPal."

      4. AUDIENCE — "We work with 65k lawn and landscape professionals nationwide." (or "We serve 65,000+...")

      5. PARTNER HUB — Use short OR long variant (do NOT use both; do NOT repeat discount messaging):
         - Short: "Inside GreenPal, we built a Partner Hub where vendors and organizations gain direct visibility to these operators. There is no cost to be listed." (Then add discount line in step 7 if desired.)
         - Long: "We built a Partner Hub inside GreenPal to list tools and services our vendors may want to discover. There is no cost to be included. If partners choose to offer a discount, we highlight it, otherwise, it is simply brand visibility inside the hub." (Do NOT add the separate discount line — it would be redundant.)

      6. EXAMPLE PARTNER (include when reference partner is provided) — "One example partner is [Reference Partner Name]. Here's an example of what that looks like: [plain URL]"
         - When using SHORT Partner Hub, you MAY add: "If you offer a member benefit or discount, we highlight it. If not, you still gain exposure." (Only add this when you did NOT already include discount phrasing in step 5.)
         - NEVER repeat "If you offer a discount..." and "If partners choose to offer a discount..." in the same email.

      7. CTA (mandatory) — MUST include the company display name (NOT the domain like workwave.com — use "WorkWave" or the brand name). Use one of:
         - "Would it make sense to feature [Company Name] the same way?"
         - "Would it make sense to feature [Company Name] similarly?"
         - "Would you want [Company Name] in front of the same audience?"

      8. CLOSE — "Open to a brief call?" or "Open to a quick call?"

      9. SIGNATURE:
      Best,
      Gene Caballero
      Co-Founder | GreenPal
      www.yourgreenpal.com

      SUBJECT LINE: "Possible fit between GreenPal and [Company Name]" (use display name, not domain — e.g. "WorkWave" not "workwave.com")

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

      first_name = prospect.first_name.presence || 'there'
      body = body.strip
        .gsub('{{first_name}}', first_name)
        .gsub('[first_name]', first_name)

      body = strip_markdown_links(body)
      body = normalize_company_name_in_body(body)
      body = ensure_cta_includes_company(body) if prospect.company_name.present? && !body.include?(company_display_name)

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

    def reference_partner_info
      @reference_partner_info ||= resolve_reference_partner_info
    end

    def resolve_reference_partner_info
      ref_category = ACCEPT_TO_REF_CATEGORY[prospect.accept_category.to_s.downcase.strip]
      ref = if ref_category.present?
              ReferencePartner.by_category(ref_category).by_display_order.first
            end
      ref ||= ReferencePartner.by_display_order.first
      return { name: DEFAULT_REF_PARTNER_NAME, perks_url: DEFAULT_PERKS_URL } if ref.blank?

      {
        name: ref.name.presence || DEFAULT_REF_PARTNER_NAME,
        perks_url: ref.perks_url.presence || DEFAULT_PERKS_URL
      }
    end

    def company_display_name
      raw = prospect.company_name.presence || prospect.domain.presence || ''
      return 'your company' if raw.blank?

      # Strip domain suffixes and convert to display name (e.g. workwave.com -> WorkWave)
      name = raw.to_s.strip
      name = name.sub(/\s*\([^)]*\)\s*\z/, '') # remove trailing (parenthetical)
      name = name.gsub(/\b(\.com|\.net|\.io|\.co|\.org|\.us)\b/i, '')
      name = name.gsub(/^https?:\/\//i, '').gsub(/^www\./i, '')
      name = name.split('/').first.to_s.strip
      name = name.gsub(/[-_](inc|llc|corp|co)\.?$/i, '').strip
      name = name.gsub(/[-_]/, ' ').strip
      return 'your company' if name.blank?

      name.split(/\s+/).map(&:capitalize).join(' ')
    end

    def build_prompt
      ref_info = reference_partner_info
      ref_name = ref_info[:name]
      ref_perks_url = ref_info[:perks_url]
      company_display = company_display_name
      signals_context = signals_context_for_prompt

      <<~PROMPT
        first_name: #{prospect.first_name.presence || 'there'}
        job_title: #{prospect.job_title.presence || 'N/A'}
        company_display_name: #{company_display} (use this in CTA and subject — NOT the raw domain like workwave.com)

        Observation (use for step 2 — be specific, no generic praise; prove we know them): #{prospect.observation}

        Company / research context: #{prospect.research_summary.to_s.truncate(500)}

        #{signals_context}

        REFERENCE PARTNER (for social proof — include "One example partner is #{ref_name}." with link): #{ref_name}
        Perks URL: #{ref_perks_url}

        CTA MUST include the company display name: #{company_display}. Use one of: "Would it make sense to feature #{company_display} the same way?", "Would it make sense to feature #{company_display} similarly?", or "Would you want #{company_display} in front of the same audience?"

        Write the subject line and full email body following the structure. Start with "Hi [first_name]," using the first_name above.
        Subject: "Possible fit between GreenPal and #{company_display}".
        Include the reference partner (#{ref_name}) and perks URL as social proof. Use the plain URL (no Markdown): "Here's an example of what that looks like: #{ref_perks_url}" — do NOT use [text](url) format. End with the Gene Caballero signature.
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
      "Broad signals: #{signal_label}.#{score_str} Weave into the observation if it fits naturally."
    end

    def strip_markdown_links(text)
      # Convert [text](url) to plain url for plain text email
      text.gsub(/\[([^\]]+)\]\((https?:\/\/[^\)]+)\)/, '\2')
    end

    def normalize_company_name_in_body(body)
      display = company_display_name
      raw = prospect.company_name.presence || prospect.domain.presence || ''
      return body if raw.blank? || display == raw || display == 'your company'

      # Replace domain-style company name (e.g. workwave.com) with display name (WorkWave) in CTA
      domain = prospect.domain.to_s
      [raw, domain].uniq.reject(&:blank?).each do |to_replace|
        next if to_replace == display
        body = body.gsub(
          /(Would it make sense to feature )#{Regexp.escape(to_replace)}( the same way\?| similarly\?)/i,
          "\\1#{display}\\2"
        )
        body = body.gsub(
          /(Would you want )#{Regexp.escape(to_replace)}( in front of the same audience\?)/i,
          "\\1#{display}\\2"
        )
      end
      body
    end

    def ensure_cta_includes_company(body)
      display = company_display_name
      return body if display == 'your company' || body.include?(display)

      lines = body.split("\n")
      cta_patterns = [
        /Would it make sense to feature .+ the same way\?/i,
        /Would it make sense to feature .+ similarly\?/i,
        /Would you want .+ in front of the same audience\?/i
      ]

      lines.each_with_index do |line, i|
        cta_patterns.each do |pattern|
          if line =~ pattern && !line.include?(display)
            lines[i] = "Would it make sense to feature #{display} the same way?"
            return lines.join("\n")
          end
        end
      end

      cta_insert = "\nWould it make sense to feature #{display} the same way?\n\nOpen to a brief call?\n\n"
      if body =~ /(\n\s*Best,\s*\n)/i
        body.sub(/(\n\s*Best,\s*\n)/i, "#{cta_insert}\\1")
      else
        body + cta_insert
      end
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

    def fallback_subject
      "Possible fit between GreenPal and #{company_display_name}"
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
        max_tokens: 600,
        temperature: 0.4
      }.to_json

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      json = JSON.parse(response.body)
      json.dig('choices', 0, 'message', 'content')
    end
  end
end

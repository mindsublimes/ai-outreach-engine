# frozen_string_literal: true

require 'net/http'
require 'json'

module Outreach
  class EnrichmentService
    class Result
      attr_reader :prospect, :enriched

      def initialize(prospect:, enriched:)
        @prospect = prospect
        @enriched = enriched
      end

      def success?
        enriched
      end

      def failed?
        !enriched
      end

      def error
        failed? ? 'Enrichment failed (no email found)' : nil
      end
    end

    CATEGORY_TO_TARGET = {
      'Insurance' => 'Agency Principal',
      'Software' => 'CEO/Founder',
      'Tools' => 'Sales Director'
    }.freeze

    VALID_CATEGORIES = CATEGORY_TO_TARGET.keys.freeze

    def initialize(prospect)
      @prospect = prospect
    end

    def self.call(prospect)
      new(prospect).call
    end

    def call
      perform_enrichment
    rescue Outreach::RocketReachClient::NoCreditsError
      mark_out_of_credits
    end

    private

    def openai_api_key
      credentials(:openai_api_key) || ENV['OPENAI_API_KEY']
    end

    def credentials(key)
      return nil unless Rails.application.respond_to?(:credentials) && Rails.application.credentials
      Rails.application.credentials[key]
    end

    def perform_enrichment
      domain = sanitize_and_extract_domain(@prospect.url)
      return log_and_fail('domain blank') if domain.blank?

      search_result = fetch_search_result(domain)
      return log_and_fail("no profiles (keys=#{search_result&.keys&.inspect})") unless search_result.present? && response_has_profiles?(search_result)

      profile_id = extract_profile_id(search_result)
      return log_and_fail('no profile id') if profile_id.blank?

      full_profile = Outreach::RocketReachClient.get_profile(id: profile_id)
      return log_and_fail("lookup blank for id=#{profile_id}") if full_profile.blank?

      email = extract_first_professional_email(full_profile)
      return log_and_fail("no email (emails=#{full_profile['emails']&.map { |e| e.slice('type', 'email') }&.inspect})") if email.blank?

      first_name, last_name = extract_name_from_profile(full_profile)
      @prospect.update!(
        first_name: first_name,
        last_name: last_name,
        job_title: (full_profile['current_title'] || full_profile['current_employer_title']).to_s.strip.presence,
        email: email,
        status: 'enriched'
      )
      Result.new(prospect: @prospect, enriched: true)
    end

    def response_has_profiles?(search_result)
      extract_first_profile(search_result).present?
    end

    def profiles_empty?(search_result)
      !response_has_profiles?(search_result)
    end

    def extract_first_profile(search_result)
      return nil if search_result.blank?

      profiles = if search_result.is_a?(Hash)
                   search_result['profiles'] || search_result['people'] || search_result['results'] || []
                 elsif search_result.is_a?(Array)
                   search_result
                 else
                   []
                 end

      profiles.is_a?(Array) && profiles.any? ? profiles.first : nil
    end

    def extract_name_from_profile(profile)
      if profile['name'].present?
        split_name(profile['name'])
      else
        [profile['first_name'].to_s.strip.presence, profile['last_name'].to_s.strip.presence]
      end
    end

    def split_name(full_name)
      return [nil, nil] if full_name.blank?

      parts = full_name.to_s.strip.split(/\s+/, 2)
      [parts[0].presence, parts[1].presence]
    end

    def extract_first_professional_email(profile)
      return nil unless profile.is_a?(Hash)

      emails = profile['emails'] || []
      professional = emails.find { |e| e['type'] == 'professional' || e['email_type'] == 'professional' }
      return professional['email'] if professional && professional['email'].present?

      first = emails.find { |e| e['email'].present? }
      return first['email'] if first

      profile['recommended_professional_email'].presence || profile['recommended_email'].presence
    end

    def sanitize_and_extract_domain(url)
      return nil if url.blank?

      sanitized = url.to_s.strip.gsub(%r{^https?://}i, '').chomp('/')
      UrlHelpers.extract_domain("https://#{sanitized}")
    end

    def log_and_fail(reason)
      Rails.logger.info("[EnrichmentService] prospect=#{@prospect.id} failed: #{reason}")
      mark_failed(reason)
    end

    def fetch_search_result(domain)
      target_title = @prospect.target_persona.presence || resolve_target_from_category
      result = Outreach::RocketReachClient.search_person(domain: domain, title: target_title)
      result = Outreach::RocketReachClient.search_person(domain: domain, title: nil) if (result.blank? || profiles_empty?(result)) && target_title.present?
      result
    end

    def extract_profile_id(search_result)
      first = extract_first_profile(search_result)
      first['id'] || first[:id]
    end

    def mark_failed(reason = nil)
      attrs = { status: 'enrichment_failed' }
      attrs[:failure_reason] = format_enrichment_failure_reason(reason) if reason.present? && @prospect.respond_to?(:failure_reason=)
      @prospect.update!(attrs)
      Result.new(prospect: @prospect, enriched: false)
    end

    def format_enrichment_failure_reason(reason)
      case reason.to_s
      when /domain blank/i then 'Enrichment: Could not extract domain from URL'
      when /no profiles/i then 'Enrichment: No profiles found for this domain (RocketReach)'
      when /no profile id/i then 'Enrichment: No profile ID in search results'
      when /lookup blank/i then 'Enrichment: Profile lookup returned no data'
      when /no email/i then 'Enrichment: No professional email found for contact'
      else "Enrichment: #{reason.to_s.truncate(150)}"
      end
    end

    def mark_out_of_credits
      attrs = { status: 'out_of_credits' }
      attrs[:failure_reason] = 'Enrichment: RocketReach API out of credits' if @prospect.respond_to?(:failure_reason=)
      @prospect.update!(attrs)
      Result.new(prospect: @prospect, enriched: false)
    end

    def resolve_target_from_category
      category = resolve_category
      return nil unless category.present? && VALID_CATEGORIES.include?(category)

      CATEGORY_TO_TARGET[category]
    end

    def resolve_category
      return @prospect.category if @prospect.category.present? && VALID_CATEGORIES.include?(@prospect.category)

      classify_with_openai || infer_category_from_keywords
    end

    def classify_with_openai
      return nil if openai_api_key.blank?

      prompt = build_classification_prompt
      response = openai_request(openai_api_key, prompt)
      parse_category_from_response(response)
    rescue StandardError => e
      Rails.logger.warn("[EnrichmentService] OpenAI classification failed: #{e.message}")
      nil
    end

    def build_classification_prompt
      parts = [
        'Classify this B2B prospect into exactly one category: Insurance, Software, or Tools.',
        "URL: #{@prospect.url}",
        "Company: #{@prospect.company_name.presence || 'unknown'}",
        "Research: #{@prospect.research_summary.to_s.truncate(500)}"
      ]
      "#{parts.join("\n")}\n\nRespond with only the category name (Insurance, Software, or Tools)."
    end

    def openai_request(api_key, prompt)
      uri = URI('https://api.openai.com/v1/chat/completions')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Authorization'] = "Bearer #{api_key}"
      request['Content-Type'] = 'application/json'
      request.body = {
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: 'You classify B2B companies. Respond with exactly one word: Insurance, Software, or Tools.' },
          { role: 'user', content: prompt }
        ],
        max_tokens: 20,
        temperature: 0.1
      }.to_json

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      json = JSON.parse(response.body)
      json.dig('choices', 0, 'message', 'content')
    end

    def parse_category_from_response(content)
      return nil if content.blank?

      match = content.strip.match(/\b(Insurance|Software|Tools)\b/i)
      match ? match[1] : nil
    end

    def infer_category_from_keywords
      text = [
        @prospect.url,
        @prospect.company_name,
        @prospect.research_summary
      ].compact.join(' ').downcase

      return 'Insurance' if text.match?(/insur|agency|policy|coverage/)
      return 'Software' if text.match?(/software|saas|platform|app|tech/)
      return 'Tools' if text.match?(/tool|equipment|mower|hardware|supply/)

      'Software'
    end
  end
end

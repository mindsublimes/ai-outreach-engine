# frozen_string_literal: true

require 'net/http'
require 'json'

module Outreach
  # ResearchService: Discovery + Research phase for prospects.
  # Scrape → Analyze → Extract → Save
  class ResearchService
    MARCH_PIVOT_DAY = 1
    MARCH_PIVOT_MONTH = 3

    SNOW_PITCH_PROMPT = <<~PROMPT
      Pitch GreenPal to local news as a snow removal marketplace story.
      Angle: homeowners and pros connecting for plowing/shoveling during winter.
      Hook: Snow removal season, seasonal demand, local service economy.
    PROMPT

    MOWING_PITCH_PROMPT = <<~PROMPT
      Pitch GreenPal to local news as a lawn care marketplace story.
      Angle: homeowners and pros connecting for mowing during spring/summer.
      Hook: Lawn mowing season, seasonal demand, local service economy.

      Extraction hints: Identify flagship product and innovation for context. Observation = cold email opening hook.
    PROMPT

    EXTRACTION_SYSTEM_PROMPT = <<~PROMPT
      Analyze the provided webpage content and return a JSON object with exactly these keys:

      VALIDATION (check first):
      - is_parked_or_domain_for_sale: (boolean) true if the page is a "Domain for Sale", "Parked Page", "This domain is for sale", or similar domain-squatter placeholder. Set to true for these—we do NOT want to pitch domain squatters.

      If is_parked_or_domain_for_sale is true, set is_b2b: false and return. Skip the rest.

      Otherwise:
      - is_b2b: (boolean) true if this company sells to other businesses (B2B), false if consumer-facing (B2C)
      - summary: (string) A clean, objective 3-sentence description of the company for context. Factual only.
      - observation: (string) A standalone, punchy sales hook for the cold email opening. One sentence. Must be unique—do NOT repeat or paraphrase the summary. DO NOT use marketing fluff like "commitment to quality" or "perfect lawn." Instead, identify a specific technical feature or recent news (e.g., "I saw your EVZ electric zero-turn uses a 48V system" or "The Turf Tiger II's heavy-duty driveshaft caught my eye"). Sound like one professional talking to another, not an advertisement.
      - target_persona: (string) The best job title to contact for partnership outreach, e.g. "Marketing Manager", "CEO", "Sales Director"
      - reject_category: (string | null) Set to ONE of these when the company clearly fits. Judge by content and business model, not by domain name:
        manufacturer: OEM equipment maker — sells mowers, tractors, or outdoor power equipment through dealers to consumers. "Find a dealer" / "Where to buy" = manufacturer. B2B parts suppliers with "become a dealer" or wholesale = NOT manufacturer (set null).
        big_box_retailer: Mass-market consumer retail with "store locator", "shop in store", "find a store". B2C retailers, NOT B2B partners.
        fintech: Primary business is contractor financing, equipment leasing, or equipment loans. Main value prop = "finance your equipment" or "equipment financing for contractors". SaaS that mentions financing in passing = NOT fintech (set null).
        When in doubt, prefer reject_category. Set null only for clear B2B suppliers (parts, software, trailers, tools for lawn/landscape pros).
      - accept_category: (string | null) When reject_category is null and the company is clearly a valid B2B partner (NOT an OEM manufacturer), set to ONE of: "parts", "software", "tools", "supplies", "hardware", "accessories", "trailer". CRITICAL: Companies that MANUFACTURE equipment (loaders, mowers, tractors, skid-steers) and sell through dealers are OEM manufacturers — set reject_category: manufacturer, NEVER accept_category. accept_category "hardware" = company that SUPPLIES hardware/parts to pros, NOT the OEM that manufactures the equipment. Set null if reject_category applies or if unclear.

      Return ONLY valid JSON, no markdown or explanation.
    PROMPT

    PARTNER_CATEGORIES = %w[tools software insurance accessories supplies hardware parts trailer].freeze

    PARKED_DOMAIN_KEYWORDS = [
      'domain for sale',
      'buy this domain',
      'parked free',
      'contact the registrant',
      'this domain is available'
    ].freeze
    MIN_SCRAPE_LENGTH = 400

    GREEN_INDUSTRY_THEME_KEYWORDS = [
      'lawn care', 'lawncare', 'landscaping', 'landscape', 'green industry', 'lawn mowing', 'mowing', 'turf',
      'lawn professional', 'landscape professional', 'lawn care pro', 'landscape pro',
      'mower', 'zero-turn', 'commercial mower', 'outdoor power equipment', 'outdoor power',
      'lawn and landscape', 'landscape contractor', 'landscape management',
      'aftermarket parts', 'replacement parts'
    ].freeze

    class Result
      attr_reader :prospect, :b2b_b2c_status, :research_summary, :qualified_for_track, :vetting_notes

      def initialize(prospect:, b2b_b2c_status:, research_summary:, qualified_for_track:, vetting_notes:)
        @prospect = prospect
        @b2b_b2c_status = b2b_b2c_status
        @research_summary = research_summary
        @qualified_for_track = qualified_for_track
        @vetting_notes = vetting_notes
      end

      def qualified?
        qualified_for_track
      end

      def research_failed?
        prospect.research_failed?
      end

      def success?
        !research_failed?
      end

      def error
        research_failed? ? vetting_notes : nil
      end
    end

    def initialize(prospect)
      @prospect = prospect
    end

    def self.call(prospect)
      new(prospect).call
    end

    def self.debug_theme(url)
      prospect = Prospect.new(url: url)
      service = new(prospect)
      normalized = service.send(:normalize_url_for_scrape, url)
      return { error: 'Invalid URL' } if normalized.blank?

      markdown = service.send(:scrape_url, normalized)
      return { error: 'Scrape failed or empty', scrape_length: markdown.to_s.length } if markdown.blank?

      combined = [markdown, url].compact.join(' ').downcase
      matched = GREEN_INDUSTRY_THEME_KEYWORDS.select { |kw| combined.include?(kw) }
      {
        scrape_length: markdown.length,
        theme_passed: matched.any?,
        matched_keywords: matched,
        sample: markdown.to_s.truncate(500)
      }
    end

    def self.debug_extraction(url)
      prospect = Prospect.new(url: url)
      service = new(prospect)
      normalized = service.send(:normalize_url_for_scrape, url)
      return { error: 'Invalid URL' } if normalized.blank?

      markdown = service.send(:scrape_url, normalized)
      return { error: 'Scrape failed or empty' } if markdown.blank?

      extracted = service.send(:extract_with_openai, markdown)
      return { error: 'Extraction failed' } if extracted.blank?

      extracted
    end

    def self.pr_pitch_prompt(as_of: Date.current)
      use_mowing_hook?(as_of) ? MOWING_PITCH_PROMPT : SNOW_PITCH_PROMPT
    end

    def self.pr_pitch_hook(as_of: Date.current)
      use_mowing_hook?(as_of) ? 'Mowing' : 'Snow'
    end

    def self.use_mowing_hook?(as_of)
      pivot = Date.new(as_of.year, MARCH_PIVOT_MONTH, MARCH_PIVOT_DAY)
      as_of >= pivot
    end

    def call
      url = normalize_url_for_scrape(prospect.url)
      return fail_url_invalid if url.blank?

      markdown = scrape_url(url)
      return fail_scrape_empty if markdown.blank?
      return fail_scrape_invalid(markdown) unless valid_scrape_content?(markdown)

      return fail_theme_reject(markdown) if partner_track? && !gold_standard_domain? && !green_industry_theme?(markdown)

      extracted = extract_with_openai(markdown)
      return fail_extraction_failed if extracted.blank?
      return fail_parked_domain if extracted[:is_parked_or_domain_for_sale]
      return fail_openai_reject(extracted[:reject_category]) if extracted[:reject_category].present?

      signature_result = run_signature_detector(markdown)
      return fail_signature_reject(signature_result) if signature_result.rejected? && extracted[:accept_category].blank?

      complete_research(extracted, markdown, signature_result)
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

    def normalize_url_for_scrape(url)
      return nil if url.blank?

      u = url.to_s.strip
      u = "https://#{u}" unless u.match?(%r{\Ahttps?://})
      return nil if u.match?(/localhost|127\.0\.0\.1|\.local\b/i)

      u.presence
    end

    def scrape_url(url)
      markdown = Outreach::FirecrawlService.new.scrape_markdown(url)
      return markdown if markdown.present?

      Rails.logger.info("[ResearchService] Initial scrape failed for #{url}, retrying with waitFor...")
      sleep 2
      Outreach::FirecrawlService.new.scrape_markdown(url, wait_for: 2000)
    rescue StandardError => e
      Rails.logger.warn("[ResearchService] Firecrawl error for #{url}: #{e.message}")
      nil
    end

    def extract_with_openai(markdown)
      return nil if openai_api_key.blank?

      prompt = build_extraction_prompt(markdown)
      content = openai_request(openai_api_key, prompt)
      return nil if content.blank?

      parse_extraction(content)
    rescue StandardError => e
      Rails.logger.warn("[ResearchService] OpenAI extraction error: #{e.message}")
      nil
    end

    def build_extraction_prompt(markdown)
      active_prompt = self.class.pr_pitch_prompt
      <<~PROMPT
        #{EXTRACTION_SYSTEM_PROMPT}

        Context (#{self.class.pr_pitch_hook} season): #{active_prompt}

        Webpage content:

        #{markdown.to_s.truncate(12_000)}
      PROMPT
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
          { role: 'system', content: EXTRACTION_SYSTEM_PROMPT },
          { role: 'user', content: prompt }
        ],
        max_tokens: 500,
        temperature: 0.2,
        response_format: { type: 'json_object' }
      }.to_json

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      json = JSON.parse(response.body)
      json.dig('choices', 0, 'message', 'content')
    end

    def parse_extraction(content)
      raw = JSON.parse(content)
      is_parked = raw['is_parked_or_domain_for_sale'] == true
      is_b2b = raw['is_b2b'] == true
      reject_category = raw['reject_category'].to_s.strip.presence
      reject_category = nil if reject_category.present? && !%w[manufacturer big_box_retailer fintech].include?(reject_category)
      accept_category = raw['accept_category'].to_s.strip.presence
      accept_category = nil if accept_category.present? && !PARTNER_CATEGORIES.include?(accept_category)
      {
        is_parked_or_domain_for_sale: is_parked,
        is_b2b: is_b2b,
        b2b_b2c_status: is_b2b ? 'b2b' : 'b2c',
        summary: raw['summary'].to_s.strip.presence,
        observation: raw['observation'].to_s.strip.presence,
        target_persona: raw['target_persona'].to_s.strip.presence,
        reject_category: reject_category,
        accept_category: accept_category
      }
    rescue JSON::ParserError
      nil
    end

    def compute_look_alike(metadata:, signature_result:)
      return { is_scalable: false, priority: 'low' } unless signature_result&.scalable_value && signature_result.signals_detected.any?

      result = Research::LookAlikeScorer.call(
        prospect_metadata: metadata,
        prospect_signals: signature_result.signals_detected
      )
      {
        look_alike_score: result[:score],
        is_scalable: result[:score].present?,
        priority: priority_from_look_alike(result[:score], signature_result)
      }
    end

    def priority_from_look_alike(score, _signature_result)
      return 'high' if Research::SignatureDetector.gold_standard_domain?(Outreach::UrlHelpers.extract_domain(prospect.url))
      return 'high' if score && score >= 0.5
      return 'normal' if score && score >= 0.3
      'low'
    end

    def update_prospect(extracted, _markdown, look_alike: {}, signature_result: nil)
      attrs = {
        is_b2b: extracted[:is_b2b],
        b2b_b2c_status: extracted[:b2b_b2c_status],
        research_summary: extracted[:summary].presence || 'No data available.',
        observation: extracted[:observation],
        target_persona: extracted[:target_persona],
        company_name: prospect.company_name.presence || Outreach::UrlHelpers.extract_domain(prospect.url),
        research_failed: false,
        status: 'researched'
      }
      attrs[:look_alike_score] = look_alike[:look_alike_score]
      attrs[:is_scalable] = look_alike[:is_scalable] == true
      attrs[:priority] = look_alike[:priority].presence || 'normal'
      attrs[:signals_detected] = serialize_signals(signature_result&.signals_detected) if prospect.respond_to?(:signals_detected=)
      prospect.update!(attrs)
    end

    def serialize_signals(signals)
      return nil if signals.blank?
      Array(signals).map(&:to_s).join(', ')
    end

    def partner_track?
      (prospect.track || 'partner') == 'partner'
    end

    def gold_standard_domain?
      Research::SignatureDetector.gold_standard_domain?(Outreach::UrlHelpers.extract_domain(prospect.url))
    end

    def green_industry_theme?(text)
      combined = [text, prospect.url].compact.join(' ').downcase
      return true if combined.blank?

      GREEN_INDUSTRY_THEME_KEYWORDS.any? { |kw| combined.include?(kw) }
    end

    def valid_scrape_content?(text)
      return false if text.blank?
      return false if text.to_s.length < MIN_SCRAPE_LENGTH
      return false if matched_parked_keyword(text)

      true
    end

    def matched_parked_keyword(text)
      return nil if text.blank?

      lower = text.to_s.downcase
      PARKED_DOMAIN_KEYWORDS.find { |kw| lower.include?(kw) }
    end

    def scrape_failure_reason(text)
      return 'Scrape empty or unavailable' if text.blank?

      parked = matched_parked_keyword(text)
      return "Parked domain: #{parked}" if parked

      return "Low-quality scrape: #{text.to_s.length} chars (< #{MIN_SCRAPE_LENGTH})" if text.to_s.length < MIN_SCRAPE_LENGTH

      'Invalid scrape content'
    end

    def failed_result(reason)
      Result.new(
        prospect: prospect,
        b2b_b2c_status: 'unknown',
        research_summary: nil,
        qualified_for_track: false,
        vetting_notes: reason
      )
    end

    def fail_url_invalid
      prospect.update!(research_failed: true, status: 'failed', failure_reason: 'Invalid or localhost URL—cannot scrape')
      failed_result('Invalid or localhost URL—cannot scrape')
    end

    def fail_scrape_empty
      prospect.update!(research_failed: true, status: 'failed', failure_reason: 'Scrape failed or site unavailable')
      failed_result('Scrape failed or site unavailable')
    end

    def fail_scrape_invalid(markdown)
      reason = scrape_failure_reason(markdown)
      matched_keyword = matched_parked_keyword(markdown)
      attrs = { research_failed: true, status: 'failed' }
      attrs[:failure_reason] = reason if prospect.respond_to?(:failure_reason=)
      prospect.update!(attrs)
      log_msg = "[ResearchService] Invalid scrape for #{prospect.url}: #{reason}"
      log_msg += " (matched keyword: #{matched_keyword.inspect})" if matched_keyword
      Rails.logger.info(log_msg)
      failed_result(reason)
    end

    def fail_theme_reject(_markdown)
      reason = 'Niche mismatch: site is not green industry (lawn care, landscaping)—skipping sports, fitness, etc.'
      prospect.update!(
        research_failed: true,
        status: 'disqualified',
        failure_reason: reason
      )
      Rails.logger.info("[ResearchService] Theme reject for #{prospect.url}: #{reason}")
      failed_result(reason)
    end

    def fail_signature_reject(signature_result)
      prospect.update!(
        research_failed: true,
        status: 'disqualified',
        failure_reason: signature_result.reject_reason
      )
      Rails.logger.info("[ResearchService] Broad Coverage reject for #{prospect.url}: #{signature_result.reject_reason}")
      failed_result(signature_result.reject_reason)
    end

    def fail_extraction_failed
      prospect.update!(research_failed: true, status: 'failed', failure_reason: 'OpenAI extraction failed')
      failed_result('OpenAI extraction failed')
    end

    def fail_parked_domain
      prospect.update!(
        research_failed: true,
        status: 'disqualified',
        is_b2b: false,
        b2b_b2c_status: 'b2c',
        failure_reason: 'Domain for sale or parked page—not a valid prospect'
      )
      failed_result('Domain for sale or parked page—not a valid prospect')
    end

    REJECT_REASON_MAP = {
      'manufacturer' => 'Manufacturer: OEM equipment maker — not a B2B partner prospect',
      'big_box_retailer' => 'Big-box retailer: mass-market B2C — not a B2B partner prospect',
      'fintech' => 'Fintech: contractor financing/leasing — excluded per client'
    }.freeze

    def fail_openai_reject(category)
      reason = REJECT_REASON_MAP[category.to_s] || "OpenAI reject: #{category}"
      prospect.update!(
        research_failed: true,
        status: 'disqualified',
        failure_reason: reason
      )
      Rails.logger.info("[ResearchService] OpenAI reject for #{prospect.url}: #{reason}")
      failed_result(reason)
    end

    def complete_research(extracted, markdown, signature_result)
      look_alike = compute_look_alike(metadata: extract_metadata_from_markdown(markdown), signature_result: signature_result)
      update_prospect(extracted, markdown, look_alike: look_alike, signature_result: signature_result)
      prospect.update!(status: 'disqualified') if extracted[:is_b2b] == false && extracted[:accept_category].blank?
      qualified, notes = qualify_for_track(extracted, signature_result)
      prospect.update!(failure_reason: notes) if prospect.respond_to?(:failure_reason=)
      prospect.update!(status: 'disqualified') unless qualified
      Result.new(
        prospect: prospect,
        b2b_b2c_status: extracted[:b2b_b2c_status],
        research_summary: extracted[:summary],
        qualified_for_track: qualified,
        vetting_notes: notes
      )
    end

    def run_signature_detector(markdown)
      metadata = extract_metadata_from_markdown(markdown)
      Research::SignatureDetector.call(metadata, url: prospect.url)
    end

    def extract_metadata_from_markdown(markdown)
      lines = markdown.to_s.split("\n")
      h1 = lines.find { |l| l.strip.start_with?('# ') }&.delete_prefix('# ')&.strip
      title = h1.presence || lines.first.to_s.strip
      desc = lines.reject { |l| l.strip.start_with?('#') }.first(3).join(' ').strip
      {
        title: title,
        description: desc,
        h1: h1,
        body_text: markdown.to_s
      }
    end

    def qualify_for_track(extracted, signature_result = nil)
      track = prospect.track || 'partner'
      status = extracted[:b2b_b2c_status]
      accept_category = extracted[:accept_category].presence

      case track
      when 'partner'
        b2b_ok = status == 'b2b' || accept_category.present?
        category_ok = matches_partner_category?(extracted) || accept_category.present?
        base_qualified = b2b_ok && category_ok
        gold_standard = Research::SignatureDetector.gold_standard_domain?(Outreach::UrlHelpers.extract_domain(prospect.url))
        scalable_ok = signature_result&.scalable_value != false
        qualified = if gold_standard
                     status == 'b2b'
                    elsif accept_category.present?
                     base_qualified
                    else
                     base_qualified && scalable_ok
                    end
        notes = qualified ? build_partner_pass_reason(extracted, signature_result, gold_standard, accept_category) : 'Not qualified: Partner track requires B2B (Tools, Software, Insurance) with broad coverage.'
        [qualified, notes]
      when 'pr'
        qualified = status == 'b2c' && matches_pr_category?(extracted)
        notes = qualified ? 'Passed: B2C local news/media, matches PR track.' : 'Not qualified: PR track requires B2C (local news, media).'
        [qualified, notes]
      else
        [false, "Unknown track: #{track}"]
      end
    end

    def build_partner_pass_reason(extracted, signature_result, gold_standard, accept_category = nil)
      reasons = ['Passed: B2B supplier']
      reasons << (accept_category.present? ? "(#{accept_category})" : matched_categories_summary(extracted))
      reasons << 'green industry theme'
      signal_source = if gold_standard
        'gold-standard partner DNA'
                      elsif accept_category.present?
        'OpenAI accept_category'
                      else
        'scalable signals'
                      end
      reasons << signal_source
      signals = signature_result&.signals_detected
      reasons << "(#{signals.map(&:to_s).join(', ')})" if signals&.any?
      "#{reasons.compact.join(', ')}."
    end

    def matched_categories_summary(extracted)
      text = [
        extracted[:observation],
        extracted[:target_persona],
        extracted[:summary],
        prospect.url
      ].compact.join(' ').downcase
      matched = PARTNER_CATEGORIES.select { |cat| text.include?(cat) }
      return nil if matched.empty?

      "(#{matched.first(3).join('/')})"
    end

    def matches_partner_category?(extracted)
      text = [
        extracted[:observation],
        extracted[:target_persona],
        extracted[:summary],
        prospect.url
      ].compact.join(' ').downcase
      PARTNER_CATEGORIES.any? { |cat| text.include?(cat) }
    end

    def matches_pr_category?(extracted)
      text = [extracted[:observation], extracted[:target_persona], prospect.url].compact.join(' ').downcase
      %w[news media newspaper tv radio local].any? { |kw| text.include?(kw) }
    end
  end
end

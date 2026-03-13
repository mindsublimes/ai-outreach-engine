# frozen_string_literal: true

module Research
  # SignatureDetector: Broad Coverage research engine.
  # Identifies high-leverage partners (Tools, SaaS) using positive signals.
  class SignatureDetector
    SIGNAL_A_KEYWORDS = [
      'professional-grade', 'save time', 'durability',
      'commercial-grade', 'heavy-duty', 'replacement parts', 'oem quality', 'fleet'
    ].freeze

    SIGNAL_B_KEYWORDS = [
      'business management', 'accounting',
      'scheduling', 'invoicing', 'crm', 'get paid', 'route optimization',
      'field service', 'software for', 'contractor app'
    ].freeze

    SIGNAL_C_KEYWORDS = [
      'wholesale', 'nationwide shipping', 'become a dealer',
      'bulk pricing', 'partner program', 'distributor', 'wholesale pricing',
      'landscape supply', 'parts supply'
    ].freeze

    LOCAL_REJECT_SIGNALS = [
      'local pickup only',
      'pickup only'
    ].freeze

    Result = Struct.new(
      :accepted,
      :reject_reason,
      :signals_detected,
      :is_manufacturer,
      :is_too_local,
      :scalable_value,
      keyword_init: true
    ) do
      def accepted?
        accepted
      end

      def rejected?
        !accepted
      end
    end

    def initialize(metadata = {}, url: nil)
      @title = metadata[:title].to_s
      @description = metadata[:description].to_s
      @h1 = metadata[:h1].to_s
      @body_text = metadata[:body_text].to_s
      @url = metadata[:url].presence || url
    end

    def self.call(metadata, url: nil)
      new(metadata, url: url).call
    end

    def call
      return gold_standard_result if gold_standard_bypass?

      combined = combined_text
      signals = detect_signals(combined)
      return too_local_result(signals) if too_local?(combined)

      build_final_result(signals)
    end

    def self.partner_domains
      dna_path = Rails.root.join('config', 'partners_dna.yml')
      return [] unless File.exist?(dna_path)

      dna = YAML.load_file(dna_path)
      return [] unless dna.is_a?(Hash)

      dna.values.flatten.filter_map { |e| e['domain'] if e.is_a?(Hash) }.compact
    end

    def self.gold_standard_domain?(domain)
      normalized = normalize_domain(domain)
      partner_domains.any? { |d| normalize_domain(d) == normalized }
    end

    def self.normalize_domain(domain)
      return '' if domain.blank?

      d = domain.to_s.downcase.strip
      d = d.delete_prefix('https://').delete_prefix('http://').split('/').first.to_s
      d = d.delete_prefix('www.')
      d.presence || ''
    end

    private

    attr_reader :title, :description, :h1, :body_text

    def gold_standard_bypass?
      @url.present? && self.class.gold_standard_domain?(@url)
    end

    def gold_standard_result
      Result.new(
        accepted: true,
        reject_reason: nil,
        signals_detected: [:gold_standard],
        is_manufacturer: false,
        is_too_local: false,
        scalable_value: true
      )
    end

    def too_local_result(signals)
      Result.new(
        accepted: false,
        reject_reason: 'Too local: pickup-only or single-city serving — not scalable',
        signals_detected: signals,
        is_manufacturer: false,
        is_too_local: true,
        scalable_value: false
      )
    end

    def build_final_result(signals)
      scalable_value = signals.any? { |s| %i[efficiency growth network gold_standard].include?(s) }
      Result.new(
        accepted: scalable_value,
        reject_reason: scalable_value ? nil : 'No broad-coverage signals: not Tools/Finance/SaaS with scalable value',
        signals_detected: signals,
        is_manufacturer: false,
        is_too_local: false,
        scalable_value: scalable_value
      )
    end

    def combined_text
      [title, description, h1, body_text].compact.join(' ').downcase
    end

    def detect_signals(text)
      signals = []
      signals << :efficiency if signal_a?(text)
      signals << :growth if signal_b?(text)
      signals << :network if signal_c?(text)
      signals
    end

    def signal_a?(text)
      SIGNAL_A_KEYWORDS.any? { |kw| text.include?(kw) }
    end

    def signal_b?(text)
      SIGNAL_B_KEYWORDS.any? { |kw| text.include?(kw) }
    end

    def signal_c?(text)
      SIGNAL_C_KEYWORDS.any? { |kw| text.include?(kw) }
    end

    def too_local?(text)
      LOCAL_REJECT_SIGNALS.any? do |signal|
        signal.is_a?(Regexp) ? text.match?(signal) : text.include?(signal)
      end
    end
  end
end

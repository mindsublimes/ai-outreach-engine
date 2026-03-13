# frozen_string_literal: true

module Research
  # Computes look_alike_score by comparing prospect metadata against ReferencePartner DNA.
  class LookAlikeScorer
    def initialize(prospect_metadata:, prospect_signals:)
      @metadata = prospect_metadata
      @signals = prospect_signals
    end

    def self.call(prospect_metadata:, prospect_signals:)
      new(prospect_metadata: prospect_metadata, prospect_signals: prospect_signals).call
    end

    def call
      return { score: nil, best_match: nil } if @signals.empty?

      return { score: 1.0, best_match: nil } if @signals.include?(:gold_standard)

      refs = ReferencePartner.by_display_order

      best_score = 0.0
      best_match = nil
      combined = combined_text

      refs.find_each do |ref|
        ref_signals = Array(ref.dna_signals).map(&:to_s).map(&:to_sym)
        next if ref_signals.empty?

        overlap = (@signals & ref_signals).size.to_f
        union = (@signals | ref_signals).size.to_f
        signal_score = union.positive? ? (overlap / union) : 0.0

        keyword_bonus = 0.0
        ref_signals.each do |sig|
          keywords = keywords_for_signal(sig)
          keyword_bonus += 0.1 if keywords.any? { |kw| combined.include?(kw) }
        end
        keyword_bonus = [keyword_bonus, 0.3].min

        total = (signal_score * 0.7) + (keyword_bonus * 0.3)
        total = [total, 1.0].min

        if total > best_score
          best_score = total
          best_match = ref
        end
      end

      { score: best_score.round(2), best_match: best_match }
    end

    private

    def combined_text
      [
        @metadata[:title],
        @metadata[:description],
        @metadata[:h1],
        @metadata[:body_text]
      ].compact.join(' ').downcase
    end

    def keywords_for_signal(signal)
      case signal.to_sym
      when :efficiency then SignatureDetector::SIGNAL_A_KEYWORDS
      when :growth then SignatureDetector::SIGNAL_B_KEYWORDS
      when :network then SignatureDetector::SIGNAL_C_KEYWORDS
      else []
      end
    end
  end
end

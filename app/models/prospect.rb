# frozen_string_literal: true

class Prospect < ApplicationRecord
  B2B_B2C_STATUSES = %w[b2b b2c unknown].freeze
  TRACKS = %w[partner pr].freeze
  STATUSES = %w[pending researching researched enriching enriched enrichment_failed out_of_credits ready_for_review approved drafted_in_gmail failed disqualified].freeze
  CATEGORIES = %w[Insurance Software Tools Equipment Legal Services].freeze
  PRIORITIES = %w[high normal low].freeze

  has_many :outreach_drafts, dependent: :destroy

  validates :url, presence: true, uniqueness: true
  validates :b2b_b2c_status, inclusion: { in: B2B_B2C_STATUSES }
  validates :track, inclusion: { in: TRACKS }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true

  scope :b2b, -> { where(b2b_b2c_status: 'b2b') }
  scope :b2c, -> { where(b2b_b2c_status: 'b2c') }
  scope :partner_track, -> { where(track: 'partner') }
  scope :pr_track, -> { where(track: 'pr') }
  scope :pending, -> { where(status: 'pending') }
  scope :researching, -> { where(status: 'researching') }
  scope :researched, -> { where(status: 'researched') }
  scope :enriched, -> { where(status: 'enriched') }
  scope :enrichment_failed, -> { where(status: 'enrichment_failed') }
  scope :out_of_credits, -> { where(status: 'out_of_credits') }
  scope :ready_for_review, -> { where(status: 'ready_for_review') }
  scope :drafted_in_gmail, -> { where(status: 'drafted_in_gmail') }
  scope :approved, -> { where(status: 'approved') }
  scope :research_failed, -> { where(research_failed: true) }
  scope :scalable, -> { where(is_scalable: true) }
  scope :high_priority, -> { where(priority: 'high') }

  def domain
    return nil if url.blank?
    uri = URI.parse(url)
    (uri.host || url).to_s.delete_prefix('www.').presence
  rescue URI::InvalidURIError
    url.to_s.delete_prefix('www.').delete_prefix('https://').delete_prefix('http://').split('/').first.presence
  end

  def display_label
    base = company_name.presence || domain
    if first_name.present? || last_name.present?
      "#{[first_name, last_name].compact.join(' ')} — #{base}"
    else
      base
    end
  end
end

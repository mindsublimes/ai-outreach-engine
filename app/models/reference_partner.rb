# frozen_string_literal: true

# Gold-standard partner reference from GreenPal Partner DNA.
# Used by the research pipeline to identify high-leverage partners
# and compute look_alike_score.
class ReferencePartner < ApplicationRecord
  validates :url, presence: true, uniqueness: true
  validates :domain, presence: true
  validates :category, inclusion: { in: %w[supplies finance saas hardware], allow_nil: true }

  scope :by_display_order, -> { order(:display_order, :id) }
  scope :by_category, ->(cat) { where(category: cat) }

  DNA_SIGNAL_TYPES = %w[efficiency growth network].freeze

  serialize :dna_signals, coder: JSON
end

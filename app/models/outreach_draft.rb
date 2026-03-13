# frozen_string_literal: true

class OutreachDraft < ApplicationRecord
  STATUSES = %w[draft approved sent].freeze

  belongs_to :prospect

  validates :subject, :body, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :drafts, -> { where(status: 'draft') }
  scope :approved, -> { where(status: 'approved') }
  scope :sent, -> { where(status: 'sent') }
end

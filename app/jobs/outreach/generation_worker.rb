# frozen_string_literal: true

module Outreach
  class GenerationWorker < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveRecord::RecordNotFound

    def perform(prospect_id)
      prospect = Prospect.find(prospect_id)
      result = Outreach::GenerationService.call(prospect)
      return if result.success?

      prospect.update!(status: 'failed', failure_reason: result.error.presence || 'Email generation failed')
    end
  end
end

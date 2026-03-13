# frozen_string_literal: true

module Outreach
  class EnrichmentWorker < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveRecord::RecordNotFound

    def perform(prospect_id)
      prospect = Prospect.find(prospect_id)
      return if prospect.status == 'out_of_credits'

      result = Outreach::EnrichmentService.call(prospect)

      Outreach::GenerationWorker.perform_later(prospect_id) if result.success?
    end
  end
end

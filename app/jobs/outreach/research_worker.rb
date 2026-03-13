# frozen_string_literal: true

module Outreach
  class ResearchWorker < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveRecord::RecordNotFound

    def perform(prospect_id)
      prospect = Prospect.find(prospect_id)
      result = Outreach::ResearchService.call(prospect)

      return if result.research_failed?
      return unless result.qualified?

      Outreach::EnrichmentWorker.perform_later(prospect_id)
    end
  end
end

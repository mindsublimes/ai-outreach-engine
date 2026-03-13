# frozen_string_literal: true

class PipelineController < ApplicationController
  def index
    recent = Prospect.where('created_at > ?', 30.days.ago)
    @prospects = recent.order(created_at: :desc).limit(200)
    @status_counts = recent.group(:status).count
  end

  def retry
    prospect = Prospect.find(params[:id])
    if prospect.status == 'enriched'
      Outreach::GenerationWorker.perform_later(prospect.id)
      redirect_to pipeline_path, notice: "Retrying generation for #{prospect.url}"
    elsif prospect.status == 'enrichment_failed'
      prospect.update!(status: 'enriching', failure_reason: nil)
      Outreach::EnrichmentWorker.perform_later(prospect.id)
      redirect_to pipeline_path, notice: "Retrying enrichment for #{prospect.url}"
    else
      prospect.update!(status: 'pending', research_failed: false, failure_reason: nil)
      Outreach::ResearchWorker.perform_later(prospect.id)
      redirect_to pipeline_path, notice: "Retrying research for #{prospect.url}"
    end
  end
end

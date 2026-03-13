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

  def clear
    count = Prospect.count
    OutreachDraft.delete_all
    Prospect.delete_all
    redirect_to pipeline_path, notice: "Cleared #{count} prospect(s) and all drafts."
  end

  def seed_status
    @ref_count = ReferencePartner.count
    @prospect_count = Prospect.count
    render :seed_status, layout: 'application'
  end

  def seed
    Rake::Task['partners_dna:seed'].reenable
    Rake::Task['partners_dna:seed'].invoke
    refs = ReferencePartner.count
    prospects = Prospect.count
    redirect_to pipeline_path, notice: "Seeded #{refs} reference partners and #{prospects} prospects."
  end
end

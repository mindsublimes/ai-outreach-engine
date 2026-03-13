# frozen_string_literal: true

class PipelineController < ApplicationController
  PER_PAGE = 25

  def index
    recent = Prospect.where('created_at > ?', 30.days.ago)
    @status_counts = recent.group(:status).count
    page = [params[:page].to_i, 1].max
    @prospects = recent.order(created_at: :desc).limit(PER_PAGE).offset((page - 1) * PER_PAGE)
    @total_count = recent.count
    @total_pages = [(@total_count.to_f / PER_PAGE).ceil, 1].max
    @current_page = page
    @per_page = PER_PAGE
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

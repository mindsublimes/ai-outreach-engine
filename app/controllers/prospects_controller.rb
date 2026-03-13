# frozen_string_literal: true

class ProspectsController < ApplicationController
  def index
    @prospects = Prospect.order(created_at: :desc).limit(50)
  end

  def create
    url = params[:url].to_s.strip
    url = "https://#{url}" if url.present? && !url.match?(%r{\Ahttps?://})

    if url.blank?
      redirect_to prospects_path, alert: 'Please enter a valid URL.'
      return
    end

    @prospect = Prospect.find_or_initialize_by(url: url)
    @prospect.assign_attributes(
      track: 'partner',
      status: 'pending',
      b2b_b2c_status: 'unknown'
    )
    @prospect.research_failed = false
    @prospect.failure_reason = nil

    if @prospect.save
      Outreach::ResearchWorker.perform_later(@prospect.id)
      redirect_to prospects_path, notice: "Queued research for #{url}"
    else
      redirect_to prospects_path, alert: @prospect.errors.full_messages.join(', ')
    end
  end

  def research_now
    @prospect = Prospect.find(params[:id])
    result = Outreach::ResearchService.call(@prospect)
    @prospect.reload

    if result.success?
      redirect_to prospects_path, notice: "Research complete. #{result.qualified? ? 'Qualified!' : 'Not qualified.'}"
    else
      redirect_to prospects_path, alert: "Research failed: #{result.error}"
    end
  end
end

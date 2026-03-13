# frozen_string_literal: true

class BulkImportsController < ApplicationController
  def new
  end

  def create
    urls = params[:urls].to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)

    if urls.size > 50
      redirect_to new_bulk_import_path, alert: 'Batch exceeds 50 URL limit.'
      return
    end

    urls.first(50).each do |raw_url|
      url = normalize_import_url(raw_url)
      next if url.blank?

      prospect = Prospect.find_or_create_by!(url: url)
      next unless prospect.status == 'pending'

      prospect.update!(status: 'researching')
      Outreach::ResearchWorker.perform_later(prospect.id)
    end

    redirect_to pipeline_path, notice: "Imported #{urls.size} prospects. Researching now."
  end

  private

  def normalize_import_url(raw)
    return nil if raw.blank?

    u = raw.to_s.strip
    u = "https://#{u}" unless u.match?(%r{\Ahttps?://})
    u.presence
  end
end

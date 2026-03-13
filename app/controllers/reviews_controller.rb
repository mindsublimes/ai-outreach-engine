# frozen_string_literal: true

class ReviewsController < ApplicationController
  def index
    @prospects = Prospect.where(status: %w[ready_for_review approved drafted_in_gmail]).order(created_at: :asc)
    @selected_prospect = Prospect.find_by(id: params[:id]) || @prospects.first
  end

  def approve
    prospect = Prospect.find(params[:id])
    if prospect.update(prospect_params)
      redirect_to reviews_path, notice: 'Changes saved.'
    else
      redirect_to reviews_path(id: prospect.id), alert: 'Could not save changes.'
    end
  end

  def push_to_gmail
    prospect = Prospect.find(params[:id])
    if prospect.email.blank?
      redirect_to reviews_path(id: prospect.id), alert: 'Email required. Run enrichment first or add recipient.'
      return
    end
    svc = Outreach::GmailService.new
    svc.create_draft(prospect)
    prospect.update!(status: 'drafted_in_gmail')
    email = svc.authenticated_email rescue nil
    notice = email.present? ? "Draft created! Check Gmail Drafts for #{email}" : 'Draft created in your Gmail account!'
    redirect_to reviews_path, notice: notice
  rescue Outreach::GmailService::Error => e
    redirect_to reviews_path(id: prospect.id), alert: "Gmail error: #{e.message}"
  rescue StandardError => e
    Rails.logger.warn("[GmailService] Error for prospect #{prospect.id}: #{e.message}")
    msg = if e.message.to_s.include?('unauthorized_client')
      "Gmail OAuth error: Ensure your refresh token was obtained with the SAME client ID/secret."
    else
      "Could not create draft: #{e.message}"
    end
    redirect_to reviews_path(id: prospect.id), alert: msg
  end

  private

  def prospect_params
    params.require(:prospect).permit(:generated_email_body, :generated_email_subject, :status)
  end
end

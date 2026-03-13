# frozen_string_literal: true

require 'google/apis/gmail_v1'
require 'signet/oauth_2/client'

module Outreach
  # Creates Gmail drafts via the Gmail API using OAuth.
  class GmailService
    class Error < StandardError; end

    def initialize(access_token: nil)
      @access_token = access_token || fetch_access_token
    end

    def create_draft(prospect)
      raise Error, 'Prospect email is required' if prospect.email.blank?
      raise Error, 'Generated subject is required' if prospect.generated_email_subject.blank?
      raise Error, 'Generated body is required' if prospect.generated_email_body.blank?

      mime = build_mime_message(
        to: prospect.email,
        subject: prospect.generated_email_subject,
        body: prospect.generated_email_body
      )
      message = Google::Apis::GmailV1::Message.new(raw: mime)
      draft = Google::Apis::GmailV1::Draft.new(message: message)

      gmail.create_user_draft('me', draft)
    end

    def authenticated_email
      profile = gmail.get_user_profile('me')
      profile.email_address
    end

    private

    attr_reader :access_token

    def gmail
      @gmail ||= begin
        svc = Google::Apis::GmailV1::GmailService.new
        svc.client_options.application_name = 'GreenPal Outreach'
        svc.authorization = authorization
        svc
      end
    end

    def authorization
      return nil if access_token.blank?

      Signet::OAuth2::Client.new(access_token: access_token)
    end

    def fetch_access_token
      creds = gmail_credentials
      token = creds[:access_token] || ENV['GMAIL_ACCESS_TOKEN']
      return token if token.present?

      refresh_token = creds[:refresh_token] || ENV['GMAIL_REFRESH_TOKEN']
      return nil if refresh_token.blank?

      client_id = creds[:client_id] || ENV['GMAIL_CLIENT_ID']
      client_secret = creds[:client_secret] || ENV['GMAIL_CLIENT_SECRET']
      return nil if client_id.blank? || client_secret.blank?

      client = Signet::OAuth2::Client.new(
        client_id: client_id,
        client_secret: client_secret,
        token_credential_uri: 'https://oauth2.googleapis.com/token',
        refresh_token: refresh_token
      )
      client.fetch_access_token!
      client.access_token
    end

    def gmail_credentials
      return {} unless Rails.application.respond_to?(:credentials) && Rails.application.credentials
      Rails.application.credentials[:gmail] || {}
    end

    def sender_email
      creds = gmail_credentials
      creds[:from_email] || ENV['GMAIL_FROM_EMAIL'] || 'outreach@yourgreenpal.com'
    end

    def build_mime_message(to:, subject:, body:)
      from = sender_email
      [
        "From: #{from}",
        "To: #{to}",
        "Subject: #{subject}",
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset=UTF-8',
        '',
        body
      ].join("\r\n")
    end
  end
end

# frozen_string_literal: true

require 'httparty'

module Outreach
  class FirecrawlService
    include HTTParty

    BASE_URL = 'https://api.firecrawl.dev/v1'
    TIMEOUT = 30

    class ScrapeError < StandardError; end

    def initialize(api_key: nil)
      @api_key = api_key || credentials(:firecrawl_api_key) || ENV['FIRECRAWL_API_KEY']
    end

    def scrape_markdown(url, wait_for: nil, actions: nil)
      return nil if @api_key.blank?
      return nil if url.blank?

      body = { url: url, formats: ['markdown'] }
      body[:waitFor] = wait_for if wait_for.present?
      body[:actions] = actions if actions.present?

      response = self.class.post(
        "#{BASE_URL}/scrape",
        headers: {
          'Authorization' => "Bearer #{@api_key}",
          'Content-Type' => 'application/json'
        },
        body: body.to_json,
        timeout: TIMEOUT
      )

      parse_response(response, url)
    rescue HTTParty::Error, Timeout::Error => e
      Rails.logger.warn("[FirecrawlService] Scrape failed for #{url}: #{e.message}")
      nil
    end

    private

    def credentials(key)
      return nil unless Rails.application.respond_to?(:credentials) && Rails.application.credentials
      Rails.application.credentials[key]
    end

    def parse_response(response, url)
      return nil unless response

      body = response.parsed_response
      return nil unless body.is_a?(Hash)

      if response.success?
        markdown = body.dig('data', 'markdown') || body['markdown']
        return markdown.to_s if markdown.present?
      end

      error_msg = body['error'] || body['message'] || "HTTP #{response.code}"
      Rails.logger.warn("[FirecrawlService] Scrape failed for #{url}: #{error_msg}")
      nil
    end
  end
end

# frozen_string_literal: true

require 'httparty'

module Outreach
  class RocketReachClient
    include HTTParty

    SEARCH_URL = 'https://api.rocketreach.co/v2/api/search'
    LOOKUP_URL = 'https://api.rocketreach.co/v2/api/person/lookup'

    class Error < StandardError; end
    class NoCreditsError < Error; end
    class PersonNotFoundError < Error; end
    class ApiError < Error; end

    class << self
      def search_person(domain:, title: nil)
        new.search_person(domain: domain, title: title)
      end

      def get_profile(id:)
        new.get_profile(id: id)
      end
    end

    def initialize(api_key: nil)
      @api_key = api_key || credentials(:rocket_reach_api_key) || credentials(:rocketreach_api_key) || ENV['ROCKETREACH_API_KEY']
    end

    def search_person(domain:, title: nil)
      if @api_key.blank?
        Rails.logger.warn('[RocketReachClient] API key blank - cannot search')
        return nil
      end

      sanitized_domain = sanitize_domain(domain)
      if sanitized_domain.blank?
        Rails.logger.warn("[RocketReachClient] domain blank after sanitize (input=#{domain.inspect})")
        return nil
      end

      query = { company_domain: [sanitized_domain] }
      query[:current_title] = [title] if title.present?

      body = { query: query, page_size: 1 }.to_json
      response = HTTParty.post(
        SEARCH_URL,
        headers: { 'Api-Key' => @api_key.to_s, 'Content-Type' => 'application/json' },
        body: body,
        timeout: 15
      )

      handle_search_response(response)
    rescue NoCreditsError, PersonNotFoundError
      nil
    rescue ApiError => e
      Rails.logger.warn("[RocketReachClient] API error: #{e.message}")
      nil
    end

    def get_profile(id:)
      return nil if @api_key.blank? || id.blank?

      response = self.class.get(
        "#{LOOKUP_URL}?id=#{id}",
        headers: headers,
        timeout: 15
      )

      handle_lookup_response(response)
    rescue PersonNotFoundError
      nil
    rescue ApiError => e
      Rails.logger.warn("[RocketReachClient] API error: #{e.message}")
      nil
    end

    private

    def credentials(key)
      return nil unless Rails.application.respond_to?(:credentials) && Rails.application.credentials
      Rails.application.credentials[key]
    end

    def headers
      {
        'Api-Key' => @api_key.to_s,
        'Content-Type' => 'application/json'
      }
    end

    def sanitize_domain(domain)
      return nil if domain.blank?

      domain = domain.to_s.strip.downcase
      domain = domain.gsub(%r{^https?://}, '').chomp('/')
      domain = domain.delete_prefix('www.').split('/').first
      domain.presence
    end

    def handle_search_response(response)
      return nil unless response

      raise NoCreditsError, 'RocketReach: rate limit or no credits left' if response.code == 429

      unless response.success?
        body = parse_json(response.body)
        msg = body['message'] || body['error'] || "HTTP #{response.code}"
        raise NoCreditsError, "RocketReach: #{msg}" if credits_error?(msg)
        raise PersonNotFoundError, "RocketReach: #{msg}" if person_not_found_error?(msg)
        raise ApiError, "RocketReach: #{msg}"
      end

      parse_json(response.body)
    end

    def handle_lookup_response(response)
      return nil unless response

      raise NoCreditsError, 'RocketReach: rate limit or no credits left' if response.code == 429
      raise PersonNotFoundError, 'RocketReach: person not found' if response.code == 404

      unless response.success?
        body = parse_json(response.body)
        msg = body['message'] || body['error'] || "HTTP #{response.code}"
        raise NoCreditsError, "RocketReach: #{msg}" if credits_error?(msg)
        raise PersonNotFoundError, "RocketReach: #{msg}" if person_not_found_error?(msg)
        raise ApiError, "RocketReach: #{msg}"
      end

      parse_json(response.body)
    end

    def credits_error?(message)
      return false unless message.is_a?(String)
      msg = message.downcase
      msg.include?('credit') || msg.include?('quota') || msg.include?('limit') || msg.include?('429')
    end

    def person_not_found_error?(message)
      return false unless message.is_a?(String)
      msg = message.downcase
      msg.include?('not found') || msg.include?('no person') || msg.include?('no results')
    end

    def parse_json(body)
      return {} if body.blank?
      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end
  end
end

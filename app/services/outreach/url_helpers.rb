# frozen_string_literal: true

module Outreach
  module UrlHelpers
    module_function

    def normalize_import_url(raw)
      return nil if raw.blank?

      u = raw.to_s.strip
      u = "https://#{u}" unless u.match?(%r{\Ahttps?://})
      u.presence
    end

    def extract_domain(url)
      return nil if url.blank?

      uri = URI.parse(url)
      domain = uri.host || url
      domain = domain.to_s.delete_prefix('www.')
      domain.presence
    rescue URI::InvalidURIError
      url.to_s.delete_prefix('www.').delete_prefix('https://').delete_prefix('http://').split('/').first.presence
    end
  end
end

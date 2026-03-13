# frozen_string_literal: true

namespace :partners_dna do
  desc 'Seed reference_partners (gold standard) and prospects from config/partners_dna.yml'
  task seed: :environment do
    dna_path = Rails.root.join('config', 'partners_dna.yml')
    unless File.exist?(dna_path)
      puts "partners_dna.yml not found at #{dna_path}"
      next
    end

    dna = YAML.load_file(dna_path)
    unless dna.is_a?(Hash)
      puts 'partners_dna.yml must be a Hash with category keys'
      next
    end

    display_order = 0
    seeded_refs = 0
    seeded_prospects = 0

    dna.each do |category_key, entries|
      next unless entries.is_a?(Array)

      entries.each do |entry|
        next unless entry.is_a?(Hash) && entry['domain'].present?

        domain = entry['domain'].to_s.strip.downcase
        url = domain.start_with?('http') ? domain : "https://#{domain}"
        name = entry['name'].presence || domain
        category = entry['category'].presence || category_key.to_s
        dna_signals = Array(entry['dna_signals']).map(&:to_s)
        about_summary = entry['about_summary'].presence || "Gold standard #{category} partner."

        ref = ReferencePartner.find_or_initialize_by(url: url)
        ref.assign_attributes(
          domain: domain,
          name: name,
          category: category,
          dna_signals: dna_signals,
          about_summary: about_summary,
          products_summary: about_summary,
          display_order: display_order
        )
        seeded_refs += 1 if ref.save
        display_order += 1

        prospect = Prospect.find_or_initialize_by(url: url)
        prospect.assign_attributes(
          track: 'partner',
          status: 'pending',
          b2b_b2c_status: 'unknown',
          company_name: name,
          priority: 'high',
          is_scalable: true
        )
        seeded_prospects += 1 if prospect.save
      end
    end

    puts "Partners DNA seed complete: #{seeded_refs} reference_partners, #{seeded_prospects} prospects (Gold Standard)"
  end

  desc 'Run research on a URL. Usage: rake partners_dna:research URL=https://www.mowmore.com'
  task research: :environment do
    url = ENV['URL'] || 'https://www.mowmore.com'
    prospect = Prospect.find_or_create_by!(url: url) do |p|
      p.track = 'partner'
      p.status = 'pending'
      p.b2b_b2c_status = 'unknown'
    end
    prospect.update!(status: 'pending', research_failed: false, failure_reason: nil)

    puts "Running research on: #{url}"
    result = Outreach::ResearchService.call(prospect)
    prospect.reload

    if result.success?
      puts "✅ ACCEPTED | Priority: #{prospect.priority} | Score: #{prospect.look_alike_score}"
      puts "Notes: #{prospect.failure_reason}"
    else
      puts "❌ REJECTED | Reason: #{result.error}"
    end
  end

  desc 'Queue research pipeline for a URL. Usage: rake partners_dna:queue URL=https://www.mowmore.com'
  task queue: :environment do
    url = ENV['URL']
    raise 'Usage: rake partners_dna:queue URL=https://example.com' if url.blank?

    prospect = Prospect.find_or_create_by!(url: url) do |p|
      p.track = 'partner'
      p.status = 'pending'
      p.b2b_b2c_status = 'unknown'
    end
    prospect.update!(status: 'pending', research_failed: false, failure_reason: nil)

    Outreach::ResearchWorker.perform_later(prospect.id)
    puts "Queued research pipeline for: #{url} (prospect_id=#{prospect.id})"
  end
end

require "json"

class BookClubDnaJob < ApplicationJob
  queue_as :default

  # Owner/admin-triggered: produce the club's Literature DNA (deterministic
  # collector + sandboxed AI analysis) and persist it on the club record.
  def perform(club_id)
    club = BookClub.find_by(id: club_id)
    return if club.blank?

    unless OtariClient.configured?
      Rails.logger.tagged("[dna ##{club_id}]") { |l| l.error("aborted: Otari is not configured (OTARI_BASE_URL / OTARI_API_KEY)") }
      return
    end
    return if club.dna_generated_at.present?

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Rails.logger.tagged("[dna ##{club_id}]") { |l| l.info("background job started") }

    result = ClubLiteratureDna.new(club: club).generate!
    if result.dna.present?
      club.update!(literature_dna: result.dna, dna_generated_at: Time.current)
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    Rails.logger.tagged("[dna ##{club_id}]") do |l|
      l.info("background job done in #{elapsed.round(1)}s: highlights=#{result.dna&.dig('narrative', 'highlights').to_a.size}")
    end
  rescue StandardError => e
    Rails.logger.tagged("[dna ##{club_id}]") { |l| l.error("background job failed: #{e.class} #{e.message}") }
    raise
  end
end

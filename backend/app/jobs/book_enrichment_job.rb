class BookEnrichmentJob < ApplicationJob
  queue_as :default

  # Full admin-button flow: AI metadata enrichment (grounded + judged) and the
  # cover swap when the judge calls for it. Runs in the background so the
  # admin request returns immediately.
  def perform(book_id)
    book = Book.find_by(id: book_id)
    return if book.blank?

    # Configuration can drift between enqueue and execution (restarts, deploy
    # envs). Fail fast, loudly, without leaving partial state.
    unless OtariClient.configured?
      Rails.logger.tagged("[enrich ##{book_id}]") { |l| l.error("aborted: Otari is not configured (OTARI_BASE_URL / OTARI_API_KEY)") }
      return
    end

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Rails.logger.tagged("[enrich ##{book_id}]") { |l| l.info("background job started") }

    result = BookMetadataEnricher.new(book: book).enrich!

    cited = (book.reload.enrichment.dig("cover_judgment") || {})["source_url"]
    if %w[missing low_quality].include?(result.cover_judgment.to_s) || placeholder_cover?(book)
      BookCoverImprover.new(book: book, cited_cover_url: cited).improve!
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    book.reload
    Rails.logger.tagged("[enrich ##{book_id}]") do |l|
      l.info("background job done in #{elapsed.round(1)}s: desc=#{result.description_changed} " \
        "country=#{result.country_of_origin.inspect} cover=#{(book.enrichment || {}).dig('cover', 'new_cover').to_s[0, 80]}")
    end
  rescue StandardError => e
    Rails.logger.tagged("[enrich ##{book_id}]") { |l| l.error("background job failed: #{e.class} #{e.message}") }
    raise
  end

  private

  def placeholder_cover?(book)
    BookCoverImprover::COVER_PLACEHOLDER_HOSTS.any? { |ph| book.cover_image.to_s.include?(ph) }
  end
end

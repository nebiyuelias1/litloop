class BookEnrichmentJob < ApplicationJob
  queue_as :default

  def perform(book_id)
    book = Book.find_by(id: book_id)
    return if book.blank? || book.enriched_at.present?

    BookMetadataEnricher.new(book: book).enrich!
  end
end

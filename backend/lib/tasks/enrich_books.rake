namespace :books do
  desc "AI-enrich book metadata via Otari (description, tags, country of origin). LIMIT=n to cap how many books are processed."
  task enrich: :environment do
    limit = ENV["LIMIT"].presence&.to_i
    books = Book.where(enriched_at: nil).order(created_at: :desc)
    books = books.limit(limit) if limit

    puts "Enriching #{books.count} books..."
    enriched = 0
    failed = 0

    books.find_each do |book|
      result = BookMetadataEnricher.new(book: book).enrich!
      puts "#{book.title} — tags=#{result.tags_added.join(', ')} country=#{result.country_of_origin} confidence=#{result.confidence}"
      enriched += 1
    rescue OtariClient::RequestError, OtariClient::ConfigurationError => e
      puts "FAILED #{book.title}: #{e.message}"
      failed += 1
      next
    end

    if ENV["IMPROVE_COVERS"] == "1"
      Rake::Task["books:improve_covers"].invoke
    end

    puts "Done. enriched=#{enriched} failed=#{failed}"
  end
end

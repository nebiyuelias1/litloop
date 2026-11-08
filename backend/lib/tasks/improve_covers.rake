namespace :books do
  desc "AI-improve book covers via Otari web search. LIMIT=n to cap how many books are processed, FORCE=1 to re-run for enriched books."
  task improve_covers: :environment do
    limit = ENV["LIMIT"].presence&.to_i
    scope = Book.where.not(cover_image: nil)
    scope = scope.where(enriched_at: nil) unless ENV["FORCE"]
    scope = scope.limit(limit) if limit

    puts "Improving covers for #{scope.count} books..."
    improved = 0
    kept = 0

    scope.find_each do |book|
      result = BookCoverImprover.new(book: book).improve!
      if result.improved
        puts "IMPROVED #{book.title}: #{result.old_cover} -> #{result.new_cover}"
        improved += 1
      else
        puts "KEPT #{book.title}: #{result.reason}"
        kept += 1
      end
    rescue OtariClient::Error => e
      puts "FAILED #{book.title}: #{e.message}"
    end

    puts "Done. improved=#{improved} kept=#{kept}"
  end
end

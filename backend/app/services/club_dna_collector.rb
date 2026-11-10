# frozen_string_literal: true

# Builds the verified, deterministic dataset that describes a book club's
# "Literature DNA" — everything here comes straight from SQL over the club's
# reading sessions and the book metadata, plus the enrichment pipeline's
# verified country codes. No model is involved in producing these numbers;
# the AI narrative layer may only quote what this dataset says.
class ClubDnaCollector
  Result = Struct.new(:data, keyword_init: true)

  def initialize(club:)
    @club = club
  end

  # Structured dataset shared verbatim with the AI layer and the UI.
  def collect!
    reads = @club.book_reads.includes(:book, :book_read_rsvps).order(:meetup_time)
    past = reads.select { |r| r.meetup_time < Time.current }
    upcoming = reads.select { |r| r.meetup_time >= Time.current }
    # A re-read of the same book is one data point for taste (map tones,
    # tags, regions) even though both sessions count in reads.total.
    read_books = reads.filter_map(&:book).uniq

    Result.new(data: {
      "club" => { "name" => @club.name, "member_count" => @club.book_club_members_count },
      "reads" => {
        "total" => reads.size,
        "past" => past.size,
        "upcoming" => upcoming.size,
        "first_meetup" => reads.first&.meetup_time&.iso8601,
        "last_meetup" => past.last&.meetup_time&.iso8601,
        "poll_only" => reads.count { |r| r.book.blank? },
        "avg_turnout" => turnout(past)
      },
      "countries" => countries(read_books),
      "regions" => regions(read_books),
      "tags" => tags(read_books),
      "languages" => languages(read_books),
      "authors" => authors(read_books)
    })
  end

  private

  # Country ISO code -> {name, flag, count, titles}. Only books carrying a
  # verified ISO code (set by the enrichment pipeline's gates) count here.
  def countries(books)
    counts = Hash.new(0)
    books.each { |book| counts[book.country_of_origin] += 1 if book.country_of_origin.present? }

    counts.sort_by { |code, count| [ -count, code ] }.to_h do |code, count|
      [ code, {
        "name" => CountryCodes.name_for(code),
        "flag" => CountryCodes.flag_for(code),
        "count" => count,
        "titles" => books.select { |b| b.country_of_origin == code }.map(&:title)
      } ]
    end
  end

  def regions(books)
    counts = Hash.new(0)
    books.each do |book|
      next if book.country_of_origin.blank?

      region = CountryCodes.region_for(book.country_of_origin)
      counts[region] += 1 if region
    end
    counts.sort_by { |_region, count| -count }.to_h
  end

  # Tags counted across the books the club actually read (or lined up).
  def tags(books)
    counts = Hash.new(0)
    BookTag.where(book_id: books).includes(:tag).find_each do |book_tag|
      name = book_tag.tag&.name
      counts[name] += 1 if name.present?
    end
    counts.sort_by { |_tag, count| -count }.to_h
  end

  def languages(books)
    counts = Hash.new(0)
    books.each { |book| counts[book.language.presence || "unknown"] += 1 }
    counts.sort_by { |_lang, count| -count }.to_h
  end

  def authors(books)
    counts = Hash.new(0)
    books.each { |book| counts[book.author.presence || "unknown"] += 1 }
    counts.sort_by { |_author, count| -count }.first(10).to_h
  end

  # Average RSVPs per *past* session (RSVPs are already preloaded).
  def turnout(past_reads)
    return nil if past_reads.empty?

    total = past_reads.sum { |r| r.book_read_rsvps.size }
    (total.to_f / past_reads.size).round(1)
  end
end

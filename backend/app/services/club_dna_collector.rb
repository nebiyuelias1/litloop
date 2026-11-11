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
      "months" => months(reads),
      "engagement" => engagement(past),
      "discussion" => discussion(past),
      "pages" => pages(read_books),
      "ratings" => ratings(read_books),
      "weekday" => weekday(past),
      "time_of_day" => time_of_day(past),
      "locations" => locations(past),
      "cadence_days" => cadence(past),
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

  # Reads grouped into calendar months (YYYY-MM -> count), oldest first —
  # the Visualization timeline mini-bars.
  def months(reads)
    counts = Hash.new(0)
    reads.each { |r| counts[r.meetup_time.strftime("%Y-%m")] += 1 }
    counts.sort.to_h
  end

  # Going-RSVP turnout per past session + the average. Turnout is the
  # club's health metric; RSVPs are preloaded.
  def engagement(past_reads)
    per = past_reads.map { |r| r.book_read_rsvps.count(&:going?) }
    {
      "per_session" => per,
      "total_going" => per.sum,
      "avg_turnout" => per.empty? ? nil : (per.sum.to_f / per.size).round(1)
    }
  end

  def discussion(past_reads)
    per = past_reads.map { |r| r.discussion_questions.size }
    {
      "total" => per.sum, "max" => per.max || 0,
      "avg_per_meetup" => per.empty? ? nil : (per.sum.to_f / per.size).round(1),
      "per_session" => per
    }
  end

  # Books table page_count where it exists (not AI-maintained — read-only).
  def pages(books)
    known = books.filter_map do |book|
      next if book.page_count.blank? || book.page_count.zero?

      [ book.title, book.page_count ]
    end
    return nil if known.empty?

    counts = known.map(&:last)
    {
      "avg" => (counts.sum.to_f / counts.size).round,
      "min" => counts.min,
      "max" => counts.max,
      "per_book" => known.sort_by(&:last).reverse.to_h
    }
  end

  # Average user rating per read book (read-only from the ratings table).
  def ratings(books)
    counts = Hash.new(0.0)
    books.each do |book|
      next if book.ratings.empty?

      counts[book.title] = book.ratings.average(:score).round(1)
    end
    counts.sort_by { |_title, score| -score }.to_h
  end

  def weekday(past_reads)
    counts = Hash.new(0)
    past_reads.each { |r| counts[r.meetup_time.strftime("%a")] += 1 }
    counts.sort_by { |_d, n| -n }.to_h
  end

  TIME_BUCKETS = { "morning" => 5..11, "afternoon" => 12..16, "evening" => 17..22 }.freeze
  def time_of_day(past_reads)
    counts = Hash.new(0)
    past_reads.each do |r|
      hour = r.meetup_time.hour
      bucket = TIME_BUCKETS.find { |_name, range| range.cover?(hour) }
      counts[bucket&.first || "night"] += 1
    end
    counts.sort_by { |_t, _n| -_n }.to_h
  end

  def locations(past_reads)
    counts = Hash.new(0)
    past_reads.each { |r| counts[r.meetup_location.to_s.truncate(24)] += 1 if r.meetup_location.present? }
    counts.sort_by { |_l, n| -n }.to_h
  end

  # Average number of days between consecutive past meetups (nil if fewer
  # than two past sessions).
  def cadence(past_reads)
    times = past_reads.map(&:meetup_time).sort
    return nil if times.size < 2

    gaps = times.each_cons(2).map { |a, b| (b - a) / 1.day }
    (gaps.sum / gaps.size).round(1)
  end

  # Average RSVPs per *past* session (RSVPs are already preloaded).
  def turnout(past_reads)
    return nil if past_reads.empty?

    total = past_reads.sum { |r| r.book_read_rsvps.size }
    (total.to_f / past_reads.size).round(1)
  end
end

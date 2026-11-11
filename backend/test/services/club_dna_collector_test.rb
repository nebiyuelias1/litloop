require "test_helper"

class ClubDnaCollectorTest < ActiveSupport::TestCase
  test "aggregates countries, regions, tags, languages and turnout deterministically" do
    club = BookClub.create!(name: "Dna Club", owner: users(:one))

    et = Book.create!(title: "ኦሮማይ", author: "በዓሉ ግርማ", description: "Amharic novel", language: "am", country_of_origin: "ET")
    br = Book.create!(title: "The Alchemist", author: "Paulo Coelho", description: "Brazilian classic", language: "en", country_of_origin: "BR")
    no_country = Book.create!(title: "Unverified", author: "Anon", description: "No origin yet", language: "en")

    fiction = Tag.create!(name: "fiction")
    BookTag.create!(book: et, tag: fiction)
    BookTag.create!(book: br, tag: fiction)
    BookTag.create!(book: no_country, tag: Tag.create!(name: "orphan"))

    BookRead.new(book: et, book_club: club, host: users(:one), meetup_time: 30.days.ago, meetup_location: "Cafe 1").tap { |r| r.save!(validate: false) }
    read2 = BookRead.new(book: br, book_club: club, host: users(:one), meetup_time: 10.days.ago, meetup_location: "Cafe 2").tap { |r| r.save!(validate: false) }
    BookReadRsvp.create!(book_read: read2, user: users(:two), status: :going)
    # upcoming session: poll-only, no book chosen yet
    BookRead.new(book_club: club, host: users(:one), meetup_time: 10.days.from_now, meetup_location: "Cafe 3").tap { |r| r.save!(validate: false) }

    data = ClubDnaCollector.new(club: club).collect!.data

    assert_equal({ "ET" => 1, "BR" => 1 }, data["countries"].transform_values { |v| v["count"] })
    assert_equal "Ethiopia", data["countries"].dig("ET", "name")
    assert_equal "🇪🇹", data["countries"].dig("ET", "flag")
    assert_includes data["countries"].dig("ET", "titles"), "ኦሮማይ"
    # books without a verified origin never leak into the map data
    assert_nil data["countries"].keys.find { |c| data["countries"][c]["name"].nil? }

    assert_equal({ "Africa" => 1, "South America" => 1 }, data["regions"])
    assert_equal 2, data["tags"]["fiction"]
    assert_equal(0.5, data["reads"]["avg_turnout"])
    # timeline: 2 past reads in distinct recent months
    assert data["months"].is_a?(Hash)
    assert data["months"].values.sum >= 2
    assert_equal 1, data["engagement"]["total_going"]
    assert_equal 0.5, data["engagement"]["avg_turnout"]
    assert_equal 2, data["engagement"]["per_session"].size
    assert data["weekday"].all? { |d, _| %w[Mon Tue Wed Thu Fri Sat Sun].include?(d) }
    assert data["time_of_day"].is_a?(Hash)
    assert_includes data["locations"].keys, "Cafe 1"
    assert data["cadence_days"].present?
    assert_equal 3, data["reads"]["total"]
    assert_equal 2, data["reads"]["past"]
    assert_equal 1, data["reads"]["upcoming"]
    assert_equal 1, data["reads"]["poll_only"] # upcoming session has no book yet
  end

  test "counts a book only once per country even when read twice" do
    club = BookClub.create!(name: "Re-read Club", owner: users(:one))
    book = Book.create!(title: "Sapiens", author: "Harari", description: "history", language: "en", country_of_origin: "IL")

    2.times do |i|
      BookRead.new(book: book, book_club: club, host: users(:one), meetup_time: (5 + i).days.ago, meetup_location: "Cafe").tap { |r| r.save!(validate: false) }
    end

    data = ClubDnaCollector.new(club: club).collect!.data
    assert_equal 1, data["countries"]["IL"]["count"]
    assert_equal({ "Asia" => 1 }, data["regions"])
  end

  test "sequence, taste and questions feed the new panels from verified data" do
    club = BookClub.create!(name: "Panels Club", owner: users(:one))

    first = Book.create!(title: "First", author: "A", description: "x", language: "en", page_count: 200)
    second = Book.create!(title: "Second", author: "B", description: "x", language: "en", page_count: 400)
    tag = Tag.create!(name: "war")
    BookTag.create!(book: first, tag: tag)
    BookTag.create!(book: second, tag: tag)

    read1 = BookRead.new(book: first, book_club: club, host: users(:one), meetup_time: 40.days.ago).tap { |r| r.save!(validate: false) }
    read2 = BookRead.new(book: second, book_club: club, host: users(:one), meetup_time: 10.days.ago).tap { |r| r.save!(validate: false) }

    DiscussionQuestion.create!(book_read: read1, content: "What is home?", position: 1)
    DiscussionQuestion.create!(book_read: read2, content: "Who decides?", position: 1)

    Rating.create!(user: users(:one), book: second, score: 2.0)
    Rating.create!(user: users(:two), book: second, score: 5.0)
    Rating.create!(user: users(:one), book: first, score: 4.0)
    Rating.create!(user: users(:two), book: first, score: 4.0)

    data = ClubDnaCollector.new(club: club).collect!.data

    # sequence: meetup order, verified attributes only
    assert_equal %w[First Second], data["sequence"].map { |s| s["title"] }
    assert_equal 200, data["sequence"][0]["pages"]
    assert_equal 400, data["sequence"][1]["pages"]
    assert_equal [ "war" ], data["sequence"][0]["tags"]

    # taste: ordered by disagreement, aggregates only
    assert_equal "Second", data["taste"].first["title"]
    assert_equal 2.0, data["taste"].first["min"]
    assert_equal 5.0, data["taste"].first["max"]
    assert_equal 3.5, data["taste"].first["avg"]
    assert_equal 2, data["taste"].first["n"]
    assert_equal 4.0, data["taste"].second["avg"]

    # questions: verbatim text, grouped with their read
    texts = data["questions"].map { |q| q["text"] }
    assert_includes texts, "What is home?"
    assert_includes texts, "Who decides?"
    assert_equal "First", data["questions"].first["book"]
  end
end

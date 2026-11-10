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
end

require "test_helper"

class BookClubsDnaControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @club = BookClub.create!(name: "Dna Route Club", owner: users(:one))
    ENV["OTARI_API_KEY"] = "tk-test"
    ENV["OTARI_BASE_URL"] = "https://gateway.test/v1"
  end

  test "requires login" do
    post generate_dna_book_club_url(@club)
    assert_redirected_to new_user_session_path
  end

  test "queues generation for the club owner" do
    sign_in users(:one)
    queued = []
    BookClubDnaJob.stub(:perform_later, ->(club_id, user_id) { queued << [ club_id, user_id ] }) do
      post generate_dna_book_club_url(@club)
    end

    assert_redirected_to book_club_url(@club)
    assert_match(/queued/, flash[:notice])
    assert_equal [ [ @club.id, users(:one).id ] ], queued
  end

  test "redirects with alert when the monthly budget is exhausted" do
    owner = users(:two) # non-admin
    club = BookClub.create!(name: "Budgeted Club", owner: owner)
    5.times { OtariBudget.record!(user: owner, feature: "dna_generation") }

    sign_in owner
    queued = []
    BookClubDnaJob.stub(:perform_later, ->(*_args) { queued << _args }) do
      post generate_dna_book_club_url(club)
    end

    assert_redirected_to book_club_url(club)
    assert_match(/budget/i, flash[:alert])
    assert_empty queued
  end

  test "admin is exempt from the budget" do
    5.times { OtariBudget.record!(user: users(:one), feature: "dna_generation") }

    sign_in users(:one)
    queued = []
    BookClubDnaJob.stub(:perform_later, ->(*_args) { queued << _args }) do
      post generate_dna_book_club_url(@club)
    end

    assert_redirected_to book_club_url(@club)
    assert_match(/queued/, flash[:notice])
    assert_not_empty queued
  end

  test "forbids non-owner members" do
    sign_in users(:two)
    BookClubMember.create!(user: users(:two), book_club: @club, role: :member)

    post generate_dna_book_club_url(@club)
    assert_response :forbidden
  end

  test "redirects with alert when Otari is not configured" do
    sign_in users(:one)
    ENV["OTARI_API_KEY"] = ""
    post generate_dna_book_club_url(@club)

    assert_redirected_to book_club_url(@club)
    assert_match(/not configured/, flash[:alert])
  end

  test "show page renders the dna panel and world map once generated" do
    @club.update!(
      literature_dna: {
        "narrative" => {
          "identity" => "A club that reads Ethiopian history in translation.",
          "signatures" => [ { "title" => "Localist", "note" => "3 of 3 from ET" } ],
          "highlights" => [ { "dataset_path" => "reads.past", "value" => 3, "comment" => "track record" } ],
          "gaps" => [ "try Latin America" ],
          "recommendation" => "Read Borges next."
        },
        "dataset" => {
          "reads" => { "total" => 3, "past" => 3, "upcoming" => 0, "first_meetup" => nil,
            "last_meetup" => nil, "poll_only" => 0, "avg_turnout" => nil },
          "months" => { "2026-10" => 2, "2026-11" => 1 },
          "engagement" => { "per_session" => [ 2, 3, 1 ], "total_going" => 6, "avg_turnout" => 2.0 },
          "discussion" => { "total" => 5, "max" => 3, "avg_per_meetup" => 1.7, "per_session" => [ 2, 3, 0 ] },
          "weekday" => { "Sat" => 2, "Sun" => 1 },
          "time_of_day" => { "afternoon" => 3 },
          "locations" => { "Cafe" => 3 },
          "cadence_days" => 12.0,
          "countries" => { "ET" => { "name" => "Ethiopia", "flag" => "🇪🇹", "count" => 3, "titles" => [] } },
          "regions" => { "Africa" => 3 },
          "languages" => { "am" => 2, "en" => 1 },
          "tags" => { "history" => 2 },
          "pages" => { "avg" => 205, "min" => 200, "max" => 209, "per_book" => { "ኦሮማይ" => 200, "Things Fall Apart" => 209 } },
          "ratings" => { "Things Fall Apart" => 4.5 },
          "authors" => {}
        },
        "model" => "openai/gpt-oss-120b",
        "sandbox_calls" => [ { "code" => "print(3)", "stdout" => "3\n", "exit_code" => 0 } ],
        "generated_at" => Time.current.iso8601
      },
      dna_generated_at: Time.current
    )

    BookRead.new(
      book: Book.create!(title: "ኦሮማይ", author: "በዓሉ ግርማ", description: "x", language: "am",
        country_of_origin: "ET", cover_image: "https://images.example/oromay.jpg"),
      book_club: @club, host: users(:one), meetup_time: 30.days.ago, meetup_location: "Cafe"
    ).tap { |r| r.save!(validate: false) }

    sign_in users(:one)
    get book_club_url(@club)
    assert_response :success

    body = response.body
    assert_includes body, "Literature DNA"
    # the cover strip was removed in v4 — DNA is analytics only
    refute_includes body, "The reading journey"
    assert_includes body, "Where these stories come from"
    assert_includes body, "data-dna-country=\"ET\""
    assert_includes body, "dna-map" # zoom/pan controller hook
    assert_includes body, "Theme composition"
    assert_includes body, "World composition"
    assert_includes body, "Attendance"
    assert_includes body, "When the club meets"
    assert_includes body, "Conversation depth"
    # rhythm month-bars were folded into "When the club meets"; the page-bars
    # and rating-bars were replaced by the difficulty and taste panels
    refute_includes body, "Reading rhythm"
    refute_includes body, "Book length"
    refute_includes body, "How members rated them"

    # no stat tiles, no AI commentary, no python-speak
    refute_includes body, "python"
    refute_includes body, "At a glance"
    refute_includes body, "commentary on this DNA"
    refute_includes body, "At a glance"
  end
end

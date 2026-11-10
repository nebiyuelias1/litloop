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
    BookClubDnaJob.stub(:perform_later, ->(club_id) { queued << club_id }) do
      post generate_dna_book_club_url(@club)
    end

    assert_redirected_to book_club_url(@club)
    assert_match(/queued/, flash[:notice])
    assert_equal [ @club.id ], queued
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
          "countries" => { "ET" => { "name" => "Ethiopia", "flag" => "🇪🇹", "count" => 3, "titles" => [] } },
          "regions" => { "Africa" => 3 },
          "tags" => { "history" => 2 },
          "languages" => { "am" => 3 },
          "authors" => {}
        },
        "model" => "openai/gpt-oss-120b",
        "sandbox_calls" => [ { "code" => "print(3)", "stdout" => "3\n", "exit_code" => 0 } ],
        "generated_at" => Time.current.iso8601
      },
      dna_generated_at: Time.current
    )

    sign_in users(:one)
    get book_club_url(@club)
    assert_response :success

    body = response.body
    assert_includes body, "Literature DNA"
    assert_includes body, "A club that reads Ethiopian history in translation."
    assert_includes body, "data-dna-country=\"ET\""
    assert_includes body, "Ethiopia"
    assert_includes body, "openai/gpt-oss-120b"
  end
end

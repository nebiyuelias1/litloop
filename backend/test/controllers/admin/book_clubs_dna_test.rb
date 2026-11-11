require "test_helper"

class Admin::BookClubsDnaTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
    @club = BookClub.create!(name: "Admin Dna Club", owner: users(:one),
      literature_dna: {
        "dataset" => { "reads" => { "past" => 2 } },
        "charts" => { "data_uri" => "data:image/png;base64,QUJD", "file_id" => "file-x", "bytes" => 9000, "model" => "openai/gpt-oss-120b", "code" => "print(1)" },
        "sandbox_calls" => [ { "code" => "print(1)", "stdout" => "1\n", "exit_code" => 0 } ],
        "model" => "openai/gpt-oss-120b",
        "generated_at" => Time.current.iso8601
      },
      dna_generated_at: Time.current)
  end

  test "admin club show renders the dna audit section without the base64 blob" do
    get admin_book_club_path(@club)
    assert_response :success
    body = response.body
    assert_includes body, "Literature DNA audit"
    assert_includes body, "file-x"
    assert_includes body, "print(1)"
    assert_includes body, "data:image/png;base64,QUJD" # the <img> render
    assert_not_includes body, "\"data_uri\"" # stripped from the JSON dump
  end

  test "audit section absent for clubs without dna" do
    plain = BookClub.create!(name: "Plain Club", owner: users(:one))
    get admin_book_club_path(plain)
    assert_response :success
    refute_includes response.body, "Literature DNA audit"
  end
end

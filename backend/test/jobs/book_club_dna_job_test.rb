require "test_helper"

class BookClubDnaJobTest < ActiveSupport::TestCase
  include Devise::Test::IntegrationHelpers

  setup do
    ENV["OTARI_API_KEY"] = "tk-test"
    ENV["OTARI_BASE_URL"] = "https://gateway.test/v1"
    @club = BookClub.create!(name: "Dna Job Club", owner: users(:one))
  end

  test "aborts cleanly when Otari is not configured" do
    ENV["OTARI_API_KEY"] = ""
    BookClubDnaJob.new.perform(@club.id)
    assert_nil @club.reload.dna_generated_at
  end

  test "persists the generated dna on the club" do
    create_past_read!

    client = Object.new
    client.define_singleton_method(:chat) do |**kwargs|
      {
        "choices" => [ { "message" => { "content" => '{"identity": "Text history lovers club.", "signatures": [], "highlights": [], "gaps": [], "recommendation": ""}' } } ],
        "otari_tool_calls" => []
      }
    end
    OtariClient.stub(:new, client) do
      BookClubDnaJob.new.perform(@club.id)
    end

    assert_not_nil @club.reload.dna_generated_at
    assert_equal "Text history lovers club.", @club.literature_dna.dig("narrative", "identity")
  end

  test "does not overwrite an existing dna silently" do
    create_past_read!
    @club.update!(literature_dna: { "narrative" => { "identity" => "kept" } }, dna_generated_at: 1.day.ago)
    called = false
    client = Object.new
    client.define_singleton_method(:chat) { |**_kw| called = true; {} }
    OtariClient.stub(:new, client) do
      BookClubDnaJob.new.perform(@club.id)
    end

    refute called
    assert_equal "kept", @club.reload.literature_dna.dig("narrative", "identity")
  end

  private

  def create_past_read!
    book = Book.create!(title: "ኦሮማይ", author: "በዓሉ ግርማ", description: "x", language: "am", country_of_origin: "ET")
    BookRead.new(book: book, book_club: @club, host: users(:one), meetup_time: 20.days.ago, meetup_location: "Cafe").tap { |r| r.save!(validate: false) }
  end
end

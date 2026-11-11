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
    assert_equal 1, @club.literature_dna.dig("dataset", "reads", "past")
    assert_nil @club.literature_dna["narrative"] # narrative is gone; the board is Ruby-derived
  end

  test "meters the run against the triggering owner's monthly budget" do
    create_past_read!
    owner = users(:two) # non-admin

    client = Object.new
    client.define_singleton_method(:chat) do |**_kw|
      {
        "choices" => [ { "message" => { "content" => "" } } ],
        "otari_tool_calls" => [],
        "usage" => { "prompt_tokens" => 1200, "completion_tokens" => 800, "total_tokens" => 2000 }
      }
    end
    OtariClient.stub(:new, client) do
      BookClubDnaJob.new.perform(@club.id, owner.id)
    end

    usage = OtariUsage.find_by(user: owner, feature: "dna_generation", book_club: @club)
    assert_not_nil usage
    assert_equal 1, usage.cost
    assert_equal 1200, usage.input_tokens
    assert_equal 2000, usage.total_tokens
  end

  test "aborts without spending when the owner's budget is exhausted" do
    create_past_read!
    owner = users(:two) # non-admin
    5.times { OtariBudget.record!(user: owner, feature: "dna_generation") }

    called = false
    client = Object.new
    client.define_singleton_method(:chat) { |**_kw| called = true }
    OtariClient.stub(:new, client) do
      BookClubDnaJob.new.perform(@club.id, owner.id)
    end

    refute called
    assert_nil @club.reload.dna_generated_at
  end

  test "an early skip (too few past reads) is not metered" do
    owner = users(:two) # non-admin
    client = Object.new
    client.define_singleton_method(:chat) { |**_kw| raise "should not be called" }
    OtariClient.stub(:new, client) do
      BookClubDnaJob.new.perform(@club.id, owner.id)
    end

    assert_nil OtariUsage.find_by(user: owner)
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

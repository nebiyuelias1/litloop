require "test_helper"

class ClubLiteratureDnaTest < ActiveSupport::TestCase
  setup do
    @club = BookClub.create!(name: "Dna AI Club", owner: users(:one))
    create_club_history!
  end

  test "keeps the verified dataset and sandbox chart when the model produces a PNG" do
    client = Object.new
    client.define_singleton_method(:chat) do |**kwargs|
      {
        "choices" => [ { "message" => { "content" => "" } } ],
        "otari_tool_calls" => [ {
          "id" => "otari_ci_chart", "type" => "code_execution",
          "code" => 'import matplotlib.pyplot as plt; ...; savefig("chart.png")',
          "stdout" => "", "exit_code" => 0, "file_ids" => [ "file-chart123" ]
        } ]
      }
    end
    client.define_singleton_method(:download_file) do |file_id|
      raise OtariClient::RequestError, "no file" unless file_id == "file-chart123"

      SAMPLE_PNG
    end
    OtariClient.stub(:new, client) do
      dna = ClubLiteratureDna.new(club: @club).generate!.dna

      chart = dna["charts"]
      assert_not_nil chart
      assert chart["data_uri"].start_with?("data:image/png;base64,")
      assert_equal "file-chart123", chart["file_id"]
      assert_includes chart["code"], "matplotlib"

      # the dataset is the Ruby-verified analysis; the narrative is gone
      assert_equal 2, dna.dig("dataset", "reads", "past")
      assert_nil dna["narrative"]
      assert_equal 1, dna["sandbox_calls"].size
    end
  end

  test "chart failure is non-fatal and still ships the dataset" do
    client = Object.new
    client.define_singleton_method(:chat) { |**_kw| raise OtariClient::RequestError, "sandbox down" }
    OtariClient.stub(:new, client) do
      dna = ClubLiteratureDna.new(club: @club).generate!.dna

      assert_nil dna["charts"]
      assert_equal 2, dna.dig("dataset", "reads", "past")
      assert_empty dna["sandbox_calls"]
    end
  end

  test "skips clubs with no past reads without any Otari traffic" do
    empty_club = BookClub.create!(name: "Empty Club", owner: users(:one))
    client = Object.new
    client.define_singleton_method(:chat) { |**_kw| raise "gateway must not be called for 0 past reads" }
    OtariClient.stub(:new, client) do
      result = ClubLiteratureDna.new(club: empty_club).generate!

      assert_nil result.dna
    end
  end

  private

  SAMPLE_PNG = "\x89PNG\r\n\x1a\n" + ("A" * 2048) + "\x00\x00"

  def create_club_history!
    et = Book.create!(title: "ኦሮማይ", author: "በዓሉ ግርማ", description: "Amharic novel", language: "am", country_of_origin: "ET", page_count: 200)
    ng = Book.create!(title: "Things Fall Apart", author: "Chinua Achebe", description: "Nigerian classic", language: "en", country_of_origin: "NG", page_count: 209)
    fiction = Tag.create!(name: "fiction")
    BookTag.create!(book: et, tag: fiction)
    BookTag.create!(book: ng, tag: fiction)

    BookRead.new(book: et, book_club: @club, host: users(:one), meetup_time: 20.days.ago, meetup_location: "Cafe 1").tap do |read|
      read.meetup_time = 20.days.ago
      read.save!(validate: false)
    end
    second = BookRead.new(book: ng, book_club: @club, host: users(:one), meetup_time: 5.days.ago, meetup_location: "Cafe 2")
    second.save!(validate: false)
    BookReadRsvp.create!(book_read: second, user: users(:two), status: :going)
    Rating.create!(book: ng, user: users(:two), score: 4)
    Rating.create!(book: ng, user: users(:one), score: 5)
  end
end

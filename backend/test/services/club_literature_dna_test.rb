require "test_helper"

class ClubLiteratureDnaTest < ActiveSupport::TestCase
  setup do
    @club = BookClub.create!(name: "Dna AI Club", owner: users(:one))
    create_club_history!
    @golden_narrative = [
      "{",
      '  "identity": "A small club leaning Afro-diasporic literary fiction.",',
      '  "signatures": [{"title": "African realist bent", "note": "both reads from Africa"}],',
      '  "highlights": [',
      '    {"dataset_path": "reads.past", "value": 2, "comment": "read history"},',
      '    {"dataset_path": "regions.Africa", "value": 2, "comment": "regional focus"},',
      '    {"dataset_path": "reads.total", "value": 9, "comment": "fabricated stat"},',
      '    {"dataset_path": "no.such.path", "value": 3, "comment": "unresolvable"},',
      '    {"dataset_path": "countries.ET.count", "value": 1, "comment": "per-country"}',
      "  ],",
      '  "gaps": ["fiction is covered — try East Asia", "something nobody mentioned"],',
      '  "recommendation": "Try East Asian modernism next."',
      "}"
    ].join("\n")
  end

  test "keeps only path-cited, verified stats and authentic gap names" do
    stub_otari(content: @golden_narrative, sandbox_calls: 1) do
      dna = ClubLiteratureDna.new(club: @club).generate!.dna

      paths = dna.dig("narrative", "highlights").map { |h| h["dataset_path"] }
      assert_includes paths, "reads.past"
      assert_includes paths, "regions.Africa"
      assert_includes paths, "countries.ET.count"
      refute_includes paths, "no.such.path"
      refute_includes paths, "reads.total" # value 9 == mismatch -> dropped

      assert_equal [ "fiction is covered — try East Asia" ], dna.dig("narrative", "gaps")
      assert_equal "openai/gpt-oss-120b", dna["model"]
      assert_equal 1, dna["sandbox_calls"].size
      assert_includes dna["sandbox_calls"].first["stdout"], "2"
      assert_not_nil dna["generated_at"]
      assert_equal 2, dna.dig("dataset", "reads", "past")
    end
  end

  test "escalates once to the fallback model when the first attempt is unparseable" do
    attempts = []
    stub_otari(content: "", sandbox_calls: 0, attempts: attempts, fallback_content: @golden_narrative) do
      dna = ClubLiteratureDna.new(club: @club).generate!.dna

      assert_equal [ ClubLiteratureDna::DEFAULT_MODEL, ClubLiteratureDna::FALLBACK_MODEL ], attempts
      assert_equal ClubLiteratureDna::FALLBACK_MODEL, dna["model"]
    end
  end

  test "raises when neither model yields a verifiable narrative" do
    stub_otari(content: nil, sandbox_calls: 0) do
      assert_raises(OtariClient::RequestError) do
        ClubLiteratureDna.new(club: @club).generate!
      end
    end
  end

  test "skips clubs with no past reads without any Otari traffic" do
    empty_club = BookClub.create!(name: "Empty Club", owner: users(:one))
    stub_otari(content: @golden_narrative, sandbox_calls: 0) do
      result = ClubLiteratureDna.new(club: empty_club).generate!

      assert_nil result.dna
      assert_equal [], @attempts
    end
  end

  private

  def create_club_history!
    et = Book.create!(title: "ኦሮማይ", author: "በዓሉ ግርማ", description: "Amharic novel", language: "am", country_of_origin: "ET")
    ng = Book.create!(title: "Things Fall Apart", author: "Chinua Achebe", description: "Nigerian classic", language: "en", country_of_origin: "NG")
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
  end

  # Strings an OtariClient whose chat() counts attempts and returns canned
  # payloads (empty content triggers the escalation path).
  def stub_otari(content:, sandbox_calls:, attempts: [], fallback_content: nil)
    @attempts = attempts
    sandbox_payload = {
      "type" => "otari_code_execution",
      "code" => 'print(len(data["reads"]))',
      "stdout" => "2",
      "exit_code" => 0
    }
    client = Object.new
    client.define_singleton_method(:chat) do |**kwargs|
      attempts << kwargs[:model]
      answered = content
      if kwargs[:model] == ClubLiteratureDna::FALLBACK_MODEL && fallback_content
        answered = fallback_content
      end
      {
        "choices" => [ { "message" => { "content" => answered } } ],
        "otari_tool_calls" => Array.new(sandbox_calls) { sandbox_payload }
      }
    end
    OtariClient.stub(:new, client) { yield }
  end
end

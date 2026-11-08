require "test_helper"

class BookMetadataEnricherTest < ActiveSupport::TestCase
  def payload(description:, tags: [], country: "", evidence: "", confidence: "high")
    {
      "description" => description,
      "tags" => tags,
      "country_of_origin" => country,
      "country_evidence" => evidence,
      "confidence" => confidence
    }
  end

  def enrich_book(book, model_payload)
    enricher = BookMetadataEnricher.new(book: book)
    enricher.stub(:generate_payload, model_payload) do
      enricher.enrich!
    end
  end

  test "applies description, normalized tags and validated country" do
    book = Book.create!(
      title: "Things Fall Apart",
      author: "Chinua Achebe",
      description: "Old marketing blurb with celebrity endorsements.",
      language: "am"
    )

    result = enrich_book(book, payload(
      description: "Okonkwo, a wealthy and fearless Igbo warrior of Umuofia in the late 1800s, resists the loss of his traditions as British colonial forces arrive. This landmark novel captures both pre-colonial village life and its destruction.",
      tags: [ "Fiction", "  Colonialism ", "coming of age" ],
      country: "Nigeria",
      evidence: "The blurb repeatedly cites an Igbo warrior of Umuofia facing British colonial forces."
    ))

    assert result.description_changed
    assert_match(/Okonkwo/, book.reload.description)
    assert_equal "NG", book.country_of_origin
    assert_equal [ "colonialism", "coming of age", "fiction" ], book.tags.order(:name).pluck(:name)
    assert_not_nil book.enriched_at
    assert_equal "high", result.confidence
    assert_equal [ "fiction", "colonialism", "coming of age" ], result.tags_added
  end

  test "reuses existing tag records instead of duplicating" do
    Tag.create!(name: "fiction")
    book = Book.create!(title: "Test Book", author: "Test Author")

    enrich_book(book, payload(
      description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate we enforce.",
      tags: [ "fiction" ]
    ))

    assert_equal 1, Tag.where(name: "fiction").count
    assert_equal [ "fiction" ], book.reload.tags.pluck(:name)
  end

  test "rejects country without evidence" do
    book = Book.create!(title: "Mystery Book", author: "Unknown Author")
    enrich_book(book, payload(
      description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate we enforce.",
      country: "Nigeria",
      evidence: "",
      confidence: "high"
    ).merge("confidence" => "high"))

    assert_nil book.reload.country_of_origin
  end

  test "rejects country not in the whitelist and low confidence" do
    book = Book.create!(title: "Test Book", author: "Test Author")
    enrich_book(book, payload(
      description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.",
      country: "Atlantis",
      evidence: "claim",
      confidence: "high"
    ))
    assert_nil book.reload.country_of_origin

    enrich_book(book, payload(
      description: "Another richly detailed rebuilt description that easily passes the length gate again.",
      country: "Nigeria",
      evidence: "claim",
      confidence: "low"
    ))
    assert_nil book.reload.country_of_origin
  end

  test "rejects bogus description (too short)" do
    book = Book.create!(title: "Test Book", author: "Test Author", description: "Original good description.")
    enrich_book(book, payload(description: "Too short."))

    assert_equal "Original good description.", book.reload.description
  end

  test "stores audit trail with originals for reversibility" do
    book = Book.create!(title: "Things Fall Apart", author: "Chinua Achebe", description: "Original blurb.")
    Tag.create!(name: "classic")
    book.tags << Tag.find_by!(name: "classic")

    enrich_book(book, payload(
      description: "A rebuilt description written by the model that is comfortably longer than the gate.",
      tags: [ "fiction" ],
      country: "Nigeria",
      evidence: "evidence text",
      confidence: "high"
    ))

    audit = book.reload.enrichment
    assert_equal "Original blurb.", audit["original_description"]
    assert_equal [ "classic" ], audit["original_tags"]
    assert_equal "NG", audit["applied_country_of_origin"]
    assert_equal "evidence text", audit["country_evidence"]
    assert_equal "high", audit["confidence"]
    assert audit["enriched_at"].present?
  end

  test "tags_added result reflects normalized tag names" do
    book = Book.create!(title: "Test Book", author: "Test Author")

    result = enrich_book(book, payload(
      description: "A richly detailed rebuilt description that is comfortably longer than the gate.",
      tags: [ "Fiction", "non fiction" ]
    ))

    assert_equal [ "fiction", "non fiction" ], result.tags_added
  end
end

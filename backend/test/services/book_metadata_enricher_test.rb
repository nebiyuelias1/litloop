require "test_helper"

class BookMetadataEnricherTest < ActiveSupport::TestCase
  def payload(description:, tags: [], country: "", evidence: "", country_confidence: "high", page_count: 0, page_count_confidence: "high")
    {
      "description" => description,
      "tags" => tags,
      "country_of_origin" => country,
      "country_evidence" => evidence,
      "country_confidence" => country_confidence,
      "page_count" => page_count,
      "page_count_confidence" => page_count_confidence
    }
  end

  def enrich_book(book, model_payload)
    enricher = BookMetadataEnricher.new(book: book)
    enricher.stub(:propose, model_payload) do
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
    assert_equal "high", result.country_confidence
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
      country_confidence: "high"))

    assert_nil book.reload.country_of_origin
  end

  test "rejects country not in the whitelist and low confidence" do
    book = Book.create!(title: "Test Book", author: "Test Author")
    enrich_book(book, payload(
      description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.",
      country: "Atlantis",
      evidence: "claim",
      country_confidence: "high"
    ))
    assert_nil book.reload.country_of_origin

    enrich_book(book, payload(
      description: "Another richly detailed rebuilt description that easily passes the length gate again.",
      country: "Nigeria",
      evidence: "claim",
      country_confidence: "low",
      page_count_confidence: "high"
    ))
    assert_nil book.reload.country_of_origin
  end

  test "fills page_count from the model when confident and lookup absent" do
    book = Book.create!(title: "Test Book", author: "Test Author")

    result = enrich_book(book, payload(description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.", page_count: 226))

    assert_equal 226, book.reload.page_count
    assert result.page_count_changed
    audit = book.enrichment
    assert_equal "model", audit["page_count_source"]
  end

  test "page_count prefers the deterministic catalog lookup over the model" do
    book = Book.create!(title: "Test Book", author: "Test Author")
    lookup = [ { "source" => "google_books", "page_count" => 412 } ]

    enricher = BookMetadataEnricher.new(book: book)
    enricher.stub(:propose, payload(description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.", country_confidence: "medium", page_count: 99)) do
      enricher.enrich!(fresh_lookup: lookup)
    end

    assert_equal 412, book.reload.page_count
    assert_equal "catalog_lookup", book.enrichment["page_count_source"]
  end

  test "page_count requires high confidence from the model alone" do
    book = Book.create!(title: "Test Book", author: "Test Author")

    enrich_book(book, payload(description: "A richly detailed rebuilt description that is comfortably longer than the gate.", page_count: 226, page_count_confidence: "medium"))
    assert_nil book.reload.page_count
  end

  test "page_count sanity range" do
    book = Book.create!(title: "Test Book", author: "Test Author")

    enrich_book(book, payload(description: "A richly detailed rebuilt description that is comfortably longer than the gate.", page_count: 99_999))
    assert_nil book.reload.page_count
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
      country_confidence: "high"
    ))

    audit = book.reload.enrichment
    assert_equal "Original blurb.", audit["original_description"]
    assert_equal [ "classic" ], audit["original_tags"]
    assert_equal "NG", audit["applied_country_of_origin"]
    assert_equal "evidence text", audit["country_evidence"]
    assert_equal "high", audit["country_confidence"]
    assert audit["enriched_at"].present?
  end

  test "escalates declined fields to the fallback model" do
    book = Book.create!(title: "Dune", author: "Frank Herbert")

    declined = payload(description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.", country: "", evidence: "", country_confidence: "low", page_count: 0, page_count_confidence: "low")
    strong = payload(description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.", country: "United States", evidence: "Author Frank Herbert is American; published by Chilton Books, a US publisher", page_count: 412)

    enricher = BookMetadataEnricher.new(book: book)
    result = nil
    enricher.stub(:propose, lambda do |model, _lookup|
      model == BookMetadataEnricher::DEFAULT_MODEL ? declined : strong
    end) do
      result = enricher.enrich!(fresh_lookup: [])
    end

    assert_equal "US", book.reload.country_of_origin
    assert_equal 412, book.page_count
    assert_equal "mistral/mistral-large-latest", book.enrichment["escalated_with"]
    assert_equal "US", result.country_of_origin
  end

  test "no escalation when the primary model answers everything" do
    book = Book.create!(title: "Test Book", author: "Test Author")

    result = enrich_book(book, payload(
      description: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.",
      country: "US",
      evidence: "claim",
      page_count: 300
    ))

    assert_nil book.enrichment["escalated_with"]
    assert_equal "US", book.reload.country_of_origin
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

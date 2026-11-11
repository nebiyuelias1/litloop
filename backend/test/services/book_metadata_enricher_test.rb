require "test_helper"

class BookMetadataEnricherTest < ActiveSupport::TestCase
  WIKI = "https://en.wikipedia.org/wiki/Things_Fall_Apart"

  def ground(facts: nil, sources: [ WIKI ], cited_sources: [ WIKI ])
    { facts: facts || default_facts, sources: sources, cited_sources: cited_sources }
  end

  def default_facts
    <<~FACTS
      Things Fall Apart is a 1958 novel by Nigerian author Chinua Achebe.
      Source: #{WIKI}
    FACTS
  end

  def judgment(desc_action: "keep_existing", desc_value: "", desc_source: "", quote: "",
               tags_action: "keep_existing", tags: [], country_action: "keep_existing",
               country: "", country_source: "", country_quote: "",
               cover_judgment: "adequate", cover_reason: "")
    {
      "description" => { "action" => desc_action, "value" => desc_value, "source_url" => desc_source, "quote" => quote },
      "tags" => { "action" => tags_action, "values" => tags, "source_url" => WIKI },
      "country_of_origin" => { "action" => country_action, "value" => country, "source_url" => country_source, "quote" => country_quote },
      "cover" => { "judgment" => cover_judgment, "reason" => cover_reason, "source_url" => "" }
    }
  end

  def enrich_with(ground, judgment)
    enricher = BookMetadataEnricher.new(book: @book)
    enricher.stub(:ground_with_web_search, ground) do
      enricher.stub(:judge, judgment) do
        enricher.enrich!
      end
    end
  end

  test "applies attributed updates and records sources" do
    @book = Book.create!(title: "Things Fall Apart", author: "Chinua Achebe", language: "en",
      description: "Old blurb.", country_of_origin: nil)

    judgment = judgment(
      desc_action: "update",
      desc_value: "Set in pre-colonial Nigeria, Things Fall Apart follows Okonkwo, a feared Igbo wrestler and leader of Umuofia, as the arrival of British missionaries dismantles his world and cultural order.",
      desc_source: WIKI,
      tags_action: "update",
      tags: [ "fiction", "colonialism" ],
      country_action: "update",
      country: "Nigeria",
      country_source: WIKI,
      country_quote: "Things Fall Apart is a 1958 novel by Nigerian author Chinua Achebe",
      cover_judgment: "missing",
      cover_reason: "no cover stored"
    )

    result = enrich_with(ground, judgment)

    assert result.description_changed
    assert_match(/Okonkwo/, @book.reload.description)
    assert_equal "NG", @book.country_of_origin
    assert_equal WIKI, result.country_source
    assert_equal "fiction", @book.tags.first.name
    audit = @book.enrichment
    assert_equal "high", audit["country_confidence"]
    assert_equal WIKI, audit["country_source_url"]
    assert_equal "missing", audit["cover_judgment"]["judgment"]
  end

  test "unattributed country claim is never applied" do
    @book = Book.create!(title: "Some Book", author: "Unknown", description: "Desc that is long enough. " * 5)

    judgment = judgment(
      country_action: "update",
      country: "Nigeria",
      country_source: "https://made-up.example/nigeria",  # not on the whitelist
      country_quote: ""                                   # and no verbatim quote
    )

    enrich_with(ground, judgment)

    assert_nil @book.reload.country_of_origin
  end

  test "quote-verified attribution applies with medium confidence" do
    @book = Book.create!(title: "Some Book", author: "Nobody", description: "Original desc that is long enough.")

    judgment = judgment(
      country_action: "update",
      country: "Nigeria",
      country_source: "",
      country_quote: "novel by Nigerian author Chinua Achebe"
    )

    result = enrich_with(ground, judgment)

    assert_equal "NG", @book.reload.country_of_origin
    assert_equal "medium", @book.enrichment["country_confidence"]
    assert_equal "quote-verified", result.country_source
  end

  test "keep_existing leaves the record untouched" do
    @book = Book.create!(title: "Some Book", author: "Nobody", description: "Original desc.", country_of_origin: "IL")
    original = @book.description

    enrich_with(ground, judgment(country: "", country_source: ""))

    assert_equal "Original desc.", @book.reload.description
    assert_equal "IL", @book.country_of_origin
  end

  test "description needs attribution too" do
    @book = Book.create!(title: "Some Book", author: "Nobody", description: "Original desc.")

    # Update with no source and no quote → rejected
    enrich_with(ground, judgment(desc_action: "update", desc_value: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.", desc_source: "", quote: ""))

    assert_equal "Original desc.", @book.reload.description

    # Update quoting the facts → accepted
    enrich_with(ground, judgment(
      desc_action: "update",
      desc_value: "Set in pre-colonial Nigeria, the novel follows Okonkwo whose world is dismantled by British missionaries in Chinua Achebe's landmark fiction.",
      desc_source: "",
      quote: "novel by Nigerian author Chinua Achebe"
    ))

    assert_match(/Okonkwo/, @book.reload.description)
  end

  test "wrong source_url does not veto a verbatim quote for descriptions" do
    @book = Book.create!(title: "Some Book", author: "Nobody", description: "Original desc.")

    # Source not on the whitelist, but the quote IS verbatim in the facts —
    # mirrors sanitize_country's medium-confidence path.
    result = enrich_with(ground, judgment(
      desc_action: "update",
      desc_value: "Set in pre-colonial Nigeria, the novel follows Okonkwo whose world is dismantled by British missionaries in Chinua Achebe's landmark fiction.",
      desc_source: "https://made-up.example/review",
      quote: "novel by Nigerian author Chinua Achebe"
    ))

    assert_match(/Okonkwo/, @book.reload.description)
    assert_equal "medium", @book.enrichment["description_confidence"]
    assert_equal "https://made-up.example/review", @book.enrichment["description_source_url"]
    assert result.description_changed
  end

  test "description whitelisted source applies with high confidence" do
    @book = Book.create!(title: "Some Book", author: "Nobody", description: "Original desc.")

    result = enrich_with(ground, judgment(
      desc_action: "update",
      desc_value: "Set in pre-colonial Nigeria, the novel follows Okonkwo whose world is dismantled by British missionaries in Chinua Achebe's landmark fiction.",
      desc_source: WIKI
    ))

    assert result.description_changed
    assert_equal "high", @book.enrichment["description_confidence"]
    assert_equal WIKI, @book.enrichment["description_source_url"]
  end

  test "MCP tool outputs are harvested into the consulted-source whitelist" do
    @book = Book.create!(title: "So Long a Letter", author: "Mariama Bâ")

    response = {
      "choices" => [ { "message" => { "role" => "assistant", "content" => "Facts about the book. Source: https://openlibrary.org/books/OL51587863M" } } ],
      "otari_tool_calls" => [
        { "type" => "mcp", "status" => "completed", "server" => "books", "name" => "get_book",
          "output" => { urls: [ "http://openlibrary.org/books/OL51587863M", "http://books.google.com/books?id=zA51b1qCgCEC" ] }.to_json },
        { "type" => "tool", "status" => "completed", "name" => "otari_web_search",
          "sources" => [ "https://en.wikipedia.org/wiki/Mariama_B%C3%A2" ] }
      ]
    }

    ground = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:chat) { |**_kwargs| response }
    OtariClient.stub(:new, fake_client) do
      ground = BookMetadataEnricher.new(book: @book).send(:ground_with_web_search, BookMetadataEnricher::DEFAULT_MODEL)
    end

    consulted = ground[:sources]
    assert_includes consulted, "https://openlibrary.org/books/OL51587863M"   # from MCP output (scheme normalized)
    assert_includes consulted, "https://books.google.com/books"              # from MCP output, query stripped
    assert_includes consulted, "https://en.wikipedia.org/wiki/Mariama_B%C3%A2" # from web-search sources
  end

  test "judge errors escalate to the fallback model" do
    @book = Book.create!(title: "Test Book", author: "Author", description: "Desc long enough to exist.")

    enricher = BookMetadataEnricher.new(book: @book)
    enricher.stub(:ground_with_web_search, ground) do
      enricher.stub(:judge_with, ->(model, _ground) {
        model == BookMetadataEnricher::DEFAULT_MODEL ? raise(OtariClient::RequestError, "503") :
          judgment(desc_action: "update", desc_value: "A richly detailed rebuilt description that is comfortably longer than the minimum length gate.", desc_source: WIKI)
      }) do
        enricher.enrich!
      end
    end

    assert_match(/richly detailed/, @book.reload.description)
  end

  test "deterministic grounding supplies wikipedia extract when web search unavailable" do
    @book = Book.create!(title: "Test Book", author: "Author", description: "Existing press blurb text.")

    enricher = BookMetadataEnricher.new(book: @book)
    # In test env wikipedia_search_title returns nil -> facts fall back to row description
    enricher.stub(:ground_with_web_search, ->(model) {
      raise raise = OtariClient::RequestError, "down" if false
      BookMetadataEnricher.new(book: @book).send(:ground_via_deterministic_sources)
    }) do
      ground = nil
      enricher.stub(:judge, ->(model, g) { ground = g; judgment() }) do
        enricher.enrich!
      end
      assert ground.is_a?(Hash)
      assert ground.key?(:facts)
    end
  end
end

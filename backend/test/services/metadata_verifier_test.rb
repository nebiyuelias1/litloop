require "test_helper"

class MetadataVerifierTest < ActiveSupport::TestCase
  def verifier
    @verifier ||= MetadataVerifier.new(book: books(:one))
  end

  # Wikidata API fixture shapes
  def pageprops_ok
    { "query" => { "pages" => { "123" => { "pageprops" => { "wikibase_item" => "Q27561" } } } } }
  end

  def claims_p495(qid)
    { "entities" => { qid => { "claims" => { "P495" => [ { "mainsnak" => { "datavalue" => { "value" => { "id" => "Q1033" } } } } ] } } } }
  end

  def labels(qid, name)
    { "entities" => { qid => { "labels" => { "en" => { "value" => name } } } } }
  end

  test "confirms when wikidata p495 agrees with the proposal" do
    # Things Fall Apart -> Q27561 -> P495 = Q1033 (Nigeria)
    verifier.stub(:http_get_json, lambda { |uri, **|
      params = Rack::Utils.parse_nested_query(URI.parse(uri).query)
      case params["action"]
      when "query" then pageprops_ok
      when "wbgetentities" then params.dig("props") == "claims" ? claims_p495("Q27561") : labels("Q1033", "Nigeria")
      end
    }) do
      result = verifier.verify_country(model_country_code: "NG", wikipedia_page: "https://en.wikipedia.org/wiki/Things_Fall_Apart")

      assert_equal "confirmed", result.verdict
      assert_equal "NG", result.country_code
      assert_equal "Q1033", result.source_country_qid
    end
  end

  test "rejects when wikidata disagrees" do
    verifier.stub(:http_get_json, lambda { |uri, **|
      params = Rack::Utils.parse_nested_query(URI.parse(uri).query)
      case params["action"]
      when "query" then pageprops_ok
      when "wbgetentities" then params.dig("props") == "claims" ? claims_p495("Q27561") : labels("Q1033", "Nigeria")
      end
    }) do
      result = verifier.verify_country(model_country_code: "ET", wikipedia_page: "https://en.wikipedia.org/wiki/Things_Fall_Apart")

      assert_equal "disagreement", result.verdict
      assert_equal "NG", result.country_code, "source answer surfaces for the audit"
    end
  end

  test "no_source when article has no wikidata item or p495" do
    verifier.stub(:http_get_json, ->(_uri, **) { { "query" => { "pages" => { "1" => { "title" => "X" } } } } }) do
      result = verifier.verify_country(model_country_code: "NG", wikipedia_page: "https://en.wikipedia.org/wiki/Obscure_Book")
      assert_equal "no_source", result.verdict
    end

    result = verifier.verify_country(model_country_code: "NG", wikipedia_page: nil)
    assert_equal "no_source", result.verdict
  end

  test "no_source when country claim cannot be mapped to an ISO code" do
    verifier.stub(:http_get_json, lambda { |uri, **|
      params = Rack::Utils.parse_nested_query(URI.parse(uri).query)
      case params["action"]
      when "query" then pageprops_ok
      when "wbgetentities" then params.dig("props") == "claims" ? claims_p495("Q27561") : labels("Q1033", "Atlantis")
      end
    }) do
      assert_equal "no_source", verifier.verify_country(model_country_code: "NG", wikipedia_page: "https://en.wikipedia.org/wiki/Things_Fall_Apart").verdict
    end
  end
end

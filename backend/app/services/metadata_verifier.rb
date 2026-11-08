# frozen_string_literal: true

require "uri"
require "json"

# Verifies AI-proposed metadata against independent, human-curated sources
# before it is persisted. Deliberately LLM-free: grounding, not vibes.
#
# Country verification:
#   1. The proposed Wikipedia article is resolved to its Wikidata entity (QID)
#      via the article's pageprops.
#   2. The entity's P495 ("country of origin") claim is read; the claim's
#      country entity label is converted to an ISO 3166-1 alpha-2 code.
#   3. Verdicts:
#        - "confirmed"     : Wikidata agrees with the model's proposal
#        - "disagreement"  : Wikidata has a different answer -> do not apply
#        - "no_source"     : book has no Wikidata/P495 data -> fall back to the
#                            proposal's own evidence + confidence gates
class MetadataVerifier
  VERDICTS = %w[confirmed disagreement no_source].freeze
  Result = Struct.new(:verdict, :country_code, :source_country_qid, :model_country_code, :detail, keyword_init: true)

  WIKIDATA_API = "https://www.wikidata.org/w/api.php"
  WIKIDATA_USER_AGENT = "Litloop/1.0 (AI metadata verification; https://github.com/nebiyuelias1/litloop)".freeze
  PROPERTY_COUNTRY_OF_ORIGIN = "P495"

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  def initialize(book:)
    @book = book
  end

  # Verifies a proposed country (ISO alpha-2 code) against Wikidata via the
  # book's Wikipedia article. Returns a Result.
  def verify_country(model_country_code:, wikipedia_page: nil)
    country = wikidata_country(wikipedia_page)
    return no_source("no Wikidata data (no article/item or P495 claim)") if country.nil?
    return confirmed(country, model_country_code) if country[:code] == model_country_code

    Result.new(
      verdict: "disagreement", country_code: country[:code], source_country_qid: country[:qid],
      model_country_code: model_country_code,
      detail: "Wikidata country (#{country[:code]}) disagrees with the proposal (#{model_country_code})"
    )
  end

  def confirmed(country, model_country_code)
    Result.new(
      verdict: "confirmed", country_code: country[:code], source_country_qid: country[:qid],
      model_country_code: model_country_code, detail: "Wikidata P495 agrees with the proposal"
    )
  end

  def no_source(detail)
    Result.new(verdict: "no_source", country_code: nil, source_country_qid: nil,
      model_country_code: nil, detail: detail)
  end

  private

  # {qid: "Q1033", code: "NG"} or nil
  def wikidata_country(wikipedia_page)
    qid = wikidata_qid_for_article(wikipedia_page)
    return nil if qid.blank?

    country_qid = claim_country_qid(qid)
    return nil if country_qid.blank?

    label = entity_label(country_qid)
    return nil if label.blank?

    code = CountryCodes.code_for(label)
    return nil if code.nil?

    { qid: country_qid, code: code }
  end

  # pageprops on the article -> wikibase_item
  def wikidata_qid_for_article(wikipedia_page)
    return nil if wikipedia_page.blank? || !wikipedia_page.include?("wikipedia.org/wiki/")

    title = URI(wikipedia_page).path.split("/").last
    return nil if title.blank?

    uri = URI("https://#{URI(wikipedia_page).host}/w/api.php")
    uri.query = URI.encode_www_form(
      action: "query", prop: "pageprops", titles: title.tr("_", " "),
      ppprop: "wikibase_item", format: "json", redirects: 1
    )
    data = http_get_json(uri)
    page = data&.dig("query", "pages")&.values&.first
    page&.dig("pageprops", "wikibase_item")
  end

  # The P495 claim's value entity id, or nil
  def claim_country_qid(qid)
    data = http_get_json(wikidata_api_uri(action: "wbgetentities", ids: qid, props: "claims"))
    claims = data&.dig("entities", qid, "claims", PROPERTY_COUNTRY_OF_ORIGIN)
    return nil if claims.blank?

    claims.first.dig("mainsnak", "datavalue", "value", "id")
  end

  def entity_label(qid)
    data = http_get_json(wikidata_api_uri(action: "wbgetentities", ids: qid, props: "labels"))
    data&.dig("entities", qid, "labels", "en", "value")
  end

  def wikidata_api_uri(**params)
    uri = URI(WIKIDATA_API)
    uri.query = URI.encode_www_form(**params, format: "json")
    uri
  end

  def http_get_json(uri, retries: 1)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = WIKIDATA_USER_AGENT
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end

    if response.code.to_i == 429 && retries.positive?
      sleep(2)
      return http_get_json(uri, retries: retries - 1)
    end

    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue => e
    Rails.logger.warn("MetadataVerifier lookup failed for #{uri}: #{e.message}")
    nil
  end
end

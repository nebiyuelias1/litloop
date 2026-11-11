# frozen_string_literal: true

require "uri"
require "net/http"
require "json"

# Enriches a Book's metadata by GROUNDING in web sources and JUDGING against
# the stored record, per the owner's design:
#
#   1. GROUND  — one Otari tool-loop call (otari_web_search) collects facts
#                about the book from the internet, WITH source URLs. The
#                gateway's tool calls are harvested as a source whitelist.
#                Fallback grounding: Wikipedia search + REST extract.
#   2. JUDGE   — a structured (strict-schema) call compares the book's CURRENT
#                metadata against the grounded facts and decides per field:
#                keep_existing | update(value, source_url, quote). For the
#                cover it receives quality facts about the current image and
#                decides whether it is missing / low quality / fine.
#   3. APPLY   — only updates pass gates:
#                * "update" requires a source_url that is on the harvested
#                  whitelist (confidence high) or at least a verbatim quote
#                  from the grounded facts (confidence medium).
#                * unattributed claims are never applied.
#   * Every applied value's original is stored in book.enrichment for audit
#     and revert; the source URL is recorded alongside it.
class BookMetadataEnricher
  Result = Struct.new(
    :description_changed, :tags_added, :country_of_origin, :country_source,
    :cover_judgment, :cover_source_url, keyword_init: true
  )

  LANGUAGE_NAMES = {
    "am" => "Amharic", "en" => "English", "or" => "Oromo", "ar" => "Arabic",
    "fr" => "French", "sw" => "Swahili", "ti" => "Tigrinya", "es" => "Spanish",
    "de" => "German", "it" => "Italian", "pt" => "Portuguese"
  }.freeze

  # Verified working on the hosted gateway:
  # https://api.otari.ai/api/v1/models
  DEFAULT_MODEL = "openai/gpt-oss-120b"
  FALLBACK_MODEL = "mistral/mistral-large-latest"
  MAX_TAGS = 6
  MAX_TAG_LENGTH = 40
  MIN_DESCRIPTION_LENGTH = 30
  MAX_DESCRIPTION_LENGTH = 4_000

  JUDGE_SCHEMA = {
    type: "object",
    properties: {
      description: {
        type: "object",
        properties: {
          action: { type: "string", enum: %w[keep_existing update] },
          value: { type: "string", description: "new description in the book's language; empty when keeping" },
          source_url: { type: "string", description: "URL among the harvested sources backing this update; empty if none" },
          quote: { type: "string", description: "short verbatim quote from the grounded facts it is based on" }
        },
        required: %w[action value source_url quote],
        additionalProperties: false
      },
      tags: {
        type: "object",
        properties: {
          action: { type: "string", enum: %w[keep_existing update] },
          values: { type: "array", maxItems: MAX_TAGS, items: { type: "string" } },
          source_url: { type: "string" }
        },
        required: %w[action values source_url],
        additionalProperties: false
      },
      country_of_origin: {
        type: "object",
        properties: {
          action: { type: "string", enum: %w[keep_existing update] },
          value: { type: "string", description: "official English country name; empty when keeping/unknown" },
          source_url: { type: "string" },
          quote: { type: "string", description: "verbatim quote from the grounded facts establishing the country" }
        },
        required: %w[action value source_url quote],
        additionalProperties: false
      },
      cover: {
        type: "object",
        properties: {
          judgment: { type: "string", enum: %w[missing low_quality adequate cannot_assess] },
          reason: { type: "string" },
          source_url: { type: "string", description: "URL that shows what the real cover is, when suggesting a replace" }
        },
        required: %w[judgment reason source_url],
        additionalProperties: false
      }
    },
    required: %w[description tags country_of_origin cover],
    additionalProperties: false
  }.freeze

  def initialize(book:)
    @book = book
  end

  def enrich!(model: nil)
    model ||= DEFAULT_MODEL
    enrich_log("enrichment start (model=#{model})")
    ground = ground_with_web_search(model)
    enrich_log("grounded: sources=#{ground[:sources].size} facts_bytes=#{ground[:facts].bytesize}")
    judgment = judge(model, ground)

    commit(judgment, ground, model).tap do |result|
      enrich_log("done: desc=#{result.description_changed} country=#{result.country_of_origin.inspect} " \
        "source=#{result.country_source.inspect} cover=#{result.cover_judgment.inspect}")
    end
  end

  def enrich_log(message)
    Rails.logger.tagged("[enrich ##{@book.id}]") { |l| l.info(message) }
  end

  def logger_for(_name)
    Rails.logger.tagged("[enrich ##{@book.id}]") { |l| l }
  end

  private

  # ---- Phase 1: GROUND ------------------------------------------------------

  # Returns { facts:, sources: } where facts is text about the book and
  # sources is the whitelist of URLs the gateway actually searched.
  def ground_with_web_search(model)
    ground = try_grounding(model)
    return ground if ground && ground[:facts].to_s.strip.present?

    # The open-weight model sometimes searches nothing useful (especially for
    # non-Latin titles) or the gateway times out; the frontier model's broader
    # knowledge fills in.
    if model != FALLBACK_MODEL
      enrich_log("grounding empty on #{model}; escalating grounding to #{FALLBACK_MODEL}")
      ground = try_grounding(FALLBACK_MODEL)
      return ground if ground && ground[:facts].to_s.strip.present?
    end

    ground_via_deterministic_sources
  end

  def try_grounding(model)
    ground_via_web_search(model)
  rescue OtariClient::Error => e
    enrich_log("web grounding failed on #{model} (#{e.class} #{e.message})")
    nil
  end

  # Grounding prompt. When a books MCP server is configured in the Otari
  # workspace (OTARI_MCP_BOOK_SERVER_ID), the model is told to prefer its
  # structured lookups (search_books / get_book) over web search — exact
  # metadata by ISBN/title/author, no hallucinated titles, and each record
  # already carries source URLs (openlibrary.org, books.google.com).
  def grounding_prompt(mcp_ids)
    mcp_note = mcp_ids.present? ? <<~MCP : ""
      You also have book MCP tools available. PREFER them over web search for this book:
      - search_books with q="<title> <author>" to find the book and its identifiers;
      - get_book with isbn=<ISBN> (if you have one) for the richest merged record.
      Treat the returned description, subjects, ratings, publisher, page count and
      release date as facts, and use the record's openlibrary.org / books.google.com
      URLs as the source URLs. Only fall back to web search if the MCP tools
      find no match.
    MCP

    <<~PROMPT
      Research this book and report bullet-point FACTS, each on its own line, each ending with the source URL you used:
      description/plot summary, country of origin of the author/work, and where its real cover image can be found.
      Only state what the searched sources support.
      Non-Latin-script titles: also try searching a transliteration (e.g. Amharic "የተቆለፈበት ቁልፍ" -> "Yeteqolefetebet Kulf")
      and include the URL of any page whose cover photo is the real book cover.
      #{mcp_note}
      Book: "#{@book.title}" by #{@book.author}
      Current metadata: language=#{@book.language}, country=#{@book.country_of_origin || "unknown"}, cover=#{@book.cover_image || "none"}
    PROMPT
  end

  # Otari workspace MCP server ids for structured book lookups, e.g.
  # "OTARI_MCP_BOOK_SERVER_ID=uuid1,uuid2". Empty when not configured, in
  # which case grounding relies on otari_web_search alone.
  def book_mcp_server_ids
    ENV["OTARI_MCP_BOOK_SERVER_ID"].to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def ground_via_web_search(model)
    mcp_ids = book_mcp_server_ids
    response = OtariClient.new.chat(
      model: model,
      tools: [ { type: "otari_web_search", max_uses: 3 } ],
      mcp_server_ids: mcp_ids.presence,
      temperature: 0.0,
      messages: [
        { role: "user", content: grounding_prompt(mcp_ids) }
      ]
    )

    facts = response.dig("choices", 0, "message", "content").to_s
    tool_urls = (response["otari_tool_calls"] || [])
      .flat_map { |call|
        # Web-search calls carry a sources list; MCP tool calls don't — their
        # output (merged book records, search results) is full of source URLs
        # (openlibrary.org, books.google.com) that are the citation whitelist
        # for MCP-grounded facts.
        web = Array(call["sources"]).map { |s| s.is_a?(String) ? s : (s["url"] || s["href"]) }
        mcp = call["type"] == "mcp" ? URI.extract(call["output"].to_s, %w[http https]) : []
        web + mcp
      }
      .compact
      .map { |s| strip_query(s) }

    if facts.strip.blank?
      logger_for(self.class.name).warn("web grounding returned empty facts; falling back to deterministic sources")
      return ground_via_deterministic_sources
    end

    # Not everything the search backend visited is a citation: separate the
    # URLs the model's facts actually reference ("cited") from everything the
    # gateway read along the way ("consulted").
    fact_urls = URI.extract(facts, %w[http https]).map { |u| strip_query(u) }
    cited_sources = (fact_urls & tool_urls).uniq
    cited_sources = fact_urls.uniq if cited_sources.blank?

    logger_for(self.class.name).info(
      "web grounding: #{facts.bytesize}B facts, #{cited_sources.size} cited / #{tool_urls.size} consulted sources, model=#{model}"
    )

    { facts: facts, sources: tool_urls.uniq, cited_sources: cited_sources }
  end

  # No-gateway fallback: Wikipedia REST extract with attribution.
  def ground_via_deterministic_sources
    return { facts: @book.description.to_s, sources: [] } if @book.description.present? && Rails.env.test?

    title = wikipedia_search_title
    if title.present?
      text = wikipedia_extract(title)
      return { facts: "From https://en.wikipedia.org/wiki/#{title.tr(' ', '_')}:\n#{text}", sources: [ "https://en.wikipedia.org/wiki/#{title.tr(' ', '_')}" ] } if text.present?
    end

    { facts: "", sources: [] }
  end

  def wikipedia_search_title
    return nil if Rails.env.test?

    uri = URI("https://en.wikipedia.org/w/api.php")
    uri.query = URI.encode_www_form(action: "query", list: "search", srsearch: "#{@book.title} #{@book.author}".strip, format: "json", srlimit: 1)
    data = http_get_json(uri)
    data&.dig("query", "search", 0, "title")
  end

  def wikipedia_extract(title)
    uri = URI("https://en.wikipedia.org/api/rest_v1/page/summary/#{URI.encode_www_form_component(title)}")
    data = http_get_json(uri)
    data&.dig("extract").to_s
  end

  # ---- Phase 2: JUDGE -------------------------------------------------------

  def judge(model, ground)
    judge_with(model, ground)
  rescue OtariClient::Error => e
    Rails.logger.tagged("[enrich ##{@book.id}]") { |l| l.warn("judge failed on #{model} (#{e.message}); escalating to #{FALLBACK_MODEL}") }
    judge_with(FALLBACK_MODEL, ground)
  end

  def judge_with(model, ground)
    OtariClient.new.chat_structured(
      model: model,
      name: "enrichment_judgment",
      schema: JUDGE_SCHEMA,
      temperature: 0.0,
      messages: [
        { role: "system", content: <<~PROMPT },
          You judge whether a book's stored metadata should be updated against freshly grounded
          web facts (a book club catalogue). Rules:
          - Never invent data. value/quote must come from the GROUNDED FACTS section.
          - source_url must be one of the HARVESTED SOURCES unless you clearly saw it in the facts text.
          - If the stored value is already good and the facts do not clearly contradict it,
            act with "keep_existing".
          - Write description updates in the stored language listed below; drop celebrity endorsements,
            keep 80-300 words.
          - For the cover: the VISION judgment section is authoritative and measured from the actual
            image. The judgment field takes these values ONLY:
              "adequate"    — vision said real_cover AND depicts this book AND quality high_res
              "low_quality" — vision said real_cover but low_res, or vision is unavailable,
                              or the stored image is a placeholder/generic photo
              "missing"     — no cover stored at all
          - Vision saying "not_cover" for the stored image ALWAYS means judgment = "low_quality",
            even when the grounded facts contain a better cover URL. Never "adequate" then.
          - When the grounded facts name a page carrying the real cover (publisher, catalogue, store,
            original edition when possible), cite that exact page URL in cover.source_url so the
            pipeline can extract the image from it.
          - Empty quote => low confidence => nothing will be applied, so if you recommend an update,
            always include the supporting quote.
        PROMPT
        { role: "user", content: judge_prompt(ground) }
      ]
    ).tap do |j|
      Rails.logger.tagged("[enrich ##{@book.id}]") do |l|
        l.info("judged: desc=#{j.dig('description', 'action')} country=#{j.dig('country_of_origin', 'action')}:#{j.dig('country_of_origin', 'value')} " \
          "#{j.dig('country_of_origin', 'source_url').to_s[0, 80]} cover=#{j.dig('cover', 'judgment')} cited=#{j.dig('cover', 'source_url').to_s[0, 100]}")
      end
    end
  end

  def judge_prompt(ground)
    facts = ground[:facts].to_s[0, 6_000]
    cited = Array(ground[:cited_sources]).join("\n  ")
    sources = ground[:sources].join("\n  ")
    language = LANGUAGE_NAMES.fetch(@book.language.to_s, nil) || "the book's original language"
    <<~PROMPT
      === CURRENTLY STORED METADATA ===
      Title: #{@book.title}
      Author: #{@book.author}
      Description (#{language}): #{@book.description.to_s[0, 900]}
      Tags: #{@book.tags.order(:name).pluck(:name).join(', ')}
      Country of origin: #{@book.country_of_origin.presence || "(empty)"}

      === CURRENT COVER QUALITY FACTS (measured by code) ===
      #{old_cover_facts}

      === GROUNDED FACTS (web) ===
      #{facts}

      === CITED SOURCES (referenced by the facts — trusted for attribution) ===
      #{cited}

      === ALL SOURCES CONSULTED during searching (may include noise) ===
      #{sources}
    PROMPT
  end

  # Old-cover facts for the judge; the structured vision result is kept for the
  # audit trail.
  def old_cover_facts
    vision = CoverVisionJudge.new(book: @book).judge!
    @cover_vision_audit = vision

    if vision.verdict != "unknown"
      "Vision judgment of the stored cover:\n" \
        "  verdict: #{vision.verdict} (real book cover? -> #{vision.verdict == 'real_cover'})\n" \
        "  depicts this specific book: #{vision.matches_book}\n" \
        "  quality: #{vision.quality}\n" \
        "  notes: #{vision.detail}"
    else
      url = @book.cover_image
      return "MISSING: no cover image stored (#{vision.detail})" if url.blank?

      probe = probe_image(url)
      host = URI(url).host rescue "unknown"
      placeholder = BookCoverImprover::COVER_PLACEHOLDER_HOSTS.any? { |ph| url.include?(ph) }
      "Stored cover URL: #{url}\nHost: #{host}#{placeholder ? ' (generic placeholder domain)' : ''}\nSize when fetched: #{probe&.dig(:size) || 'unreachable'}"
    end
  end

  # ---- Phase 3: APPLY -------------------------------------------------------

  def commit(judgment, ground, model)
    changes = {}
    audit = {
      "model" => model,
      "cited_sources" => ground[:cited_sources],
      "sources_consulted" => ground[:sources],
      "enriched_at" => Time.current.iso8601,
      "judged" => true
    }

    audit["original_description"] = @book.description if @book.description.present?
    if (description = sanitize_description(judgment.dig("description"), ground))
      changes[:description] = description[:value]
      audit["description_source_url"] = description[:source_url]
      audit["description_confidence"] = description[:confidence]
    end

    audit["original_tags"] = @book.tags.order(:name).pluck(:name) if @book.tags.any?
    if (tags = normalize_tags(judgment.dig("tags", "values"))).any? && judgment.dig("tags", "action") == "update"
      changes[:tags] = tags
    end

    audit["original_country_of_origin"] = @book.country_of_origin if @book.country_of_origin.present?
    if (country = sanitize_country(judgment["country_of_origin"], ground)).present?
      changes[:country_of_origin] = country[:code]
      audit["country_source_url"] = country[:source_url]
      audit["country_confidence"] = country[:confidence]
    end

    audit["cover_judgment"] = judgment["cover"].presence
    if (cover_vision = @cover_vision_audit)
      audit["cover_vision"] = {
        "verdict" => cover_vision.verdict,
        "quality" => cover_vision.quality,
        "matches_book" => cover_vision.matches_book,
        "notes" => cover_vision.detail
      }
    end
    audit["tags_source_url"] = (judgment["tags"]["source_url"] if changes[:tags])
    @book.enrichment = audit.merge(
      "applied_description" => changes.key?(:description),
      "applied_country_of_origin" => changes[:country_of_origin],
      "applied_tags" => (changes[:tags] if changes[:tags])
    ).compact

    @book.description = changes[:description] if changes[:description]
    @book.country_of_origin = changes[:country_of_origin] if changes[:country_of_origin]
    if changes[:tags]
      tag_records = changes[:tags].map { |name| Tag.find_or_create_by!(name: name) }
      @book.tags = tag_records
    end
    @book.enriched_at = Time.current

    @book.save!

    Result.new(
      description_changed: changes.key?(:description),
      tags_added: changes[:tags] || [],
      country_of_origin: @book.country_of_origin,
      country_source: audit["country_source_url"],
      cover_judgment: judgment.dig("cover", "judgment"),
      cover_source_url: judgment.dig("cover", "source_url").presence
    )
  end

  # An update applies only when its citation checks out:
  #   * source_url on the harvested whitelist  -> { confidence: "high" } -> apply
  #   * no/unknown source_url but the verbatim quote
  #     appears verbatim in the grounded facts -> { confidence: "medium" } -> apply
  #   * otherwise                               -> never applied
  def sanitize_country(country_judgment, ground)
    return nil unless country_judgment.is_a?(Hash) && country_judgment["action"] == "update"

    name = country_judgment["value"].to_s.strip
    code = CountryCodes.code_for(name)
    return nil if code.nil? || @book.country_of_origin == code

    source_url = strip_query(country_judgment["source_url"].to_s)
    quote = country_judgment["quote"].to_s.strip
    facts = ground[:facts].to_s
    cited = Array(ground[:cited_sources]).map { |u| strip_query(u) }

    if source_url.present? && cited.include?(source_url)
      { code: code, source_url: source_url, confidence: "high" }
    elsif quote.present? && normalize_space(facts).include?(normalize_space(quote))
      { code: code, source_url: source_url.presence || "quote-verified", confidence: "medium" }
    else
      nil
    end
  end

  def normalize_space(text)
    text.to_s.gsub(/\s+/, " ").strip
  end

  # A description rewrite is accepted when cited like a fact update:
  #   * source_url on the harvested whitelist  -> { confidence: "high" } -> apply
  #   * no/unknown source_url but the verbatim quote
  #     appears verbatim in the grounded facts -> { confidence: "medium" } -> apply
  #     (a wrong source_url does not veto a verifiable quote)
  #   * otherwise                               -> never applied
  def sanitize_description(judgment, ground)
    return nil unless judgment.is_a?(Hash) && judgment["action"] == "update"

    value = judgment["value"].to_s.strip
    return nil if value.blank?
    return nil if value.length < MIN_DESCRIPTION_LENGTH || value.length > MAX_DESCRIPTION_LENGTH

    source_url = strip_query(judgment["source_url"].to_s)
    quote = judgment["quote"].to_s.strip
    cited = Array(ground[:cited_sources]).map { |u| strip_query(u) }
    consulted = Array(ground[:sources]).map { |u| strip_query(u) }

    if source_url.present? && (cited.include?(source_url) || consulted.include?(source_url))
      { value: value, source_url: source_url, confidence: "high" }
    elsif quote.present? && normalize_space(ground[:facts].to_s).include?(normalize_space(quote))
      { value: value, source_url: source_url.presence || "quote-verified", confidence: "medium" }
    else
      nil
    end
  end

  def normalize_tags(values)
    Array(values)
      .map { |value| value.to_s.strip.downcase.gsub(/\s+/, " ") }
      .reject { |value| value.blank? || value.length > MAX_TAG_LENGTH }
      .uniq
      .first(MAX_TAGS)
  end

  # ---- shared helpers -------------------------------------------------------

  WIKIMEDIA_USER_AGENT = "Litloop/1.0 (AI cover enrichment; https://github.com/nebiyuelias1/litloop)".freeze

  def http_get_json(uri, retries: 1)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = WIKIMEDIA_USER_AGENT
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end

    if response.code.to_i == 429 && retries.positive?
      sleep(2)
      return http_get_json(uri, retries: retries - 1)
    end

    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue => e
    Rails.logger.warn("BookMetadataEnricher lookup failed for #{uri}: #{e.message}")
    nil
  end

  def probe_image(url)
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)
    return nil unless response["content-type"].to_s.start_with?("image/")

    size = response["content-length"] ? response["content-length"].to_i : response.body.bytesize
    { size: size, content_type: response["content-type"].to_s }
  rescue => e
    Rails.logger.warn("BookMetadataEnricher probe failed for #{url}: #{e.message}")
    nil
  end

  def strip_query(url)
    # Query params differ per source request; scheme differs between the
    # record (http://books.google.com/...) and the judge's citation
    # (https://...). Normalize both so citation matching is stable.
    url.to_s.gsub(/\?.*\z/, "").sub(/\Ahttp:\/\//, "https://")
  end
end

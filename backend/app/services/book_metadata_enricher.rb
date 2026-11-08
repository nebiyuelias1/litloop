# frozen_string_literal: true

# Enriches a Book's metadata (description, tags, country of origin) using the
# Otari AI gateway.
#
# Anti-hallucination measures:
# * The model is given an evidence bundle (title, author, description, publisher,
#   ISBN, language) and is instructed to extract, not invent.
# * Structured output with a strict JSON schema.
# * The model must return supporting evidence for country_of_origin, or empty.
# * The model outputs an official English country name; CountryCodes converts it
#   to an ISO 3166-1 alpha-2 code. Anything unmappable is dropped.
# * country_of_origin is validated against the ISO code whitelist in Ruby (and
#   again at the model layer) before it can ever be persisted.
# * Tags are normalized (lowercase, length-capped) and reused via find_or_create.
# * The original values are stored in book.enrichment so every enrichment is
#   reversible.
class BookMetadataEnricher
  Result = Struct.new(:description_changed, :tags_added, :country_of_origin, :confidence, keyword_init: true)

  # The model writes the description in the book's language
  LANGUAGE_NAMES = {
    "am" => "Amharic", "en" => "English", "or" => "Oromo", "ar" => "Arabic",
    "fr" => "French", "sw" => "Swahili", "ti" => "Tigrinya", "es" => "Spanish",
    "de" => "German", "it" => "Italian", "pt" => "Portuguese"
  }.freeze

  # Verified working on the hosted gateway (mozilla-hosted account):
  # https://api.otari.ai/api/v1/models
  DEFAULT_MODEL = "openai/gpt-oss-120b"
  MAX_TAGS = 6
  MAX_TAG_LENGTH = 40
  MIN_DESCRIPTION_LENGTH = 30
  MAX_DESCRIPTION_LENGTH = 4_000

  SCHEMA = {
    type: "object",
    properties: {
      description: {
        type: "string",
        description: "Rewritten, improved book description in the requested language, 80-300 words, no celebrity endorsements"
      },
      tags: {
        type: "array",
        maxItems: MAX_TAGS,
        items: { type: "string" },
        description: "2-6 short lowercase tags describing genres, themes and shelf category"
      },
      country_of_origin: {
        type: "string",
        description: "Official English country name, or empty string when the evidence does not clearly establish one"
      },
      country_evidence: {
        type: "string",
        description: "Quote or paraphrase from the evidence supporting country_of_origin, or a short explanation of what is missing or ambiguous when declining; empty string when clearly nothing relevant"
      },
      confidence: {
        type: "string",
        enum: %w[high medium low]
      },
      wikipedia_page: {
        type: "string",
        description: "English Wikipedia article URL about this book (used to verify the country); empty string if unsure"
      }
    },
    required: %w[description tags country_of_origin country_evidence confidence wikipedia_page],
    additionalProperties: false
  }.freeze

  def initialize(book:)
    @book = book
  end

  def enrich!(model: nil)
    model ||= DEFAULT_MODEL
    proposal = propose(model)
    verification = MetadataVerifier.new(book: @book).verify_country(
      model_country_code: CountryCodes.code_for(proposal["country_of_origin"]),
      wikipedia_page: proposal["wikipedia_page"].presence
    )
    changes, audit = apply(proposal, verification, model)
    @book.enriched_at = Time.current
    @book.save!
    Result.new(
      description_changed: changes.key?(:description),
      tags_added: changes[:tags] || [],
      country_of_origin: @book.country_of_origin,
      confidence: proposal["confidence"]
    )
  end

  private

  # Turns the verified proposal into attribute changes plus the audit trail
  # stored in book.enrichment. Verification outcome decides the country.
  def apply(proposal, verification, model)
    changes = {}
    audit = {
      "model" => model,
      "confidence" => proposal["confidence"],
      "country_evidence" => proposal["country_evidence"].presence,
      "country_verification" => verification && {
        "verdict" => verification.verdict,
        "source_country_qid" => verification.source_country_qid,
        "model_country_code" => verification.model_country_code,
        "detail" => verification.detail
      },
      "enriched_at" => Time.current.iso8601
    }

    audit["original_description"] = @book.description if @book.description.present?
    if (description = sanitize_description(proposal["description"]))
      changes[:description] = description
    end

    audit["original_tags"] = @book.tags.order(:name).pluck(:name) if @book.tags.any?
    if (tags = normalize_tags(proposal["tags"])).any?
      changes[:tags] = tags
    end

    audit["original_country_of_origin"] = @book.country_of_origin if @book.country_of_origin.present?
    if (country = validate_country(proposal, verification)).present?
      changes[:country_of_origin] = country
    end

    @book.enrichment = audit.merge(
      "applied_description" => changes.key?(:description),
      "applied_tags" => (changes[:tags] if changes[:tags]),
      "applied_country_of_origin" => changes[:country_of_origin]
    ).compact

    @book.description = changes[:description] if changes[:description]
    @book.country_of_origin = changes[:country_of_origin] if changes[:country_of_origin]
    if changes[:tags]
      tags = changes[:tags].map { |name| Tag.find_or_create_by!(name: name) }
      @book.tags = tags
    end

    [ changes, audit ]
  end

  def sanitize_description(value)
    return nil if value.blank?
    return nil if value.length < MIN_DESCRIPTION_LENGTH || value.length > MAX_DESCRIPTION_LENGTH

    value.strip
  end

  # Country gate that consults the verification verdict:
  #   confirmed     -> store (source-backed)
  #   no_source     -> fall back to evidence + confidence gates
  #   disagreement  -> reject the proposal entirely
  def validate_country(proposal, verification)
    case verification&.verdict
    when "confirmed"
      verification.country_code
    when "disagreement", "rejected"
      nil
    when "no_source", nil
      fallback_country_code(proposal)
    end
  end

  def fallback_country_code(proposal)
    return nil if proposal["country_evidence"].to_s.strip.blank?
    return nil unless %w[high medium].include?(proposal["confidence"])

    result = CountryCodes.code_for(proposal["country_of_origin"])
    result if @book.country_of_origin.blank? || (result.present? && @book.country_of_origin == result)
  end

  def normalize_tags(values)
    Array(values)
      .map { |value| value.to_s.strip.downcase.gsub(/\s+/, " ") }
      .reject { |value| value.blank? || value.length > MAX_TAG_LENGTH }
      .uniq
      .first(MAX_TAGS)
  end

  def propose(model)
    OtariClient.new.chat_structured(
      model: model,
      name: "book_metadata",
      schema: SCHEMA,
      temperature: 0.2,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: evidence_prompt }
      ]
    )
  end

  def system_prompt
    language = LANGUAGE_NAMES.fetch(@book.language.to_s, nil) || "the book's original language"
    <<~PROMPT
      You are an assistant for a book club application. You enrich book metadata from EVIDENCE you are given.

      Rules:
      - Never invent facts that are not supported by the evidence.
      - Extract and synthesize; if the evidence is insufficient, return an empty country with low confidence.
      - When declining country_of_origin, country_evidence must state what is missing or ambiguous
        (e.g. "author is of mixed ethnicity and nationality is not established by the evidence").
      - Write the description in #{language}.
      - Tags must be short lowercase English words (e.g. "fiction", "coming of age").
      - country_of_origin must be an official English country name, only when the evidence clearly supports it.
    PROMPT
  end

  def evidence_prompt
    parts = [ "Title: #{@book.title}", "Author: #{@book.author}" ]
    parts << "Publisher: #{@book.publisher}" if @book.publisher.present?
    parts << "Published: #{@book.published_at.year}" if @book.published_at.present?
    parts << "ISBN: #{@book.isbn}" if @book.isbn.present?
    parts << "Language: #{@book.language}" if @book.language.present?
    parts << "Existing description: #{@book.description[0, 1_000]}" if @book.description.present?
    if (fresh = fresh_lookup_candidates.presence)
      fresh.each_with_index do |result, i|
        parts << "External catalog result ##{i + 1} (#{result['source']}):"
        parts << "  categories: #{result['categories'].join(', ')}" if result["categories"].present?
        parts << "  language: #{result['language']}" if result["language"].present?
        parts << "  description: #{result['description'].to_s[0, 400]}" if result["description"].present?
      end
    end
    tags = Tag.order(:name).limit(100).pluck(:name)
    if tags.any?
      parts << "Existing tags in our catalogue (prefer these when fitting): #{tags.join(', ')}"
    end
    parts.join("\n")
  end

  # Fresh external-catalog evidence for the proposal phase: normalized to plain
  # hashes so it stays JSON-friendly. Empty on any failure (the enrichment
  # proceeds with row evidence only).
  def fresh_lookup_candidates
    return [] if Rails.env.test?

    results = BookLookup::Finder.new(title: @book.title, author: @book.author, max_candidates: 2).find || []
    results.first(2).map do |result|
      { source: result.source, categories: Array(result.categories), language: result.language,
        description: result.description || "" }
    end
  rescue => e
    Rails.logger.warn("BookMetadataEnricher fresh lookup failed: #{e.message}")
    []
  end
end

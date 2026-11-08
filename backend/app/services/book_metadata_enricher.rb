# frozen_string_literal: true

# Enriches a Book's metadata (description, tags, country) using the Otari AI
# gateway.
#
# Policy (owner decision): the LLM proposes and we apply directly, gated by
# per-field confidence. No page_count updates.
#
# Safety gates (small and cheap):
# * Structured output with a strict JSON schema.
# * country must map to a real ISO 3166-1 alpha-2 code; requires cited evidence
#   and the model reporting medium/high confidence.
# * Tags normalized (lowercase, length-capped) and reused via find_or_create.
# * Original values stored in book.enrichment so every enrichment is reversible.
class BookMetadataEnricher
  Result = Struct.new(:description_changed, :tags_added, :country_of_origin, :country_confidence, keyword_init: true)

  # The model writes the description in the book's language
  LANGUAGE_NAMES = {
    "am" => "Amharic", "en" => "English", "or" => "Oromo", "ar" => "Arabic",
    "fr" => "French", "sw" => "Swahili", "ti" => "Tigrinya", "es" => "Spanish",
    "de" => "German", "it" => "Italian", "pt" => "Portuguese"
  }.freeze

  # Verified working on the hosted gateway (mozilla-hosted accounts):
  # https://api.otari.ai/api/v1/models
  DEFAULT_MODEL = "openai/gpt-oss-120b"
  # Escalation model for fields the open-weight model declines; frontier world
  # knowledge fills what the smaller model won't.
  FALLBACK_MODEL = "mistral/mistral-large-latest"
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
      country_confidence: {
        type: "string",
        enum: %w[high medium low],
        description: "Confidence in country_of_origin only"
      }
    },
    required: %w[description tags country_of_origin country_evidence country_confidence],
    additionalProperties: false
  }.freeze

  def initialize(book:)
    @book = book
  end

  def enrich!(model: nil, fresh_lookup: nil)
    model ||= DEFAULT_MODEL
    lookup = fresh_lookup || fresh_lookup_candidates
    proposal = propose(model, lookup)
    proposal = escalate_fields(proposal, FALLBACK_MODEL, lookup)
    changes, audit = apply(proposal, lookup, model)
    @book.enriched_at = Time.current
    @book.save!
    Result.new(
      description_changed: changes.key?(:description),
      tags_added: changes[:tags] || [],
      country_of_origin: @book.country_of_origin,
      country_confidence: proposal["country_confidence"]
    )
  end

  private

  # Otari's routing story, applied at the app level: the open-weight model
  # answers first; when it declines the country field, the frontier fallback
  # model fills it.
  def escalate_fields(proposal, fallback_model, lookup)
    country_declined = proposal["country_of_origin"].to_s.strip.blank?
    return proposal unless country_declined

    fallback = propose(fallback_model, lookup)
    merged = proposal.dup
    escalated = []

    if country_declined && fallback["country_of_origin"].to_s.strip.present?
      merged["country_of_origin"] = fallback["country_of_origin"]
      merged["country_evidence"] = fallback["country_evidence"]
      merged["country_confidence"] = fallback["country_confidence"]
      escalated << "country_of_origin"
    end

    merged["escalated_with"] = fallback_model if escalated.any?
    merged["escalated_fields"] = escalated if escalated.any?
    merged
  rescue OtariClient::Error => e
    Rails.logger.warn("BookMetadataEnricher escalation failed: #{e.message}")
    proposal
  end

  # Turns the proposal into attribute changes plus the audit trail stored in
  # book.enrichment.
  def apply(proposal, lookup, model)
    changes = {}
    audit = {
      "model" => model,
      "escalated_with" => proposal["escalated_with"].presence,
      "escalated_fields" => proposal["escalated_fields"].presence,
      "country_confidence" => proposal["country_confidence"],
      "country_evidence" => proposal["country_evidence"].presence,
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
    if (country = sanitize_country(proposal)).present?
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

  # Model outputs an official English country name; stored as ISO alpha-2.
  # Requires cited evidence and medium/high confidence.
  def sanitize_country(proposal)
    name = proposal["country_of_origin"].to_s.strip
    return nil if name.blank?
    return nil if proposal["country_evidence"].to_s.strip.blank?
    return nil unless %w[high medium].include?(proposal["country_confidence"])

    code = CountryCodes.code_for(name)
    code
  end

  def normalize_tags(values)
    Array(values)
      .map { |value| value.to_s.strip.downcase.gsub(/\s+/, " ") }
      .reject { |value| value.blank? || value.length > MAX_TAG_LENGTH }
      .uniq
      .first(MAX_TAGS)
  end

  def propose(model, lookup)
    OtariClient.new.chat_structured(
      model: model,
      name: "book_metadata",
      schema: SCHEMA,
      temperature: 0.2,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: evidence_prompt(lookup) }
      ]
    )
  end

  def system_prompt
    language = LANGUAGE_NAMES.fetch(@book.language.to_s, nil) || "the book's original language"
    <<~PROMPT
      You are an assistant for a book club application. You enrich book metadata from EVIDENCE you are given.

      Rules:
      - Never invent facts that are not supported by the evidence.
      - Extract and synthesize; if the evidence is insufficient for a field, return an empty answer
        for that field and low confidence FOR THAT FIELD ONLY — do not let one uncertain field
        downgrade unrelated fields.
      - When declining country_of_origin, country_evidence must state what is missing or ambiguous
        (e.g. "author is of mixed ethnicity and nationality is not established by the evidence").
      - Write the description in #{language}.
      - Tags must be short lowercase English words (e.g. "fiction", "coming of age").
      - country_of_origin must be an official English country name, only when the evidence clearly supports it.
    PROMPT
  end

  def evidence_prompt(lookup)
    parts = [ "Title: #{@book.title}", "Author: #{@book.author}" ]
    parts << "Publisher: #{@book.publisher}" if @book.publisher.present?
    parts << "Published: #{@book.published_at.year}" if @book.published_at.present?
    parts << "ISBN: #{@book.isbn}" if @book.isbn.present?
    parts << "Language: #{@book.language}" if @book.language.present?
    parts << "Existing description: #{@book.description[0, 1_000]}" if @book.description.present?
    Array(lookup).each_with_index do |result, i|
      parts << "External catalog result ##{i + 1} (#{result['source']}):"
      parts << "  categories: #{result['categories'].join(', ')}" if result["categories"].present?
      parts << "  language: #{result['language']}" if result["language"].present?
      parts << "  description: #{result['description'].to_s[0, 400]}" if result["description"].present?
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

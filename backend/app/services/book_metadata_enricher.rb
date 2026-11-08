# frozen_string_literal: true

# Enriches a Book's metadata (description, tags, country of origin) using the
# Otari AI gateway.
#
# Anti-hallucination measures:
# * The model is given an evidence bundle (title, author, description, publisher,
#   ISBN, language) and is instructed to extract, not invent.
# * Structured output with a strict JSON schema.
# * The model must return supporting evidence for country_of_origin, or empty.
# * country_of_origin is validated against a country-name whitelist in Ruby
#   before it can ever be persisted.
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

  # The model must not invent country names; validate against this list
  VALID_COUNTRIES = %w[
    Afghanistan Albania Algeria Argentina Armenia Australia Austria Azerbaijan Bahrain Bangladesh
    Belarus Belgium Belize Benin Bhutan Bolivia Bosnia\ and\ Herzegovina Botswana Brazil Bulgaria
    Burkina\ Faso Burundi Cambodia Cameroon Canada Chad Chile China Colombia Congo Costa\ Rica
    Croatia Cuba Cyprus Czechia Denmark Djibouti Dominica Dominican\ Republic Ecuador Egypt El\ Salvador
    Eritrea Estonia Eswatini Ethiopia Fiji Finland France Gabon Gambia Georgia Germany Ghana Greece
    Grenada Guatemala Guinea Guinea-Bissau Guyana Haiti Honduras Hungary Iceland India Indonesia Iran
    Iraq Ireland Israel Italy Ivory\ Coast Jamaica Japan Jordan Kazakhstan Kenya Kiribati Kuwait
    Kyrgyzstan Laos Latvia Lebanon Lesotho Liberia Libya Liechtenstein Lithuania Luxembourg Madagascar
    Malawi Malaysia Maldives Mali Malta Mauritania Mauritius Mexico Moldova Monaco Mongolia Montenegro
    Morocco Mozambique Myanmar Namibia Nauru Nepal Netherlands New\ Zealand Nicaragua Niger Nigeria
    North\ Korea North\ Macedonia Norway Oman Pakistan Palau Palestine Panama Papua\ New\ Guinea Paraguay
    Peru Philippines Poland Portugal Qatar Romania Russia Rwanda Samoa San\ Marino Saudi\ Arabia Senegal
    Serbia Seychelles Sierra\ Leone Singapore Slovakia Slovenia Solomon\ Islands Somalia South\ Africa
    South\ Korea South\ Sudan Spain Sri\ Lanka Sudan Suriname Sweden Switzerland Syria Taiwan Tajikistan
    Tanzania Thailand Timor-Leste Togo Tonga Trinidad\ and\ Tobago Tunisia Turkey Turkmenistan Tuvalu
    Uganda Ukraine United\ Arab\ Emirates United\ Kingdom United\ States Uruguay Uzbekistan Vanuatu
    Venezuela Vietnam Yemen Zambia Zimbabwe
  ].to_set

  DEFAULT_MODEL = "openai:gpt-oss-120b"
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
        description: "Short quote or paraphrase from the evidence supporting country_of_origin, empty string when none"
      },
      confidence: {
        type: "string",
        enum: %w[high medium low]
      }
    },
    required: %w[description tags country_of_origin country_evidence confidence],
    additionalProperties: false
  }.freeze

  def initialize(book:)
    @book = book
  end

  def enrich!(model: nil)
    model ||= ENV.fetch("OTARI_MODEL", DEFAULT_MODEL)
    payload = generate_payload(model)
    changes, audit = apply(payload, model)
    @book.enriched_at = Time.current
    @book.save!
    Result.new(
      description_changed: changes.key?(:description),
      tags_added: changes[:tags] || [],
      country_of_origin: @book.country_of_origin,
      confidence: payload["confidence"]
    )
  end

  private

  # Turns a model payload into attribute changes plus the audit trail stored in
  # book.enrichment. Gates every field before it can reach the database.
  def apply(payload, model)
    changes = {}
    audit = {
      "model" => model,
      "confidence" => payload["confidence"],
      "country_evidence" => payload["country_evidence"].presence,
      "enriched_at" => Time.current.iso8601
    }

    audit["original_description"] = @book.description if @book.description.present?
    if (description = sanitize_description(payload["description"]))
      changes[:description] = description
    end

    audit["original_tags"] = @book.tags.order(:name).pluck(:name) if @book.tags.any?
    if (tags = normalize_tags(payload["tags"])).any?
      changes[:tags] = tags
    end

    audit["original_country_of_origin"] = @book.country_of_origin if @book.country_of_origin.present?
    if (country = sanitize_country(payload)).present?
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

  def sanitize_country(payload)
    name = payload["country_of_origin"].to_s.strip
    evidence = payload["country_evidence"].to_s.strip
    return nil if name.blank? || evidence.blank?
    return nil unless %w[high medium].include?(payload["confidence"])
    return nil unless VALID_COUNTRIES.include?(name)

    name
  end

  def normalize_tags(values)
    Array(values)
      .map { |value| value.to_s.strip.downcase.gsub(/\s+/, " ") }
      .reject { |value| value.blank? || value.length > MAX_TAG_LENGTH }
      .uniq
      .first(MAX_TAGS)
  end

  def generate_payload(model)
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
    tags = Tag.order(:name).limit(100).pluck(:name)
    if tags.any?
      parts << "Existing tags in our catalogue (prefer these when fitting): #{tags.join(', ')}"
    end
    parts.join("\n")
  end
end

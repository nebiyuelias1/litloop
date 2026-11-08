# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Improves a Book's cover image.
#
# Cover-credential pipeline:
# 1. A cheap structured model call (Otari gateway, no tool loop) proposes the
#    book's Wikipedia article and Wikimedia Commons file-page URLs. Models are
#    good at naming articles; they must never be trusted for image bytes.
# 2. Ruby resolves those into direct image URLs:
#      - Wikipedia article  -> pageimages API (the article's infobox cover)
#      - Commons file page  -> Special:FilePath (redirects to the file)
#    A deterministic Ruby-side title search is the fallback when the model
#    returns nothing usable.
# 3. Every candidate is verified in Ruby (an image, plausible book-cover size,
#    and, for placeholder covers like generic unsplash photos, any distinct
#    real cover wins) before book.cover_image may change.
class BookCoverImprover
  Result = Struct.new(:improved, :old_cover, :new_cover, :reason, keyword_init: true)

  # Verified working on the hosted gateway (mozilla-hosted account):
  # https://api.otari.ai/api/v1/models
  DEFAULT_MODEL = "openai/gpt-oss-120b"
  MIN_IMAGE_BYTES = 15_000       # thumbnails are typically < 15 KiB
  MAX_IMAGE_BYTES = 10_000_000
  VERIFY_OPEN_TIMEOUT = 5
  VERIFY_READ_TIMEOUT = 10

  VALIDATION_SCHEMA = {
    type: "object",
    properties: {
      wikipedia_page: {
        type: "string",
        description: "Full URL of the English Wikipedia article about this book, or empty if unsure"
      },
      commons_file_pages: {
        type: "array",
        items: { type: "string" },
        description: "Full URLs of Wikimedia Commons file pages (commons.wikimedia.org/wiki/File:...) showing this book's cover"
      }
    },
    required: %w[wikipedia_page commons_file_pages],
    additionalProperties: false
  }.freeze

  def initialize(book:)
    @book = book
  end

  def improve!(model: nil)
    model ||= DEFAULT_MODEL
    candidates = collect_candidates(model)

    best = candidates.filter_map do |url|
      next if url.blank?
      next if url == @book.cover_image
      probe = probe_image(url)
      next if probe.nil?
      next if probe[:size] < MIN_IMAGE_BYTES || probe[:size] > MAX_IMAGE_BYTES

      { url: url, size: probe[:size] }
    end.max_by { |candidate| candidate[:size] }

    return kept(candidates.any? ? "no candidate verified as a usable image" : "no candidates") if best.nil?

    if @book.cover_image == best[:url]
      return kept("best candidate is already the current cover")
    end

    audit = @book.enrichment || {}
    audit["cover"] = {
      "old_cover" => @book.cover_image,
      "new_cover" => best[:url],
      "old_size_bytes" => probe_image(@book.cover_image)&.fetch(:size, nil),
      "new_size_bytes" => best[:size],
      "improved_at" => Time.current.iso8601
    }
    @book.update!(cover_image: best[:url], enrichment: audit)
    Result.new(improved: true, old_cover: audit["cover"]["old_cover"], new_cover: best[:url], reason: "verified higher-quality cover found")
  rescue OtariClient::Error => e
    Result.new(improved: false, old_cover: @book.cover_image, new_cover: nil, reason: "gateway error: #{e.message}")
  end

  private

  def kept(reason)
    Result.new(improved: false, old_cover: @book.cover_image, new_cover: nil, reason: reason)
  end

  # Collects candidate image URLs Wikipedia-wise, AI-proposed first, Ruby
  # search as the fallback.
  def collect_candidates(model)
    candidates = []

    ai = ai_candidates(model)
    candidates.concat(ai)

    if candidates.empty? || @book.cover_image.to_s.include?("unsplash")
      candidates.concat(deterministic_candidates)
    end

    candidates.compact.uniq
  end

  # Step 1: the model names pages, Ruby owns URLs -> images.
  def ai_candidates(model)
    client = OtariClient.new
    payload = client.chat_structured(
      model: model,
      name: "cover_candidates",
      schema: VALIDATION_SCHEMA,
      temperature: 0.0,
      messages: [
        { role: "user", content: <<~PROMPT }
          Find the cover image for this book.

          Book: "#{@book.title}" by #{@book.author}
          Current cover: #{@book.cover_image || "none"}

          Return:
          - wikipedia_page: the English Wikipedia article about this book (empty if unsure)
          - commons_file_pages: Wikimedia Commons file page URLs for this book's cover
        PROMPT
      ]
    )

    urls = []
    wiki = payload["wikipedia_page"].to_s
    urls << page_image_url(wiki) if wiki.include?("wikipedia.org/wiki/")

    Array(payload["commons_file_pages"]).each do |file_page|
      urls << commons_image_url(file_page)
    end
    urls
  rescue OtariClient::Error => e
    Rails.logger.warn("BookCoverImprover AI candidates failed: #{e.message}")
    []
  end

  # Deterministic fallback: Wikipedia's own search API finds the article.
  def deterministic_candidates
    article = wikipedia_search_title
    return [] if article.blank?

    [ page_image_url("https://en.wikipedia.org/wiki/#{URI.encode_www_form_component(article.tr(" ", "_"))}") ]
  end

  def wikipedia_search_title
    return nil if Rails.env.test?

    uri = URI("https://en.wikipedia.org/w/api.php")
    uri.query = URI.encode_www_form(
      action: "query", list: "search", srsearch: "#{@book.title} #{@book.author}".strip,
      format: "json", srlimit: 1
    )
    response = http_get_json(uri)
    response&.dig("query", "search", 0, "title")
  end

  def page_image_url(article_url)
    title = URI(article_url).path.split("/").last  # e.g. Things_Fall_Apart
    return nil if title.blank?

    uri = URI("https://#{URI(article_url).host}/w/api.php")
    uri.query = URI.encode_www_form(
      action: "query", prop: "pageimages", titles: title.tr("_", " "),
      format: "json", pithumbsize: 800, redirects: 1
    )
    data = http_get_json(uri)
    page = data&.dig("query", "pages", 0)
    thumbnail = page&.dig("thumbnail", "source")
    # Avoid serving SVG logo/vector images as covers
    thumbnail unless thumbnail.to_s.end_with?(".svg")
  end

  def commons_image_url(file_page)
    return nil unless file_page.include?("commons.wikimedia.org/wiki/File:")

    file = URI(file_page).path.split("/").last.delete_prefix("File:")
    "https://commons.wikimedia.org/wiki/Special:FilePath/#{file}?width=800"
  end

  def http_get_json(uri)
    request = Net::HTTP::Get.new(uri)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: VERIFY_OPEN_TIMEOUT, read_timeout: VERIFY_READ_TIMEOUT) do |http|
      http.request(request)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue => e
    Rails.logger.warn("BookCoverImprover lookup failed for #{uri}: #{e.message}")
    nil
  end

  # Downloads the URL and reports size/content type; nil unless really an image.
  def probe_image(url)
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: VERIFY_OPEN_TIMEOUT, read_timeout: VERIFY_READ_TIMEOUT) do |http|
      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      content_type = response["content-type"].to_s
      return nil unless content_type.start_with?("image/")

      size = response["content-length"] ? response["content-length"].to_i : response.body.bytesize
      { size: size, content_type: content_type }
    end
  rescue => e
    Rails.logger.warn("BookCoverImprover probe failed for #{url}: #{e.message}")
    nil
  end
end

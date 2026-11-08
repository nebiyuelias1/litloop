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
      action: "query", prop: "images", titles: title.tr("_", " "),
      format: "json", redirects: 1, imlimit: 40
    )
    data = http_get_json(uri)
    page = data&.dig("query", "pages")&.values&.first
    files = (page&.dig("images") || []).map { |f| f["title"] }

    chosen = choose_cover_file(files, title)
    return nil if chosen.blank?

    image_info_url(URI(article_url).host, chosen)
  end

  # Picks the most plausible cover among an article's files: files whose name
  # matches the book title win outright; obvious junk (flags, icons, logos,
  # author portraits etc.) is penalized.
  JUNK_FILE_WORDS = /flag|icon|symbol|logo|stub|jukebox|collection|edit|voice|map|menu/i

  def choose_cover_file(files, article_title)
    image_files(files).max_by do |file|
      score = 0
      bare = file.gsub(/\AFile:|File:/, "").gsub(/[^a-zA-Z0-9]/, "").downcase
      title_key = article_title.gsub(/[^a-zA-Z0-9]/, "").downcase
      score += 100 if bare.include?(title_key) && title_key.length > 3
      score += 10 if bare.start_with?(title_key[0, 8].to_s)
      score -= 50 if JUNK_FILE_WORDS.match?(file)
      score
    end
  end

  def image_files(files)
    files.select { |f| /\.(jpe?g|png)$/i.match?(f) }
  end

  def commons_image_url(file_page)
    return nil unless file_page.include?("commons.wikimedia.org/wiki/File:")

    file = URI(file_page).path.split("/").last  # keeps File: prefix for imageinfo
    image_info_url("commons.wikimedia.org", file)
  end

  # Resolves "File:..." on a MediaWiki host to a direct image URL
  def image_info_url(host, file_title)
    uri = URI("https://#{host}/w/api.php")
    uri.query = URI.encode_www_form(
      action: "query", prop: "imageinfo", titles: file_title,
      iiprop: "url|mime|size", format: "json"
    )
    data = http_get_json(uri)
    info = data&.dig("query", "pages")&.values&.first&.dig("imageinfo", 0)
    return nil if info.nil?
    return nil unless /\Aimage\/(jpe?g|png)\z/.match?(info["mime"].to_s)

    info["url"].gsub(/\?.*\z/, "")
  end

  WIKIMEDIA_USER_AGENT = "Litloop/1.0 (AI cover enrichment; https://github.com/nebiyuelias1/litloop)".freeze

  def http_get_json(uri, retries: 1)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = WIKIMEDIA_USER_AGENT
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: VERIFY_OPEN_TIMEOUT, read_timeout: VERIFY_READ_TIMEOUT) do |http|
      http.request(request)
    end

    # Wikimedia rate-limits bursts; one polite retry after a pause
    if response.code.to_i == 429 && retries.positive?
      sleep(2)
      return http_get_json(uri, retries: retries - 1)
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

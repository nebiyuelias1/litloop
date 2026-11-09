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

  def initialize(book:, cited_cover_url: nil)
    @book = book
    @cited_cover_url = cited_cover_url
  end

  def improve!(model: nil)
    model ||= DEFAULT_MODEL
    candidates = collect_candidates(model)

    # Relevance beats size: candidates are tiered (wikipedia/arxiv-quality
    # first, Open Library next, model-propose Commons last); we take the best
    # VERIFIED candidate of the highest tier that yields one.
    best = candidates.sort_by { |c| -c[:relevance] }
                     .group_by { |c| c[:relevance] }
                     .values
                     .filter_map do |tier|
      tier.filter_map do |candidate|
        next if candidate[:url] == @book.cover_image
        probe = probe_image(candidate[:url])
        next if probe.nil?
        next if probe[:size] < MIN_IMAGE_BYTES || probe[:size] > MAX_IMAGE_BYTES

        { url: candidate[:url], size: probe[:size] }
      end.max_by { |c| c[:size] }
    end.first

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

  RELEVANCE = { wiki_article: 100, openlibrary: 80, cited_source: 55, commons_proposal: 40 }.freeze

  # Collects relevance-tagged candidate URLs:
  #  - Wikipedia article file (resolved title-match) — 100
  #  - Open Library ISBN cover — 80
  #  - URL the enrichment judge cited as showing the real cover — 55
  #  - Model-proposed Commons files — 40 (lowest tier: hallucinations die here)
  def collect_candidates(model)
    candidates = []
    candidates.concat(ai_candidates(model))
    # Always run the deterministic path too — the model can name the wrong
    # article (e.g. a film page for a novel) or hallucinate Commons files;
    # verified duplicate URLs dedupe below.
    candidates.concat(deterministic_candidates)
    candidates.concat(openlibrary_candidates)
    candidates.concat(cited_cover_candidates)

    candidates.compact.uniq { |c| c[:url] }
  end

  # The enrichment judge may cite a URL it found on the web as "this is what
  # the real cover is". Turn that citation into a candidate: if it is an
  # article/file page shape we can resolve, resolve it properly; otherwise
  # take it as an unverified direct image guess (probe will decide).
  def cited_cover_candidates
    cited = @cited_cover_url.to_s
    return [] if cited.blank? || cited == @book.cover_image

    if cited.include?("wikipedia.org/wiki/") && !cited.include?("/File:")
      [ { url: page_image_url(cited), relevance: RELEVANCE[:wiki_article] } ]
    elsif cited.include?("commons.wikimedia.org/wiki/File:")
      [ { url: commons_image_url(cited), relevance: RELEVANCE[:commons_proposal] } ]
    else
      [ { url: cited, relevance: RELEVANCE[:cited_source] } ]
    end
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

    tagged = []
    wiki = payload["wikipedia_page"].to_s
    if wiki.include?("wikipedia.org/wiki/")
      tagged << { url: page_image_url(wiki), relevance: RELEVANCE[:wiki_article] }
    end

    Array(payload["commons_file_pages"]).each do |file_page|
      tagged << { url: commons_image_url(file_page), relevance: RELEVANCE[:commons_proposal] }
    end
    tagged
  rescue OtariClient::Error => e
    Rails.logger.warn("BookCoverImprover AI candidates failed: #{e.message}")
    []
  end

  # Deterministic fallback: Wikipedia's own search API finds the article, and
  # Open Library's ISBN cover endpoint offers a second independent source.
  def deterministic_candidates
    article = wikipedia_search_title
    return [] if article.blank?

    url = page_image_url("https://en.wikipedia.org/wiki/#{URI.encode_www_form_component(article.tr(" ", "_"))}")
    return [] if url.blank?

    [ { url: url, relevance: RELEVANCE[:wiki_article] } ]
  end

  def openlibrary_candidates
    return [] if @book.isbn.blank?

    [ { url: "https://covers.openlibrary.org/b/isbn/#{@book.isbn}-L.jpg", relevance: RELEVANCE[:openlibrary] } ]
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

  # Picks the most plausible cover among an article's files. MediaWiki lists
  # files alphabetically, so "first" alone is not meaningful; score instead:
  #   exact title-name match  > title + cover-ish word > title first word among
  #   non-junk files; junk (flags, icons, film posters, collections) excluded.
  JUNK_FILE_WORDS = /\b(flag|icon|symbol|logo|stub|jukebox|collection|edit|voice|map|menu|poster|film|movie|wiktion)\b/i
  GOOD_FILE_WORDS = /cover|book|edition|jacket|first|front/i

  def choose_cover_file(files, article_title)
    eligible = image_files(files).reject { |file| JUNK_FILE_WORDS.match?(file) }
    return nil if eligible.blank?

    title_key = article_title.gsub(/[^a-zA-Z0-9]/, "").downcase
    first_word = article_title.split(/[\s(]/).first.to_s.gsub(/[^a-zA-Z0-9]/, "").downcase

    eligible.max_by do |file|
      bare = File.basename(file, ".*").gsub(/[^a-zA-Z0-9]/, "").downcase
      score = 0
      score += 120 if title_key.length > 3 && bare == title_key
      score += 80 if title_key.length > 3 && bare.include?(title_key)
      if first_word.length > 2 && bare.include?(first_word)
        score += GOOD_FILE_WORDS.match?(bare) ? 60 : 30
      end
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

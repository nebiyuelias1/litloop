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
  # Domains whose images are known catalogue placeholders (generic photos,
  # not a specific book's cover). A cover on one of these always triggers an
  # improvement attempt regardless of LLM verdicts.
  COVER_PLACEHOLDER_HOSTS = %w[images.unsplash.com unsplash.com source.unsplash.com].freeze
  Result = Struct.new(:improved, :old_cover, :new_cover, :reason, keyword_init: true)
  MAX_VISION_CHECKS = 5

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
      },
      cover_pages: {
        type: "array",
        items: { type: "string" },
        description: "Any other web pages that show the real published cover image (Goodreads, publisher pages, store listings, blogs)"
      }
    },
    required: %w[wikipedia_page commons_file_pages cover_pages],
    additionalProperties: false
  }.freeze

  def initialize(book:, cited_cover_url: nil)
    @book = book
    @cited_cover_url = cited_cover_url
  end

  def improve!(model: nil)
    model ||= DEFAULT_MODEL
    cover_log("improver start (book cover=#{@book.cover_image.to_s[0, 60]})")
    candidates = collect_candidates(model)
    candidates.each { |c| cover_log("candidate #{c[:url].to_s[0, 100]} (tier #{c[:relevance]})") }

    ordered = candidates
      .reject { |c| c[:url].blank? || c[:url] == @book.cover_image }
      .sort_by { |c| [ -c[:relevance], 0 ] }

    judge = CoverVisionJudge.new(book: @book)

    # Budget for vision checks (each is a gateway upload + completion): the
    # ordered candidates get at most MAX_VISION_CHECKS vision passes; when the
    # budget runs dry the best probed candidate is accepted deterministically
    # and flagged vision=unverified.
    vision_budget = MAX_VISION_CHECKS

    chosen = nil
    best_probed = nil
    unverified = nil
    ordered.find do |candidate|
      image = fetch_image_bytes(candidate[:url])
      cover_log("fetch #{candidate[:url].to_s[0, 90]} -> #{image ? image[:size] : 'nil'}B")
      if image.nil? || image[:size] < MIN_IMAGE_BYTES || image[:size] > MAX_IMAGE_BYTES
        next
      end

      best_probed ||= { url: candidate[:url], size: image[:size], content_type: image[:content_type], bytes: image[:bytes] }
      if vision_budget <= 0
        next
      end
      vision_budget -= 1

      vision = judge.inspect_bytes(bytes: image[:bytes], content_type: image[:content_type], filename: "cover.jpg")
      cover_log("vision #{candidate[:url].to_s[0, 80]} -> #{vision.verdict}/#{vision.quality} matches=#{vision.matches_book} #{vision.detail.to_s[0, 80]}")

      if vision.verdict == "unknown"
        unverified ||= { url: candidate[:url], size: image[:size] }
        next
      end
      if vision.verdict == "real_cover" && vision.matches_book
        chosen = { url: candidate[:url], size: image[:size], vision: vision }
        true
      else
        false
      end
    end

    if chosen.nil? && best_probed && vision_budget <= 0
      cover_log("vision budget exhausted; accepting best probed candidate unverified")
      chosen = { url: best_probed[:url], size: best_probed[:size], vision: "unverified" }
    end

    if chosen.nil?
      reason = unverified ? "no candidate verified by vision; best unverified: #{unverified[:url][0, 80]}" : (candidates.any? ? "no candidate verified as a usable image" : "no candidates")
      cover_log("kept (#{reason})")
      return kept(reason)
    end

    swap(chosen, chosen[:vision])
  rescue OtariClient::Error => e
    cover_log("gateway error: #{e.message}")
    Result.new(improved: false, old_cover: @book.cover_image, new_cover: nil, reason: "gateway error: #{e.message}")
  end

  def swap(chosen, vision)
    audit = @book.enrichment || {}
    audit["cover"] = {
      "old_cover" => @book.cover_image,
      "new_cover" => chosen[:url],
      "old_size_bytes" => probe_image(@book.cover_image)&.fetch(:size, nil),
      "new_size_bytes" => chosen[:size],
      "vision_verdict" => vision.is_a?(Struct) || vision.respond_to?(:verdict) ? "#{vision.verdict}/#{vision.quality}" : vision.to_s,
      "improved_at" => Time.current.iso8601
    }
    cover_log("swapped to #{chosen[:url][0, 100]} (#{chosen[:size]} bytes, vision=#{vision.respond_to?(:verdict) ? "#{vision.verdict}/#{vision.quality}" : vision})")
    @book.update!(cover_image: chosen[:url], enrichment: audit)
    Result.new(
      improved: true,
      old_cover: audit["cover"]["old_cover"],
      new_cover: chosen[:url],
      reason: vision.respond_to?(:verdict) ? "verified cover swap (vision: #{vision.verdict} #{vision.quality})" : "cover swap (probe-only, vision budget exhausted)"
    )
  end

  # One-shot candidate verification download: returns bytes + size + type, or
  # nil when the URL is dead/non-image/oversized. Single network pass — probes
  # and vision consume the same bytes.
  def fetch_image_bytes(url)
    response = http_get_following_redirects(URI(url))
    return nil unless response.is_a?(Net::HTTPSuccess)
    return nil unless response["content-type"].to_s.start_with?("image/")

    bytes = response.body.to_s
    return nil if bytes.bytesize > MAX_IMAGE_BYTES

    { bytes: bytes, size: response["content-length"] ? response["content-length"].to_i : bytes.bytesize,
      content_type: response["content-type"].to_s.split(";").first }
  rescue => e
    Rails.logger.warn("BookCoverImprover image fetch failed for #{url}: #{e.message}")
    nil
  end

  def cover_log(message)
    Rails.logger.tagged("[cover ##{@book.id}]") { |l| l.info(message) }
  end

  private

  def kept(reason)
    Result.new(improved: false, old_cover: @book.cover_image, new_cover: nil, reason: reason)
  end

  RELEVANCE = { cited_source: 110, wiki_article: 100, openlibrary: 80, cited_page: 60, commons_proposal: 40 }.freeze

  # Site chrome and placeholder images mined from arbitrary web pages. None of
  # these can be a book cover; rejecting them keeps the vision budget for
  # plausible candidates instead of spending it on category icons and loaders.
  SITE_CHROME_FILE = /logo|icon|spinner|avatar|banner|sprite|\.svg\z|analytics|pixel|tracking|placeholder|no[-_]cover|loader|ajax|cleardot|spacer|social|facebook|twitter|bsky|github|tweet|pantheon|triad|favicon/i

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
  # treat the page as HTML and extract cover-looking images (og:image first).
  def cited_cover_candidates
    cited = @cited_cover_url.to_s
    return [] if cited.blank? || cited == @book.cover_image

    # Open Library cover-by-id URLs: the enrichment judge (grounded by the
    # books MCP) cites e.g. covers.openlibrary.org/b/id/14338907-M.jpg. Upgrade
    # to the large rendering — the -M variant is often under the minimum size.
    if (m = cited.match(%r{covers\.openlibrary\.org/b/id/(\d+)-[SML]\.jpe?g}i))
      return [ { url: "https://covers.openlibrary.org/b/id/#{m[1]}-L.jpg", relevance: RELEVANCE[:cited_source] } ]
    end

    if cited.include?("wikipedia.org/wiki/") && !cited.include?("/File:")
      [ { url: page_image_url(cited), relevance: RELEVANCE[:wiki_article] } ]
    elsif cited.include?("commons.wikimedia.org/wiki/File:")
      [ { url: commons_image_url(cited), relevance: RELEVANCE[:commons_proposal] } ]
    elsif cited.match?(/\.(jpe?g|png|webp|gif)(\?.*)?\z/i)
      [ { url: strip_query(cited), relevance: RELEVANCE[:cited_source] } ]
    else
      candidates = [ { url: cited, relevance: RELEVANCE[:cited_source] } ]
      # Google Books cover endpoints have no file extension and their default
      # zoom renders small; a larger render exists at the same path. Judge the
      # URL as an image directly — if it is HTML instead, fetch_image_bytes
      # rejects it on content-type and nothing is lost.
      if cited.include?("books.google.") && cited.include?("/books/content")
        candidates << { url: cited.sub(/zoom=\d+/, "zoom=2"), relevance: RELEVANCE[:cited_source] }
      end
      candidates.concat(html_page_cover_candidates(cited))
      candidates
    end
  end

  # Arbitrary web pages (publisher/store/blog): pull og:image and <img> tags
  # whose filename looks like a cover, then probe each. None of these are
  # trusted until they pass the same verification as every other candidate.
  def html_page_cover_candidates(page_url)
    return [] if page_url.blank?

    html = http_get_text(page_url)
    return [] if html.blank?

    candidates = []
    # Two-step: find the og:image meta tag text, then its content attribute
    # (single-pass regexes break on Ruby's greedy backtracking here).
    meta_tag = html[/<meta[^>]+og:image[^>]*>/i] || html[/<meta[^>]+og:image.*>/i]
    og = meta_tag && meta_tag[/content=["']([^"']+)["']/i, 1]
    candidates << { url: absolute_uri(page_url, og), relevance: RELEVANCE[:cited_source] } if og

    img_urls = html.scan(/<img[^>]+src=["']([^"']+)["']/i).flatten
                   .map { |src| absolute_uri(page_url, src) }
                   .select { |u| /\Ahttps?:/.match?(u) }
                   .reject { |u| SITE_CHROME_FILE.match?(u) }
                   .reject { |u| u == @book.cover_image }
                   .reject { |u| u.include?("$") || u.include?("{{") }
    # Images whose filenames mention the book or "cover" outrank the rest
    title_key = @book.title.to_s.gsub(/[^a-zA-Z0-9]/i, "").downcase
    img_urls.sort_by { |u|
      u_name = File.basename(URI.parse(u).path.to_s).downcase
      (u_name.include?(title_key) || u_name.include?("cover") ? "0" : "1") + u
    }.first(8).each { |u| candidates << { url: u, relevance: RELEVANCE[:cited_page] } }

    cover_log("cited page #{page_url[0, 80]} -> og=#{og ? og[0, 60].inspect : 'none'}, imgs=#{img_urls.size} (#{candidates.size} candidates)")
    candidates
  end

  def strip_query(url)
    url.to_s.gsub(/\?.*\z/, "").gsub(/[).,;]+\z/, "")
  end

  def absolute_uri(base_url, value)
    URI.join(URI(base_url), value.to_s.strip).to_s
  rescue StandardError => e
    cover_log("bad image url #{value.to_s[0, 60]} on #{base_url.to_s[0, 60]}: #{e.message}")
    nil
  end

  # Step 1: the model names pages, Ruby owns URLs -> images. When the primary
  # model yields nothing resolvable (extra true for non-Latin titles), retry
  # once with the frontier fallback model.
  def ai_candidates(model)
    tagged = ai_candidates_with(model)
    if tagged.compact.empty? && model != BookMetadataEnricher::FALLBACK_MODEL
      cover_log("AI candidates empty on #{model}; escalating to #{BookMetadataEnricher::FALLBACK_MODEL}")
      tagged = ai_candidates_with(BookMetadataEnricher::FALLBACK_MODEL)
    end
    tagged
  end

  def ai_candidates_with(model)
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
          - cover_pages: any other web pages that show the real cover image
            (Goodreads, publisher pages, store listings, blogs). Prefer those with
            the official published cover.
        PROMPT
      ]
    )

    tagged = []
    wiki = clean_proposal_url(payload["wikipedia_page"]).to_s
    if wiki.include?("wikipedia.org/wiki/")
      tagged << { url: page_image_url(wiki), relevance: RELEVANCE[:wiki_article] }
    end

    Array(payload["commons_file_pages"]).each do |file_page|
      tagged << { url: commons_image_url(clean_proposal_url(file_page).to_s), relevance: RELEVANCE[:commons_proposal] }
    end

    Array(payload["cover_pages"]).each do |page_url|
      clean = clean_proposal_url(page_url).to_s
      next if clean.blank?
      cover_log("cover_page proposal: #{clean[0, 90]}")
      tagged.concat(html_page_cover_candidates(clean))
    end
    tagged
  rescue OtariClient::Error => e
    Rails.logger.warn("BookCoverImprover AI candidates failed: #{e.message}")
    []
  end

  # Model-proposed URLs often arrive annotated:
  #   "https://openlibrary.org/works/OL158896W (Open Library – multiple edition
  #    covers, including the original...)"
  # The unicode annotation makes URI() refuse the whole string ("URI must be
  # ascii only"). Extract the bare leading URL instead.
  def clean_proposal_url(value)
    URI.extract(value.to_s, %w[http https]).first
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

  # Fetches a web page for og:image / <img> mining; drops anything past 2 MiB.
  def http_get_text(url)
    response = http_get_following_redirects(URI(url))
    unless response.is_a?(Net::HTTPSuccess)
      cover_log("page fetch #{url.to_s[0, 80]} -> HTTP #{response&.code || "error"}")
      return nil
    end
    return nil unless /html|text/i.match?(response["content-type"].to_s)

    response.body.to_s[0, 2_000_000]
  end

  def http_get_json(uri, retries: 1)
    response = http_get_following_redirects(uri)

    # Wikimedia rate-limits bursts; one polite retry after a pause
    if response&.code.to_i == 429 && retries.positive?
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
    response = http_get_following_redirects(URI(url))
    return nil unless response.is_a?(Net::HTTPSuccess)

    content_type = response["content-type"].to_s
    return nil unless content_type.start_with?("image/")

    size = response["content-length"] ? response["content-length"].to_i : response.body.bytesize
    { size: size, content_type: content_type }
  end

  # GET with manual redirect following — Net::HTTP does not follow redirects,
  # and Open Library's cover endpoints 302 to archive.org while work pages 301
  # to their canonical path. Returns the final Net::HTTPResponse, or nil on a
  # transport error (which is logged).
  def http_get_following_redirects(uri, limit: 4)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = WIKIMEDIA_USER_AGENT

    limit.times do
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: VERIFY_OPEN_TIMEOUT, read_timeout: VERIFY_READ_TIMEOUT) { |http| http.request(request) }
      return response unless response.is_a?(Net::HTTPRedirection)

      location = response["location"].to_s
      cover_log("redirect (#{response.code}) #{uri.to_s[0, 70]} -> #{location[0, 70]}")
      uri = URI.join(uri, location)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = WIKIMEDIA_USER_AGENT
    end
    cover_log("redirect limit (#{limit}) reached at #{uri.to_s[0, 80]}")
    nil
  rescue => e
    Rails.logger.warn("BookCoverImprover request failed for #{uri}: #{e.message}")
    nil
  end
end

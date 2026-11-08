# frozen_string_literal: true

require "net/http"
require "uri"

# Improves a Book's cover image using the Otari gateway with web search.
#
# The model (with the otari_web_search tool) proposes candidate cover-image
# URLs for the book. Nothing the model returns is trusted: every candidate is
# verified in Ruby (must load, must be an image, must meet the minimum byte
# size, and must beat the current cover's size) before it can replace
# book.cover_image.
class BookCoverImprover
  Result = Struct.new(:improved, :old_cover, :new_cover, :reason, keyword_init: true)

  DEFAULT_MODEL = "openai:gpt-oss-120b"
  MIN_IMAGE_BYTES = 15_000       # thumbnails are typically < 15 KiB
  MAX_IMAGE_BYTES = 10_000_000
  VERIFY_OPEN_TIMEOUT = 5
  VERIFY_READ_TIMEOUT = 10

  def initialize(book:)
    @book = book
  end

  def improve!(model: nil)
    model ||= ENV.fetch("OTARI_MODEL", DEFAULT_MODEL)
    current_bytes = probe_image(@book.cover_image)&.fetch(:size, nil)
    candidates = fetch_candidates(model)

    best = candidates.filter_map do |url|
      next if url == @book.cover_image
      probe = probe_image(url)
      next if probe.nil?
      next if probe[:size] < MIN_IMAGE_BYTES || probe[:size] > MAX_IMAGE_BYTES
      next if current_bytes && probe[:size] <= current_bytes

      { url: url, size: probe[:size] }
    end.max_by { |candidate| candidate[:size] }

    if best
      audit = @book.enrichment || {}
      audit["cover"] = {
        "old_cover" => @book.cover_image,
        "new_cover" => best[:url],
        "old_size_bytes" => current_bytes,
        "new_size_bytes" => best[:size],
        "improved_at" => Time.current.iso8601
      }
      @book.update!(cover_image: best[:url], enrichment: audit)
      Result.new(improved: true, old_cover: audit["cover"]["old_cover"], new_cover: best[:url], reason: "larger verified image found")
    else
      Result.new(improved: false, old_cover: @book.cover_image, new_cover: nil, reason: candidates.any? ? "no candidate verified larger than current" : "no candidates returned")
    end
  rescue OtariClient::Error => e
    Result.new(improved: false, old_cover: @book.cover_image, new_cover: nil, reason: "gateway error: #{e.message}")
  end

  private

  # Asks the model to use web search to find a high-resolution official cover.
  # Returns candidate URLs extracted from the answer. Prompt restricts to image
  # URLs; Ruby-side verification remains the gate.
  def fetch_candidates(model)
    response = OtariClient.new.chat(
      model: model,
      tools: [ { type: "otari_web_search", max_uses: 3 } ],
      temperature: 0.0,
      messages: [
        { role: "system", content: <<~PROMPT },
          You find high-resolution book cover images. Only return URLs that point directly to an image file
          (ending .jpg, .jpeg or .png, or served with an image content type). Prefer official publisher or
          reputable library sources. Answer with a short list of candidate URLs, one per line, and nothing else.
          If you cannot find a clearly better image than the current one, return no URLs at all.
        PROMPT
        { role: "user", content: <<~PROMPT }
          Book: "#{@book.title}" by #{@book.author}
          Current cover: #{@book.cover_image || "none"}
          Find 1-3 candidate URLs for a higher-resolution version of this book's cover.
        PROMPT
      ]
    )

    content = response.dig("choices", 0, "message", "content").to_s
    URI.extract(content, %w[http https]).map { |url| URI(url).to_s }
  end

  # Loads the first bytes of the URL and reports size/content type. Returns
  # nil unless it is verifiably an image.
  def probe_image(url)
    return nil if url.blank?

    uri = URI(url)
    request = Net::HTTP::Get.new(uri)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: VERIFY_OPEN_TIMEOUT, read_timeout: VERIFY_READ_TIMEOUT) do |http|
      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      content_type = response["content-type"].to_s
      return nil unless content_type.start_with?("image/")
      return nil if response["content-length"].nil? && response.body.nil?

      bytes = response["content-length"] ? response["content-length"].to_i : response.body.bytesize
      { size: bytes, content_type: content_type }
    end
  rescue => e
    Rails.logger.warn("BookCoverImprover probe failed for #{url}: #{e.message}")
    nil
  end
end

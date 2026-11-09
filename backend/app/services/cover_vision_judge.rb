# frozen_string_literal: true

require "uri"
require "net/http"
require "json"

# Visually judges a Book's stored cover image with a vision-capable model
# through the Otari gateway:
#
#   1. The current cover bytes are downloaded and uploaded to the Files API.
#   2. A vision-capable open-weight model sees the image and reports:
#      whether it is a real book cover, whether it depicts this specific book,
#      and whether its quality (resolution) looks high or low.
#
# The verdict is the "old cover" input to the enrichment judgment; the gateway
# flow respects the model's "Attachments" capability (the OpenAI-style inline
# image_url parts with a remote URL are dropped by the provider).
class CoverVisionJudge
  Result = Struct.new(:verdict, :quality, :matches_book, :detail, keyword_init: true)

  # Verified: open-weight vision model available on the hosted gateway
  # (https://api.otari.ai/api/v1/models; "Image, Text -> Text", attachments supported)
  VISION_MODEL = "deepseek/deepseek-v4.1-flash-1017"
  JUDGMENTS = %w[real_cover placeholder not_cover unknown].freeze
  QUALITIES = %w[high_res low_res unknown].freeze

  MAX_UPLOAD_BYTES = 10_000_000

  def initialize(book:, client: OtariClient.new)
    @book = book
    @client = client
  end

  def judge!
    return not_assessed("no cover stored") if @book.cover_image.blank?

    file_id = upload_current_cover
    return not_assessed("cover could not be uploaded for analysis") if file_id.nil?

    prompt = <<~PROMPT
      Look at this image. Answer exactly in JSON:
      {"is_real_book_cover": true|false, "depicts_title_match": true|false, "quality": "high_res"|"low_res",
       "notes": "one short line describing what you see"}
      Context: the book is "#{@book.title}" by #{@book.author}.
    PROMPT

    response = @client.chat(
      model: VISION_MODEL,
      messages: [
        { role: "user", content: [
          { type: "text", text: prompt },
          { type: "file", file: { file_id: file_id } }
        ] }
      ],
      max_tokens: 200
    )

    content = response.dig("choices", 0, "message", "content").to_s
    data = parse_verdict(content)

    verdict = data["is_real_book_cover"] === true ? "real_cover" : (data["is_real_book_cover"] === false ? "not_cover" : "unknown")
    quality = data["quality"] == "high_res" ? "high_res" : "low_res"
    matches = data["depicts_title_match"] === true

    Result.new(verdict: verdict, quality: quality, matches_book: matches, detail: data["notes"].to_s)
  rescue OtariClient::Error, JSON::ParserError => e
    Rails.logger.warn("CoverVisionJudge failed: #{e.message}")
    not_assessed("vision judgment failed: #{e.message.split("\n").first}")
  end

  private

  def not_assessed(reason)
    Result.new(verdict: "unknown", quality: "unknown", matches_book: false, detail: reason)
  end

  # Pulls the first JSON object out of the model's answer; empty verdicts when
  # it produced none.
  def parse_verdict(content)
    blob = content[/\{.*\}/m] || "{}"
    JSON.parse(blob)
  rescue JSON::ParserError
    {}
  end

  # Downloads the stored cover URL and uploads it. Returns nil when anything
  # fails (the judge degrades to "unassessed" rather than blocking enrichment).
  def upload_current_cover
    uri = URI(@book.cover_image)
    bytes = content_type = nil
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) do |http|
      request = Net::HTTP::Get.new(uri)
      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)
      return nil unless response["content-type"].to_s.start_with?("image/")

      content_type = response["content-type"].to_s.split(";").first
      bytes = response.body
    end

    return nil if bytes.nil? || bytes.bytesize > MAX_UPLOAD_BYTES

    filename = File.basename(URI.parse(@book.cover_image).path.to_s)
    filename = filename.blank? || filename.include?("?") ? "cover.jpg" : filename.tr("?", "_")
    @client.upload_file(data: bytes, filename: filename, content_type: content_type || "image/jpeg")
  end
end

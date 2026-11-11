# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Thin client for the Otari AI gateway (https://otari.ai).
#
# Otari exposes an OpenAI-compatible HTTP API. This client posts to
# {base_url}/chat/completions with a bearer virtual key and returns the
# parsed response body.
#
# Configuration (required):
#   OTARI_BASE_URL - gateway endpoint up to and including the version, e.g. "https://api.otari.ai/v1"
#   OTARI_API_KEY  - virtual key issued by the Otari dashboard (starts with "tk-")
class OtariClient
  Error = Class.new(StandardError)
  ConfigurationError = Class.new(Error)
  RequestError = Class.new(Error)
  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 60
  TOOL_LOOP_READ_TIMEOUT = 180
  FILES_UPLOAD_READ_TIMEOUT = 120

  # Whether the gateway is fully configured for outbound calls. The single
  # source of truth for "is Otari set up" — controllers use it for instant UX
  # feedback, jobs use it as a cheap pre-flight before doing work.
  def self.configured?(base_url: ENV["OTARI_BASE_URL"], api_key: ENV["OTARI_API_KEY"])
    base_url.to_s.strip.present? && api_key.to_s.strip.present?
  end

  def configured?
    self.class.configured?(base_url: @base_url, api_key: @api_key)
  end

  def initialize(base_url: ENV["OTARI_BASE_URL"], api_key: ENV["OTARI_API_KEY"])
    @base_url = base_url.to_s.chomp("/")
    @api_key = api_key
  end

  # Uploads an image/document to the Otari Files API (multipart) and returns
  # the file id ("<file-...>") usable as { type: "file", file: { file_id } } in
  # chat messages. Vision-capable models receive the image natively.
  def upload_file(data:, filename:, content_type:)
    ensure_configured!
    uri = URI("#{@base_url}/files")

    boundary = "otarirb#{rand(1e9)}"
    pre = "\r\n--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"purpose\"\r\n\r\nuser_data\r\n" \
      "--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n" \
      "Content-Type: #{content_type}\r\n\r\n"
    body = pre + data + "\r\n--#{boundary}--\r\n"

    request = Net::HTTP::Post.new(uri)
    request["Otari-Key"] = @api_key
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    request["Content-Length"] = body.bytesize
    request.body = body

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: FILES_UPLOAD_READ_TIMEOUT) { |http| http.request(request) }

    unless response.is_a?(Net::HTTPSuccess)
      raise RequestError, "file upload failed: status=#{response.code} body=#{response.body.to_s[0, 300]}"
    end

    JSON.parse(response.body)["id"].tap do |file_id|
      raise RequestError, "file upload succeeded but no id returned" if file_id.blank?
    end
  rescue RequestError, ConfigurationError
    raise
  rescue => e
    Rails.logger.error("OtariClient file upload failed: #{e.class} #{e.message}")
    raise RequestError, "unexpected file upload error: #{e.class} #{e.message}"
  end

  # Performs a chat completion and returns the full parsed response body hash.
  # See https://platform.openai.com/docs/api-reference/chat for the shape.
  # `tools` takes Otari built-in tool declarations, e.g.
  #   [{ "type" => "otari_web_search", "max_uses" => 3 }]
  # `mcp_server_ids` takes ids of MCP servers registered in the Otari
  # workspace (dashboard: Tools -> MCP servers), e.g. ["books"]. Sent as a
  # top-level request field, never inside `tools`; composes freely with
  # built-in tools.
  # Chat completion with Otari's built-in tools (gateway-run search / code
  # execution) and an optional read timeout — the tool + sandbox loop can
  # legitimately outlast a plain completion.
  def chat(model:, messages:, response_format: nil, temperature: nil, max_tokens: nil,
           tools: nil, mcp_server_ids: nil, read_timeout: nil)
    body = { model: model, messages: messages }
    body[:response_format] = response_format if response_format
    body[:temperature] = temperature if temperature
    body[:max_tokens] = max_tokens if max_tokens
    body[:tools] = tools if tools
    body[:mcp_server_ids] = mcp_server_ids if mcp_server_ids

    post("/chat/completions", body, read_timeout: read_timeout || ((tools.present? || mcp_server_ids.present?) ? TOOL_LOOP_READ_TIMEOUT : DEFAULT_READ_TIMEOUT))
  end

  # Runs Python directly in the gateway's sandbox — no model involved
  # (POST /api/v1/code/execute). Returns the parsed result body
  # (stdout, stderr, return_code, files with file_id + filename).
  def execute_code(code, timeout_seconds: 60)
    post("/code/execute", { code: code, timeout_seconds: timeout_seconds }, read_timeout: timeout_seconds + 30)
  end

  # Downloads a file produced/uploaded through the Files API. Returns the
  # raw bytes.
  def download_file(file_id)
    ensure_configured!
    uri = URI("#{@base_url}/files/#{file_id}/content")

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT) { |http| http.request(request) }

    unless response.is_a?(Net::HTTPSuccess)
      raise RequestError, "file download failed: status=#{response.code} body=#{response.body.to_s[0, 300]}"
    end

    response.body
  end

  # Chat completion with OpenAI structured output. Returns the parsed JSON
  # object the model produced (raises RequestError if it is not an object).
  def chat_structured(model:, messages:, name:, schema:, temperature: nil, read_timeout: nil)
    response = chat(
      model: model,
      messages: messages,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: name,
          strict: true,
          schema: schema
        }
      },
      temperature: temperature,
      read_timeout: read_timeout
    )

    content = response.dig("choices", 0, "message", "content")
    raise RequestError, "empty completion content" if content.blank?

    JSON.parse(content)
  rescue JSON::ParserError => e
    raise RequestError, "invalid JSON in structured completion: #{e.message}"
  end

  private

  def post(path, body, read_timeout: DEFAULT_READ_TIMEOUT)
    ensure_configured!
    uri = URI("#{@base_url}#{path}")

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)

    response = Net::HTTP.start(
      uri.hostname, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: DEFAULT_OPEN_TIMEOUT,
      read_timeout: read_timeout
    ) { |http| http.request(request) }

    unless response.is_a?(Net::HTTPSuccess)
      raise RequestError, "status=#{response.code} body=#{response.body.to_s[0, 500]}"
    end

    JSON.parse(response.body)
  rescue RequestError, ConfigurationError
    raise
  rescue => e
    Rails.logger.error("OtariClient request failed: #{e.class} #{e.message}")
    raise RequestError, "unexpected error: #{e.class} #{e.message}"
  end

  def ensure_configured!
    if @base_url.blank? || @api_key.blank?
      raise ConfigurationError,
        "Otari is not configured. Set OTARI_BASE_URL and OTARI_API_KEY."
    end
  end
end

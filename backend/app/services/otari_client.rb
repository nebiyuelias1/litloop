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

  def initialize(base_url: ENV["OTARI_BASE_URL"], api_key: ENV["OTARI_API_KEY"])
    @base_url = base_url.to_s.chomp("/")
    @api_key = api_key
  end

  # Performs a chat completion and returns the full parsed response body hash.
  # See https://platform.openai.com/docs/api-reference/chat for the shape.
  # `tools` takes Otari built-in tool declarations, e.g.
  #   [{ "type" => "otari_web_search", "max_uses" => 3 }]
  def chat(model:, messages:, response_format: nil, temperature: nil, max_tokens: nil, tools: nil)
    body = { model: model, messages: messages }
    body[:response_format] = response_format if response_format
    body[:temperature] = temperature if temperature
    body[:max_tokens] = max_tokens if max_tokens
    body[:tools] = tools if tools

    post("/chat/completions", body)
  end

  # Chat completion with OpenAI structured output. Returns the parsed JSON
  # object the model produced (raises RequestError if it is not an object).
  def chat_structured(model:, messages:, name:, schema:, temperature: nil)
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
      temperature: temperature
    )

    content = response.dig("choices", 0, "message", "content")
    raise RequestError, "empty completion content" if content.blank?

    JSON.parse(content)
  rescue JSON::ParserError => e
    raise RequestError, "invalid JSON in structured completion: #{e.message}"
  end

  private

  def post(path, body)
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
      read_timeout: DEFAULT_READ_TIMEOUT
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

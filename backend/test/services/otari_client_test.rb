require "test_helper"

class OtariClientTest < ActiveSupport::TestCase
  class FakeResponse
    attr_reader :body, :code

    def initialize(body = "{}", success: true)
      @body = body
      @code = success ? "200" : "500"
      @success = success
    end

    def is_a?(klass)
      return @success if klass == Net::HTTPSuccess

      super
    end
  end

  setup do
    ENV["OTARI_BASE_URL"] = "https://gateway.test/v1"
    ENV["OTARI_API_KEY"] = "tk-test"
  end

  teardown do
    ENV.delete("OTARI_BASE_URL")
    ENV.delete("OTARI_API_KEY")
  end

  # Runs the block with Net::HTTP faked to return `response`; returns the
  # captured request object afterwards.
  def stub_http(response)
    response = FakeResponse.new(response) unless response.is_a?(FakeResponse)
    fake_http = Object.new
    captured = nil
    fake_http.define_singleton_method(:request) do |req|
      captured = req
      response
    end

    Net::HTTP.stub(:start, ->(*_args, **_kwargs, &blk) { blk.call(fake_http) }) do
      yield
    end

    captured
  end

  test "chat returns parsed response body" do
    body = { "choices" => [ { "message" => { "role" => "assistant", "content" => "hello" } } ] }.to_json

    result = nil
    captured = stub_http(body) do
      client = OtariClient.new
      result = client.chat(model: "openai/gpt-oss-120b", messages: [ { role: "user", content: "hi" } ])
    end

    assert_equal "hello", result.dig("choices", 0, "message", "content")
    assert_equal "Bearer tk-test", captured["Authorization"]
    assert_equal "application/json", captured["Content-Type"]
    payload = JSON.parse(captured.body)
    assert_equal "openai/gpt-oss-120b", payload["model"]
    assert_equal [ { "role" => "user", "content" => "hi" } ], payload["messages"]
  end

  test "chat_structured sends json_schema response_format and parses content" do
    schema = {
      type: "object",
      properties: { tags: { type: "array", items: { type: "string" } } },
      required: [ "tags" ],
      additionalProperties: false
    }
    body = { "choices" => [ { "message" => { "content" => '{"tags":["fiction"]}' } } ] }.to_json

    result = nil
    captured = stub_http(body) do
      client = OtariClient.new
      result = client.chat_structured(
        model: "openai/gpt-oss-120b",
        messages: [ { role: "user", content: "tag this" } ],
        name: "book_tags",
        schema: schema
      )
    end

    assert_equal [ "fiction" ], result["tags"]
    rf = JSON.parse(captured.body)["response_format"]
    assert_equal "json_schema", rf["type"]
    assert_equal true, rf["json_schema"]["strict"]
    assert_equal "book_tags", rf["json_schema"]["name"]
  end

  test "chat sends mcp_server_ids as top-level request field" do
    body = { "choices" => [ { "message" => { "role" => "assistant", "content" => "found books" } } ] }.to_json

    result = nil
    captured = stub_http(body) do
      client = OtariClient.new
      result = client.chat(
        model: "openai/gpt-oss-120b",
        messages: [ { role: "user", content: "find books about cryptography" } ],
        mcp_server_ids: [ "books" ]
      )
    end

    assert_equal "found books", result.dig("choices", 0, "message", "content")
    payload = JSON.parse(captured.body)
    assert_equal [ "books" ], payload["mcp_server_ids"]
    # MCP servers are a top-level field, never a tools entry
    assert_nil payload["tools"]
  end

  test "raises ConfigurationError without credentials" do
    ENV.delete("OTARI_BASE_URL")
    ENV.delete("OTARI_API_KEY")

    stub_http("{}") do
      assert_raises OtariClient::ConfigurationError do
        OtariClient.new.chat(model: "m", messages: [])
      end
    end
  end

  test "raises RequestError on non-success response" do
    stub_http(FakeResponse.new("boom", success: false)) do
      error = assert_raises(OtariClient::RequestError) do
        OtariClient.new.chat(model: "m", messages: [])
      end
      assert_match(/status=/, error.message)
    end
  end

  test "chat_structured raises RequestError on invalid JSON content" do
    body = { "choices" => [ { "message" => { "content" => "not json {" } } ] }.to_json

    stub_http(body) do
      assert_raises(OtariClient::RequestError) do
        OtariClient.new.chat_structured(
          model: "m", messages: [], name: "x", schema: { type: "object" }
        )
      end
    end
  end
end

require "test_helper"

class BookCoverImproverTest < ActiveSupport::TestCase
  def probe_result(size)
    { size: size, content_type: "image/jpeg" }
  end

  def improver_with_candidates(book, candidate_urls, probes = {})
    improver = BookCoverImprover.new(book: book)
    client = Object.new
    client.define_singleton_method(:chat) do |**_kwargs|
      { "choices" => [ { "message" => { "content" => candidate_urls.join("\n") } } ] }
    end
    OtariClient.stub(:new, client) do
      improver.stub(:probe_image, ->(url) { probes[url] || probe_result(1_000) }) do
        yield improver
      end
    end
  end

  test "replaces cover when a larger verified candidate exists" do
    book = Book.create!(title: "Things Fall Apart", author: "Chinua Achebe", cover_image: "https://covers.example/tfa-small.jpg")

    result = improver_with_candidates(book, [ "https://better.example/tfa.jpg" ], { "https://better.example/tfa.jpg" => probe_result(200_000) }) do |improver|
      improver.improve!
    end

    assert result.improved
    assert_equal "https://better.example/tfa.jpg", book.reload.cover_image
    assert_equal 200_000, book.enrichment["cover"]["new_size_bytes"]
    assert_equal "https://covers.example/tfa-small.jpg", book.enrichment["cover"]["old_cover"]
  end

  test "keeps cover when candidates fail verification (dead URL, too small, not larger)" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://covers.example/ok.jpg")

    probes = {
      "https://dead.example/x.jpg" => nil,                                  # fails to load
      "https://tiny.example/x.jpg" => probe_result(1_000),                  # below MIN_IMAGE_BYTES
      "https://same-size.example/x.jpg" => probe_result(50_000)             # not larger than current
    }
    current = probe_result(50_000)

    result = improver_with_candidates(book, probes.keys, probes.merge("https://covers.example/ok.jpg" => current)) do |improver|
      improver.improve!
    end

    assert_not result.improved
    assert_equal "https://covers.example/ok.jpg", book.reload.cover_image
    assert book.enrichment.blank?
  end

  test "keeps cover when model returns no candidates" do
    book = Book.create!(title: "Test Book", author: "Test Author")

    result = improver_with_candidates(book, []) do |improver|
      improver.improve!
    end

    assert_not result.improved
    assert_equal "no candidates returned", result.reason
  end

  test "cover audit survives when book already has enrichment" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")
    book.update!(enrichment: { "confidence" => "high" })

    improver_with_candidates(book, [ "https://b.example/new.jpg" ], { "https://b.example/new.jpg" => probe_result(300_000) }) do |improver|
      improver.improve!
    end

    audit = book.reload.enrichment
    assert_equal "high", audit["confidence"]
    assert audit["cover"].present?
  end

  test "gateway errors are swallowed into a kept result" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| raise OtariClient::RequestError, "boom" }
    OtariClient.stub(:new, client) do
      result = BookCoverImprover.new(book: book).improve!
      assert_not result.improved
      assert_match(/gateway error/, result.reason)
    end
    assert_equal "https://a.example/old.jpg", book.reload.cover_image
  end
end

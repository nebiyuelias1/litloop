require "test_helper"

class BookCoverImproverTest < ActiveSupport::TestCase
  def probe_result(size)
    { size: size, content_type: "image/jpeg" }
  end

  def stub_ai(payload)
    client = Object.new
    client.define_singleton_method(:chat_structured) { |**_kwargs| payload }
    OtariClient.stub(:new, client) do
      yield
    end
  end

  test "replaces a placeholder cover via Wikipedia pageimages" do
    book = Book.create!(title: "Things Fall Apart", author: "Chinua Achebe", cover_image: "https://images.unsplash.com/photo-1532012197267")

    improver = BookCoverImprover.new(book: book)
    improver.stub(:page_image_url, ->(_url) { "https://upload.wikimedia.org/tfa.jpg" }) do
      improver.stub(:probe_image, ->(_url) { probe_result(120_000) }) do
        stub_ai({ "wikipedia_page" => "https://en.wikipedia.org/wiki/Things_Fall_Apart", "commons_file_pages" => [] }) do
          @result = improver.improve!
        end
      end
    end

    assert @result.improved, "reason: #{@result.try(:reason)}"
    assert_equal "https://upload.wikimedia.org/tfa.jpg", book.reload.cover_image
    assert_equal "https://images.unsplash.com/photo-1532012197267", book.enrichment["cover"]["old_cover"]
  end

  test "replaces cover via commons file page" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://images.unsplash.com/old")

    improver = BookCoverImprover.new(book: book)
    improver.stub(:probe_image, ->(_url) { probe_result(90_000) }) do
      stub_ai({ "wikipedia_page" => "", "commons_file_pages" => [ "https://commons.wikimedia.org/wiki/File:Things_Fall_Apart_signed.jpg" ] }) do
        @result = improver.improve!
      end
    end

    assert @result.improved
    assert_match(/Special:FilePath\/Things_Fall_Apart_signed.jpg/, book.reload.cover_image)
  end

  test "falls back to deterministic title search when model returns no usable candidates" do
    book = Book.create!(title: "Some Rare Book", author: "Nobody", cover_image: "https://images.unsplash.com/old")

    improver = BookCoverImprover.new(book: book)
    improver.stub(:wikipedia_search_title, -> { "Some Rare Book" }) do
      improver.stub(:page_image_url, ->(_url) { "https://upload.wikimedia.org/fallback.jpg" }) do
        improver.stub(:probe_image, ->(_url) { probe_result(50_000) }) do
          stub_ai({ "wikipedia_page" => "", "commons_file_pages" => [] }) do
            @result = improver.improve!
          end
        end
      end
    end

    assert @result.improved
    assert_equal "https://upload.wikimedia.org/fallback.jpg", book.reload.cover_image
  end

  test "keeps cover when nothing verifies" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")

    improver = BookCoverImprover.new(book: book)
    improver.stub(:page_image_url, ->(_url) { "https://upload.example/dead.jpg" }) do
      improver.stub(:probe_image, ->(_url) { nil }) do
        stub_ai({ "wikipedia_page" => "https://en.wikipedia.org/wiki/Test_Book", "commons_file_pages" => [] }) do
          @result = improver.improve!
        end
      end
    end

    assert_not @result.improved
    assert_equal "https://a.example/old.jpg", book.reload.cover_image
    assert_equal "no candidate verified as a usable image", @result.reason
  end

  test "keeps existing cover audit when book already has enrichment" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")
    book.update!(enrichment: { "confidence" => "high" })

    improver = BookCoverImprover.new(book: book)
    improver.stub(:page_image_url, ->(_url) { "https://b.example/new.jpg" }) do
      improver.stub(:probe_image, ->(_url) { probe_result(300_000) }) do
        stub_ai({ "wikipedia_page" => "https://en.wikipedia.org/wiki/Test_Book", "commons_file_pages" => [] }) do
          improver.improve!
        end
      end
    end

    audit = book.reload.enrichment
    assert_equal "high", audit["confidence"]
    assert audit["cover"].present?
  end

  test "gateway errors are swallowed into a kept result" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")
    client = Object.new
    client.define_singleton_method(:chat_structured) { |**_kwargs| raise OtariClient::RequestError, "boom" }
    OtariClient.stub(:new, client) do
      result = BookCoverImprover.new(book: book).improve!
      assert_not result.improved
    end
    assert_equal "https://a.example/old.jpg", book.reload.cover_image
  end

  test "skips its own fallback search in test env" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")

    improver = BookCoverImprover.new(book: book)
    stub_ai({ "wikipedia_page" => "", "commons_file_pages" => [] }) do
      result = improver.improve!
      assert_not result.improved
      assert_equal "no candidates", result.reason
    end
  end
end

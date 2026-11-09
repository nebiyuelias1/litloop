require "test_helper"

class BookCoverImproverTest < ActiveSupport::TestCase
  # Canonical stubbing pattern for improver tests:
  #   improver = BookCoverImprover.new(book: book)
  #   improver.stub(:method, handler) do
  #     improver.stub(:other, handler2) do
  #       OtariClient.stub(:new, fake_client) do
  #         CoverVisionJudge.stub(:new, fake_vision) do
  #           improver.improve!
  #         end
  #       end
  #     end
  #   end
  VISION_OK = -> { nil }

  def fake_vision(verdict: "real_cover", quality: "high_res", matches: true)
    judge = Object.new
    judge.define_singleton_method(:inspect_bytes) do |**_kw|
      CoverVisionJudge::Result.new(verdict: verdict, quality: quality, matches_book: matches, detail: "stubbed")
    end
    judge
  end

  def fake_client(payload)
    client = Object.new
    client.define_singleton_method(:chat_structured) { |**_kw| payload }
    client
  end

  def fetch_result(size)
    { size: size, content_type: "image/jpeg", bytes: "x" * (size || 1) }
  end

  test "replaces a placeholder cover via Wikipedia pageimages" do
    book = Book.create!(title: "Things Fall Apart", author: "Chinua Achebe", cover_image: "https://images.unsplash.com/photo-1532012197267")
    improver = BookCoverImprover.new(book: book)

    CoverVisionJudge.stub(:new, fake_vision) do
      improver.stub(:page_image_url, ->(_u) { "https://upload.wikimedia.org/tfa.jpg" }) do
        improver.stub(:fetch_image_bytes, ->(_u) { fetch_result(120_000) }) do
          OtariClient.stub(:new, fake_client({ "wikipedia_page" => "https://en.wikipedia.org/wiki/Things_Fall_Apart", "commons_file_pages" => [] })) do
            result = improver.improve!

            assert result.improved, "reason: #{result.reason}"
            assert_equal "https://upload.wikimedia.org/tfa.jpg", book.reload.cover_image
            assert_equal "https://images.unsplash.com/photo-1532012197267", book.enrichment["cover"]["old_cover"]
            assert_includes book.enrichment["cover"]["vision_verdict"], "real_cover"
          end
        end
      end
    end
  end

  test "cover judged not the real book gets rejected and cover kept" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://images.unsplash.com/old")
    improver = BookCoverImprover.new(book: book)

    CoverVisionJudge.stub(:new, fake_vision(verdict: "not_cover", matches: false)) do
      improver.stub(:page_image_url, ->(_u) { "https://upload.wikimedia.org/wrong.jpg" }) do
        improver.stub(:fetch_image_bytes, ->(_u) { fetch_result(300_000) }) do
          OtariClient.stub(:new, fake_client({ "wikipedia_page" => "https://en.wikipedia.org/wiki/Test_Book", "commons_file_pages" => [] })) do
            result = improver.improve!

            assert_not result.improved
            assert_equal "https://images.unsplash.com/old", book.reload.cover_image
          end
        end
      end
    end
  end

  test "replaces cover via commons file page" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://images.unsplash.com/old")
    improver = BookCoverImprover.new(book: book)

    CoverVisionJudge.stub(:new, fake_vision(quality: "low_res")) do
      improver.stub(:commons_image_url, ->(_fp) { "https://upload.wikimedia.org/commons/signed.jpg" }) do
        improver.stub(:fetch_image_bytes, ->(_u) { fetch_result(90_000) }) do
          OtariClient.stub(:new, fake_client({ "wikipedia_page" => "", "commons_file_pages" => [ "https://commons.wikimedia.org/wiki/File:Things_Fall_Apart_signed.jpg" ] })) do
            result = improver.improve!

            assert result.improved
            assert_equal "https://upload.wikimedia.org/commons/signed.jpg", book.reload.cover_image
          end
        end
      end
    end
  end

  test "falls back to deterministic title search when model returns no usable candidates" do
    book = Book.create!(title: "Some Rare Book", author: "Nobody", cover_image: "https://images.unsplash.com/old")
    improver = BookCoverImprover.new(book: book)

    CoverVisionJudge.stub(:new, fake_vision) do
      improver.stub(:wikipedia_search_title, -> { "Some Rare Book" }) do
        improver.stub(:page_image_url, ->(_u) { "https://upload.wikimedia.org/fallback.jpg" }) do
          improver.stub(:fetch_image_bytes, ->(_u) { fetch_result(50_000) }) do
            OtariClient.stub(:new, fake_client({ "wikipedia_page" => "", "commons_file_pages" => [] })) do
              result = improver.improve!

              assert result.improved
              assert_equal "https://upload.wikimedia.org/fallback.jpg", book.reload.cover_image
            end
          end
        end
      end
    end
  end

  test "keeps cover when nothing verifies" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")
    improver = BookCoverImprover.new(book: book)

    CoverVisionJudge.stub(:new, fake_vision) do
      improver.stub(:page_image_url, ->(_u) { "https://upload.example/dead.jpg" }) do
        improver.stub(:fetch_image_bytes, ->(_u) { nil }) do
          OtariClient.stub(:new, fake_client({ "wikipedia_page" => "https://en.wikipedia.org/wiki/Test_Book", "commons_file_pages" => [] })) do
            result = improver.improve!

            assert_not result.improved
            assert_equal "https://a.example/old.jpg", book.reload.cover_image
            assert_equal "no candidate verified as a usable image", result.reason
          end
        end
      end
    end
  end

  test "cover audit survives when book already has enrichment" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")
    book.update!(enrichment: { "confidence" => "high" })
    improver = BookCoverImprover.new(book: book)

    CoverVisionJudge.stub(:new, fake_vision) do
      improver.stub(:page_image_url, ->(_u) { "https://b.example/new.jpg" }) do
        improver.stub(:fetch_image_bytes, ->(_u) { fetch_result(300_000) }) do
          OtariClient.stub(:new, fake_client({ "wikipedia_page" => "https://en.wikipedia.org/wiki/Test_Book", "commons_file_pages" => [] })) do
            result = improver.improve!

            audit = book.reload.enrichment
            assert_equal "high", audit["confidence"]
            assert audit["cover"].present?
            assert result.improved
          end
        end
      end
    end
  end

  test "judge-cited urls are added as candidates (direct guess tier)" do
    book = Book.create!(title: "Yeteqolefetebet Kulf", author: "ዶ/ር", cover_image: "https://images.unsplash.com/old")
    improver = BookCoverImprover.new(book: book, cited_cover_url: "https://publisher.example/amharic-covers/real-cover.jpg")

    CoverVisionJudge.stub(:new, fake_vision) do
      improver.stub(:http_get_text, lambda { |_u|
        '<meta property="og:image" content="https://publisher.example/amharic-covers/real-cover.jpg">'
      }) do
        improver.stub(:fetch_image_bytes, lambda { |u|
          u.include?("real-cover") ? fetch_result(80_000) : nil
        }) do
          improver.stub(:wikipedia_search_title, -> { nil }) do
            OtariClient.stub(:new, fake_client({ "wikipedia_page" => "", "commons_file_pages" => [] })) do
              result = improver.improve!

              assert result.improved, "reason: #{result.reason}"
              assert_equal "https://publisher.example/amharic-covers/real-cover.jpg", book.reload.cover_image
            end
          end
        end
      end
    end
  end

  test "vision-rejected candidates are skipped in tier order" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://images.unsplash.com/old")
    improver = BookCoverImprover.new(book: book)

    CoverVisionJudge.stub(:new, fake_vision(verdict: "not_cover", matches: false)) do
      improver.stub(:page_image_url, ->(_u) { "https://upload.wikimedia.org/first.jpg" }) do
        improver.stub(:fetch_image_bytes, ->(u) { u.include?("first") ? fetch_result(40_000) : fetch_result(90_000) }) do
          OtariClient.stub(:new, fake_client({ "wikipedia_page" => "https://en.wikipedia.org/wiki/Test_Book", "commons_file_pages" => [] })) do
            result = improver.improve!

            assert_not result.improved
            assert_equal "https://images.unsplash.com/old", book.reload.cover_image
            assert_match(/no candidate verified as a usable image/, result.reason)
          end
        end
      end
    end
  end

  test "gateway errors are swallowed into a kept result" do
    book = Book.create!(title: "Test Book", author: "Test Author", cover_image: "https://a.example/old.jpg")
    improver = BookCoverImprover.new(book: book)

    CoverVisionJudge.stub(:new, fake_vision) do
      improver.stub(:page_image_url, ->(_u) { "https://b.example/never.jpg" }) do
        improver.stub(:fetch_image_bytes, ->(_u) { fetch_result(50_000) }) do
          erroring = Object.new
          erroring.define_singleton_method(:chat_structured) { |**_kw| raise OtariClient::RequestError, "boom" }
          erroring.define_singleton_method(:chat) { |**_kw| raise OtariClient::RequestError, "boom" }
          OtariClient.stub(:new, erroring) do
            result = improver.improve!

            assert_not result.improved
            assert result.reason.include?("no candidate") || result.reason.include?("no candidates")
          end
        end
      end
    end
  end
end

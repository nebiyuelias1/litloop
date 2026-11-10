require "test_helper"

class Admin::BooksEnrichControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one) # admin user fixture
    @book = Book.create!(title: "Things Fall Apart", author: "Chinua Achebe", description: "An existing description that is long enough to pass the gate.", language: "am")
    # dotenv autorestore puts .env values back before each test, so control the
    # env explicitly per test rather than relying on teardown of the previous one.
    ENV["OTARI_API_KEY"] = "tk-test"
    ENV["OTARI_BASE_URL"] = "https://gateway.test/v1"
  end

  test "requires admin login" do
    post enrich_admin_book_url(@book)
    assert_redirected_to new_user_session_path
  end

  test "redirects with alert when Otari is not configured" do
    ENV["OTARI_API_KEY"] = ""
    sign_in @user
    post enrich_admin_book_url(@book)
    assert_redirected_to admin_book_url(@book)
    assert_match(/not configured/, flash[:alert])
  end

  # The controller only queues now; the job runs the full flow inline in the
  # test to assert the end updates.
  test "queues enrichment; the job applies metadata updates" do
    sign_in @user

    ground = { facts: "1958 novel by Nigerian author Chinua Achebe. Source: https://en.wikipedia.org/wiki/Things_Fall_Apart", sources: [], cited_sources: [ "https://en.wikipedia.org/wiki/Things_Fall_Apart" ] }
    judgment = {
      "description" => { "action" => "keep_existing", "value" => "", "source_url" => "", "quote" => "" },
      "tags" => { "action" => "update", "values" => [ "fiction", "colonialism" ], "source_url" => "https://en.wikipedia.org/wiki/Things_Fall_Apart" },
      "country_of_origin" => { "action" => "update", "value" => "Nigeria", "source_url" => "https://en.wikipedia.org/wiki/Things_Fall_Apart", "quote" => "Nigerian author Chinua Achebe" },
      "cover" => { "judgment" => "missing", "reason" => "no cover stored", "source_url" => "" }
    }

    enricher = BookMetadataEnricher.new(book: @book)
    BookMetadataEnricher.stub(:new, ->(book:) { enricher }) do
      enricher.stub(:ground_with_web_search, ground) do
        enricher.stub(:judge, judgment) do
          post enrich_admin_book_url(@book)
        end
      end
    end

    assert_redirected_to admin_book_url(@book)
    assert_match(/queued|expected/, flash[:notice])

    # the queued job performs the actual work
    BookMetadataEnricher.stub(:new, ->(book:) { enricher }) do
      enricher.stub(:ground_with_web_search, ground) do
        enricher.stub(:judge, judgment) do
          improve_result = BookCoverImprover::Result.new(
            improved: false, old_cover: nil, new_cover: nil, reason: "no candidates"
          )
          improver = Object.new
          improver.define_singleton_method(:improve!) { attempted = false; improve_result }
          BookCoverImprover.stub(:new, improver) do
            BookEnrichmentJob.new.perform(@book.id)
          end
        end
      end
    end

    assert_equal "NG", @book.reload.country_of_origin
    assert_equal [ "colonialism", "fiction" ], @book.tags.order(:name).pluck(:name)
    assert_not_nil @book.enriched_at
  end

  test "queued job attempts the cover when the judgment calls for it" do
    ENV["OTARI_API_KEY"] = "tk-test"
    ENV["OTARI_BASE_URL"] = "https://gateway.test/v1"
    sign_in @user

    ground = { facts: "", sources: [], cited_sources: [] }
    judgment = {
      "description" => { "action" => "keep_existing", "value" => "", "source_url" => "", "quote" => "" },
      "tags" => { "action" => "keep_existing", "values" => [], "source_url" => "" },
      "country_of_origin" => { "action" => "keep_existing", "value" => "", "source_url" => "", "quote" => "" },
      "cover" => { "judgment" => "low_quality", "reason" => "placeholder unsplash image", "source_url" => "" }
    }
    enricher = BookMetadataEnricher.new(book: @book)
    attempted = false
    BookMetadataEnricher.stub(:new, ->(book:) { enricher }) do
      enricher.stub(:ground_with_web_search, ground) do
        enricher.stub(:judge, judgment) do
          improve_result = BookCoverImprover::Result.new(
            improved: true, old_cover: "https://old.example/a.jpg", new_cover: "https://upload.wikimedia.org/new.jpg",
            reason: "verified cover swap (vision: real_cover high_res)"
          )
          improver = Object.new
          improver.define_singleton_method(:improve!) do |**_kw|
            attempted = true
            improve_result
          end
          BookCoverImprover.stub(:new, improver) do
            BookEnrichmentJob.new.perform(@book.id)
          end
        end
      end
    end

    assert attempted, "the job should attempt the cover swap when the judgment calls for it"
  end

  test "enqueue failures surface as flash alert" do
    sign_in @user

    BookEnrichmentJob.stub(:perform_later, ->(_book_id) { raise OtariClient::RequestError, "boom" }) do
      post enrich_admin_book_url(@book)
    end

    assert_redirected_to admin_book_url(@book)
    assert_match(/Enrichment failed: boom/, flash[:alert])
  end
end

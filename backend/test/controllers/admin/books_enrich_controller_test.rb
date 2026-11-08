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

  test "enriches the book and shows result when configured" do
    ENV["OTARI_API_KEY"] = "tk-test"
    sign_in @user

    payload = {
      "description" => "A richly detailed rebuilt description that is comfortably longer than the minimum length gate we enforce.",
      "tags" => [ "fiction", "colonialism" ],
      "country_of_origin" => "Nigeria",
      "country_evidence" => "The blurb references Igbo warriors of Umuofia.",
      "confidence" => "high"
    }

    enricher = BookMetadataEnricher.new(book: @book)
    BookMetadataEnricher.stub(:new, ->(_book) { enricher }) do
      enricher.stub(:propose, payload) do
        post enrich_admin_book_url(@book)
      end
    end

    assert_redirected_to admin_book_url(@book)
    assert_match(/Enriched/, flash[:notice])
    assert_equal "NG", @book.reload.country_of_origin
    assert_equal [ "colonialism", "fiction" ], @book.tags.order(:name).pluck(:name)
    assert_not_nil @book.enriched_at
  end

  test "surfaces gateway errors as flash alert" do
    ENV["OTARI_API_KEY"] = "tk-test"
    sign_in @user

    enricher = BookMetadataEnricher.new(book: @book)
    BookMetadataEnricher.stub(:new, ->(_book) { enricher }) do
      enricher.stub(:propose, ->(*_args) { raise OtariClient::RequestError, "boom" }) do
        post enrich_admin_book_url(@book)
      end
    end

    assert_redirected_to admin_book_url(@book)
    assert_match(/Enrichment failed: boom/, flash[:alert])
  end
end

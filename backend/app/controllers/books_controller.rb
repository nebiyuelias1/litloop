class BooksController < ApplicationController
  before_action :set_book, only: %i[show cover]

  def index
    @tags = Tag.all.limit(10).order(:name)
    @active_tag = params[:tag]

    books = Book.order(created_at: :desc)
    if @active_tag.present?
      books = books.joins(:tags).where(tags: { name: @active_tag })
    end

    set_page_and_extract_portion_from books

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    @reviews = @book.reviews.includes(:user).where(parent_id: nil).order(created_at: :desc)
    @liked_review_ids = if current_user
      ReviewLike.where(user_id: current_user.id, review_id: @reviews).pluck(:review_id)
    else
      []
    end
    @upcoming_reads = @book.book_reads.includes(:book_club, :poll)
      .where(book_reads: { meetup_time: Time.current.. })
      .order(:meetup_time).limit(4)
    @past_reads_count = @book.book_reads.where(book_reads: { meetup_time: ...Time.current }).count
    @past_clubs = BookClub.where(
      id: @book.book_reads.where(book_reads: { meetup_time: ...Time.current }).select(:book_club_id)
    ).distinct.order(:name)
  end

  def new
    @book = Book.new
  end

  def create
    @book = Book.new(book_params)
    respond_to do |format|
      if @book.save
        enqueue_enrichment(@book)
        format.html { redirect_to @book }
        format.json { render json: @book, status: :created }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @book.errors, status: :unprocessable_content }
      end
    end
  end

  def search
    query = params[:query]
    @books = if query.present?
      local_results = Book.full_text_search(query).limit(10).to_a

      if local_results.size < 5
        lookup_results = BookLookup.find_many(title: query, author: query) || []
        external_books = lookup_results.map { |res| map_lookup_result_to_book(res) }

        combined = (local_results + external_books).uniq do |book|
          [ book.title.to_s.downcase.strip, book.author.to_s.downcase.strip ]
        end
        combined.first(10)
      else
        local_results
      end
    else
      []
    end

    respond_to do |format|
      format.html { render layout: false }
      format.json do
        render json: @books.map { |book|
          {
            id: book.id,
            title: book.title,
            author: book.author,
            cover_url: book.cover_image,
            persisted: book.persisted?,
            # Include attributes for unpersisted books so they can be saved
            attributes: book.persisted? ? {} : book.attributes.except("id", "created_at", "updated_at")
          }
        }
      end
    end
  end

  def cover
    if @book.cover_image.present?
      begin
        cache_key = [ "book_cover", @book.id, Digest::SHA1.hexdigest(@book.cover_image) ]
        data, content_type = Rails.cache.fetch(cache_key, expires_in: 24.hours) do
          require "open-uri"
          URI.open(@book.cover_image, open_timeout: 5, read_timeout: 5) do |f|
            [ f.read, f.content_type || "image/jpeg" ]
          end
        end

        send_data data, type: content_type, disposition: "inline"
      rescue => e
        Rails.logger.error "Failed to proxy book cover: #{e.message}"
        head :not_found
      end
    else
      head :not_found
    end
  end

  private

  def enqueue_enrichment(book)
    # The job is a no-op unless Otari is configured
    return if ENV["OTARI_API_KEY"].blank?
    return if book.enriched_at.present?

    BookEnrichmentJob.perform_later(book.id)
  rescue => e
    Rails.logger.warn("Failed to enqueue book enrichment: #{e.message}")
  end

  def map_lookup_result_to_book(result)
    Book.new(
      title: result.title,
      author: result.author.presence || "Unknown Author",
      cover_image: result.cover_image,
      isbn: result.isbn,
      publisher: result.publisher,
      published_at: result.published_at,
      description: result.description,
      page_count: result.page_count,
      language: result.language,
      source: result.source,
      source_url: result.source_url
    )
  end

  def set_book
    @book = Book.find(params[:id])
  end

  def book_params
    params.require(:book).permit(
      :title, :author, :description, :published_at, :language,
      :cover_image, :publisher, :isbn, :source, :source_url,
      :title_en, :title_romanized, :author_romanized, :page_count,
      :country_of_origin
    )
  end
end

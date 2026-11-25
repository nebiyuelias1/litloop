# The app's first-run tour (gather → choose → meet → reflect), ending at sign
# up or sign in. All examples are live data; slides cope with empty results.
class OnboardingController < ApplicationController
  # Languages for the book picks (the interface languages).
  PICK_LANGUAGES = %w[am en zh-CN zh-TW].freeze

  before_action :redirect_members_home

  def show
    remember_onboarded
    @cover_books = books_with_covers.limit(5)
    @clubs = BookClub.where(is_private: false).by_relevance.limit(3)
    @picks_by_language = picks_by_language
    @default_pick_language = default_pick_language
    @upcoming_read = upcoming_public_read
    @question = @upcoming_read && revealed_question_for(@upcoming_read)
    @review = latest_public_review
  end

  private

  def redirect_members_home
    redirect_to root_path if user_signed_in?
  end

  # Covered books, best rated first.
  def books_with_covers
    Book.where.not(cover_image: [ nil, "" ])
      .where.not("cover_image LIKE ?", "%no-cover.png")
      .left_joins(:ratings)
      .group(:id)
      .order(Arel.sql("AVG(ratings.score) DESC NULLS LAST, books.reviews_count DESC, books.id DESC"))
  end

  def upcoming_public_read
    BookRead.joins(:book_club)
      .where(book_clubs: { is_private: false })
      .where.not(book_id: nil)
      .where("meetup_time >= ?", Time.current)
      .includes(:book, :book_club)
      .order(:meetup_time)
      .first
  end

  def revealed_question_for(read)
    read.discussion_questions.revealed.order(:position).first
  end

  def latest_public_review
    Review.where(parent_id: nil)
      .where("LENGTH(body) BETWEEN 40 AND 400")
      .includes(:user, :book)
      .order(created_at: :desc)
      .first
  end

  def picks_by_language
    PICK_LANGUAGES.each_with_object({}) do |code, picks|
      books = books_with_covers.where(language: code).limit(6).to_a
      picks[code] = books if books.size >= 3
    end
  end

  def default_pick_language
    locale = I18n.locale.to_s
    candidates = [ locale, locale.split("-").first ]
    candidates.find { |code| @picks_by_language.key?(code) } || @picks_by_language.keys.first
  end
end

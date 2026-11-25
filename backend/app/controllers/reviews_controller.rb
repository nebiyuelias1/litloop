class ReviewsController < ApplicationController
  before_action :authenticate_user!

  def create
    @book = Book.find(params[:book_id])
    @review = @book.reviews.build(review_params)
    @review.user = current_user

    if @review.save
      redirect_to @book, notice: t("reviews.create.posted")
    else
      redirect_to @book, alert: t("reviews.create.failed", errors: @review.errors.full_messages.to_sentence)
    end
  end

  private

  def review_params
    params.require(:review).permit(:body)
  end
end

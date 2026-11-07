class DiscussionQuestionsController < ApplicationController
  prepend_before_action :store_discussion_question_draft, only: [ :create ]
  before_action :authenticate_user!
  before_action :set_book_club_and_read
  before_action :set_discussion_question, only: [ :update, :destroy ]
  before_action :authorize_discussion_question_permission, only: [ :create ]
  before_action :authorize_discussion_question_modification, only: [ :update, :destroy ]

  def create
    @discussion_question = @book_read.discussion_questions.build(discussion_question_params.merge(user: current_user))

    respond_to do |format|
      if @discussion_question.save
        session.delete(:discussion_question_draft)
        flash.now[:notice] = t("question_added")
        format.turbo_stream
        format.html { redirect_to book_club_book_read_path(@book_club, @book_read), notice: t("question_added") }
      else
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_discussion_question_form", partial: "discussion_questions/form", locals: { book_club: @book_club, book_read: @book_read, discussion_question: @discussion_question }), status: :unprocessable_content }
        format.html { redirect_to book_club_book_read_path(@book_club, @book_read), alert: t("question_blank") }
      end
    end
  end

  def update
    is_owner_or_admin = @book_club.owner == current_user || @book_club.book_club_members.exists?(user: current_user, role: :admin)

    update_params = if is_owner_or_admin
      discussion_question_update_params
    else
      discussion_question_params.merge(status: :draft)
    end

    if @discussion_question.update(update_params)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@discussion_question, partial: "discussion_questions/discussion_question", locals: { discussion_question: @discussion_question }) }
        format.html { redirect_to book_club_book_read_path(@book_club, @book_read), notice: t("question_updated") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@discussion_question, partial: "discussion_questions/discussion_question", locals: { discussion_question: @discussion_question, edit_mode: true }), status: :unprocessable_content }
        format.html { redirect_to book_club_book_read_path(@book_club, @book_read), alert: t("question_update_failed") }
      end
    end
  end

  def edit
    respond_to do |format|
      format.turbo_stream
      format.html
    end
  end

  def destroy
    @discussion_question.destroy
    @visible_questions = @book_read.visible_discussion_questions_for(current_user)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to book_club_book_read_path(@book_club, @book_read), notice: t("question_deleted") }
    end
  end

  private

  def set_discussion_question
    @discussion_question = @book_read.discussion_questions.find(params[:id])
  end

  def set_book_club_and_read
    @book_club = BookClub.find(params[:book_club_id])
    @book_read = @book_club.book_reads.find(params[:book_read_id])
  end

  def discussion_question_params
    params.require(:discussion_question).permit(:content)
  end

  def discussion_question_update_params
    params.require(:discussion_question).permit(:content, :status)
  end

  def store_discussion_question_draft
    return if user_signed_in?

    session[:discussion_question_draft] = params.dig(:discussion_question, :content)
    store_location_for(:user, book_club_book_read_path(params[:book_club_id], params[:book_read_id]))
  end

  def authorize_discussion_question_permission
    has_rsvp = @book_read.rsvp_users.exists?(id: current_user.id)
    return if has_rsvp

    authorize_club_owner!(@book_club, redirect_url: book_club_book_read_path(@book_club, @book_read))
  end

  def authorize_discussion_question_modification
    # Allow if user is the author
    return if @discussion_question.user == current_user

    # Allow if user is club owner or admin
    authorize_club_owner!(@book_club, redirect_url: book_club_book_read_path(@book_club, @book_read))
  end
end

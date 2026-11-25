require "test_helper"

class DiscussionQuestionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @book_club = book_clubs(:one)
    @book_read = book_reads(:one)
    sign_in @user
  end

  test "should create discussion question" do
    assert_difference("DiscussionQuestion.count") do
      post book_club_book_read_discussion_questions_url(@book_club, @book_read), params: {
        discussion_question: {
          content: "What did you think about the first chapter?"
        }
      }
    end

    assert_redirected_to book_club_book_read_path(@book_club, @book_read)
    assert DiscussionQuestion.last.draft?
  end

  test "should create discussion question via turbo stream" do
    assert_difference("DiscussionQuestion.count") do
      post book_club_book_read_discussion_questions_url(@book_club, @book_read), params: {
        discussion_question: {
          content: "What did you think about the first chapter?"
        }
      }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_match(/turbo-stream action="append" target="discussion_questions_list"/, @response.body)
    assert_match(/turbo-stream action="update" target="no_discussion_questions_wrapper"/, @response.body)
    assert DiscussionQuestion.last.draft?
  end

  test "should not create discussion question if not owner" do
    sign_out @user
    other_user = users(:two)
    sign_in other_user

    assert_no_difference("DiscussionQuestion.count") do
      post book_club_book_read_discussion_questions_url(@book_club, @book_read), params: {
        discussion_question: {
          content: "What did you think about the first chapter?"
        }
      }
    end

    assert_redirected_to book_club_book_read_path(@book_club, @book_read)
    assert_equal "You are not authorized to perform this action.", flash[:alert]
  end

  test "should not create discussion question with empty content via turbo stream" do
    assert_no_difference("DiscussionQuestion.count") do
      post book_club_book_read_discussion_questions_url(@book_club, @book_read), params: {
        discussion_question: {
          content: ""
        }
      }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_match(/turbo-stream action="replace" target="new_discussion_question_form"/, @response.body)
    assert_match(/Content can&#39;t be blank/, @response.body)
  end

  test "should not create discussion question with empty content" do
    assert_no_difference("DiscussionQuestion.count") do
      post book_club_book_read_discussion_questions_url(@book_club, @book_read), params: {
        discussion_question: {
          content: ""
        }
      }
    end

    assert_redirected_to book_club_book_read_path(@book_club, @book_read)
    assert_equal "Question cannot be blank.", flash[:alert]
  end

  test "should redirect unauthenticated users to sign in and preserve draft" do
    sign_out @user
    content = "Can we talk about the ending?"
    @book_read.poll = nil
    @book_read.save

    assert_no_difference("DiscussionQuestion.count") do
      post book_club_book_read_discussion_questions_url(@book_club, @book_read), params: {
        discussion_question: {
          content: content
        }
      }
    end

    assert_redirected_to new_user_session_path
    assert_equal book_club_book_read_path(@book_club, @book_read), session["user_return_to"]
    assert_equal content, session[:discussion_question_draft]

    sign_in @user
    get book_club_book_read_path(@book_club, @book_read)
    assert_response :success
    assert_includes @response.body, content
  end

  test "should delete a discussion question" do
    question = discussion_questions(:one)
    assert_difference("DiscussionQuestion.count", -1) do
      delete book_club_book_read_discussion_question_path(@book_club, @book_read, question)
    end

    assert_redirected_to book_club_book_read_path(@book_club, @book_read)
    assert_equal "Question deleted successfully.", flash[:notice]
  end

  test "should delete a discussion question via turbo stream and restore placeholder if last one" do
    # Ensure there is only one question for this book read that is visible
    @book_read.discussion_questions.destroy_all
    question = @book_read.discussion_questions.create!(user: @user, content: "Only question")

    assert_difference("DiscussionQuestion.count", -1) do
      delete book_club_book_read_discussion_question_path(@book_club, @book_read, question), as: :turbo_stream
    end

    assert_response :success
    assert_match(/turbo-stream action="remove" target="discussion_question_#{question.id}"/, @response.body)
    assert_match(/turbo-stream action="update" target="no_discussion_questions_wrapper"/, @response.body)
    assert_match(/No discussion so far/, @response.body)
  end

  test "should not delete discussion question if not author or admin" do
    sign_out @user
    other_user = users(:two) # not author of question :one
    sign_in other_user

    question = discussion_questions(:one)
    assert_no_difference("DiscussionQuestion.count") do
      delete book_club_book_read_discussion_question_path(@book_club, @book_read, question)
    end

    assert_redirected_to book_club_book_read_path(@book_club, @book_read)
    assert_equal "You are not authorized to perform this action.", flash[:alert]
  end

  test "author can delete their own discussion question" do
    # Sign in as user two, who authored question two
    sign_out @user
    author = users(:two)
    sign_in author
    question = discussion_questions(:two)

    assert_difference("DiscussionQuestion.count", -1) do
      delete book_club_book_read_discussion_question_path(book_clubs(:two), book_reads(:two), question)
    end

    assert_redirected_to book_club_book_read_path(book_clubs(:two), book_reads(:two))
    assert_equal "Question deleted successfully.", flash[:notice]
  end

  test "author cannot update status of their own discussion question if not owner or admin" do
    sign_out @user
    author = users(:two) # Not admin, not owner of club one
    sign_in author

    # Manually create a question for user two in book_read one (owned by user one)
    question = @book_read.discussion_questions.create!(user: author, content: "Author's question")

    assert_equal "draft", question.status

    patch book_club_book_read_discussion_question_path(@book_club, @book_read, question), params: {
      discussion_question: {
        content: "Updated content",
        status: "approved"
      }
    }

    assert_redirected_to book_club_book_read_path(@book_club, @book_read)
    question.reload
    assert_equal "Updated content", question.content
    assert_equal "draft", question.status # Status should NOT change
  end

  test "editing a question as author reverts status to draft if not owner or admin" do
    sign_out @user
    author = users(:two)
    sign_in author

    # Create an approved question manually (since author can't approve via controller)
    question = @book_read.discussion_questions.create!(user: author, content: "Original content", status: "approved")
    assert_equal "approved", question.status

    patch book_club_book_read_discussion_question_path(@book_club, @book_read, question), params: {
      discussion_question: {
        content: "Edited content"
      }
    }

    assert_redirected_to book_club_book_read_path(@book_club, @book_read)
    question.reload
    assert_equal "Edited content", question.content
    assert_equal "draft", question.status
    assert question.edited?
  end

  test "club owner can update status of any discussion question" do
    # @user is the owner of @book_club
    author = users(:two)
    question = @book_read.discussion_questions.create!(user: author, content: "Author's question")

    assert_equal "draft", question.status

    patch book_club_book_read_discussion_question_path(@book_club, @book_read, question), params: {
      discussion_question: {
        status: "approved"
      }
    }

    assert_redirected_to book_club_book_read_path(@book_club, @book_read)
    assert_equal "approved", question.reload.status
  end

  test "cannot add a discussion question to a book swap" do
    swap = book_reads(:swap)
    BookReadRsvp.rsvp!(book_read: swap, user: @user, status: :going)

    assert_no_difference("DiscussionQuestion.count") do
      post book_club_book_read_discussion_questions_url(@book_club, swap), params: {
        discussion_question: { content: "What did you bring?" }
      }
    end

    assert_redirected_to book_club_book_read_path(@book_club, swap)
  end
end

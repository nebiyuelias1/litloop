require "test_helper"

class BookClubsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @club_params = {
      book_club: {
        name: "Sci-Fi Readers",
        description: "A club for science fiction fans.",
        is_private: false
      }
    }
  end

  test "should create club and set the current user as owner" do
    sign_in @user

    assert_difference("BookClub.count", 1) do
      post book_clubs_url, params: @club_params
    end

    created_club = BookClub.last
    assert_equal @user.id, created_club.owner_id
    assert_equal "Sci-Fi Readers", created_club.name

    assert_redirected_to book_club_url(created_club)
    assert_equal "Book Club created successfully.", flash[:notice]
  end

  test "should create a membership record when user creates club" do
    sign_in @user

    post book_clubs_url, params: @club_params

    created_club = BookClub.last
    assert_equal 1, created_club.book_club_members_count
    membership = created_club.book_club_members.find_by(user: @user)

    assert_not_nil membership
    assert membership.admin?
  end

  test "should require form_url when creating private club" do
    sign_in @user

    @club_params[:book_club][:is_private] = true

    assert_difference("BookClub.count", 0) do
      post book_clubs_url, params: @club_params
    end

    assert_response :unprocessable_entity
    assert_select "form"
    assert_select "div", text: /can't be blank|must be a valid URL/i
  end

  test "should create private club when application_form_url is provided" do
    sign_in @user

    @club_params[:book_club][:is_private] = true
    @club_params[:book_club][:application_form_url] = "https://example.com/apply"

    assert_difference("BookClub.count", 1) do
      post book_clubs_url, params: @club_params
    end

    created_club = BookClub.last
    assert created_club.is_private?
    assert_equal "https://example.com/apply", created_club.application_form_url
    assert_redirected_to book_club_url(created_club)
  end

  test "should not create club if user is not signed in" do
    assert_no_difference("BookClub.count") do
      post book_clubs_url, params: @club_params
    end

    assert_redirected_to new_user_session_url
  end

  test "should get edit for owner" do
    @club = book_clubs(:one)
    sign_in @user # User one is the owner
    get edit_book_club_url(@club)
    assert_response :success
  end

  test "should not get edit for non-owner" do
    @club = book_clubs(:two) # User two is the owner
    sign_in @user # User one
    get edit_book_club_url(@club)
    assert_redirected_to book_club_url(@club)
    assert_equal "You are not authorized to perform this action.", flash[:alert]
  end

  test "should not get edit if not signed in" do
    @club = book_clubs(:one)
    get edit_book_club_url(@club)
    assert_redirected_to new_user_session_url
  end

  test "should update club for owner" do
    @club = book_clubs(:one)
    sign_in @user
    patch book_club_url(@club), params: {
      book_club: {
        name: "Updated Club Name",
        description: "New updated description",
        is_private: true,
        application_form_url: "https://test-form.com"
      }
    }
    assert_redirected_to book_club_url(@club)
    assert_equal "Book Club updated successfully.", flash[:notice]

    @club.reload
    assert_equal "Updated Club Name", @club.name
    assert_equal "New updated description", @club.description
    assert_equal true, @club.is_private
  end

  test "should update application_form_url for owner" do
    @club = book_clubs(:one)
    sign_in @user
    patch book_club_url(@club), params: {
      book_club: {
        application_form_url: "https://docs.google.com/forms/d/abc123"
      }
    }
    assert_redirected_to book_club_url(@club)

    @club.reload
    assert_equal "https://docs.google.com/forms/d/abc123", @club.application_form_url
  end

  test "should not update application_form_url with invalid URL" do
    @club = book_clubs(:one)
    sign_in @user
    patch book_club_url(@club), params: {
      book_club: {
        application_form_url: "not-a-url"
      }
    }
    assert_response :unprocessable_entity

    @club.reload
    assert_nil @club.application_form_url
  end

  test "edit shows checked private checkbox and visible application form url field for private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    sign_in @user
    get edit_book_club_url(@club)
    assert_response :success

    assert_select "input[name='book_club[is_private]'][checked]"
    assert_select "input[name='book_club[is_private]'][data-conditional-fields-target='toggle']"
    assert_select "input[name='book_club[is_private]'][data-action='change->conditional-fields#toggle']"
    assert_select "div[data-conditional-fields-target='field'][class*='hidden']", 0
    assert_select "input[name='book_club[application_form_url]'][disabled]", 0
    assert_select "input[name='book_club[application_form_url]']"
  end

  test "edit shows unchecked private checkbox and hidden application form url field for public club" do
    @club = book_clubs(:one)
    sign_in @user
    get edit_book_club_url(@club)
    assert_response :success

    assert_select "input[name='book_club[is_private]'][checked]", 0
    assert_select "div[data-conditional-fields-target='field'][class*='hidden']"
    assert_select "input[name='book_club[application_form_url]'][disabled]"
  end

  test "show hides member avatars and members dialog for non-member of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    sign_in users(:two)

    get book_club_url(@club)
    assert_response :success

    assert_select "#members_dialog", 0
    assert_select "img[src*='/rails/active_storage']", 0
  end

  test "show shows member avatars and members dialog for member of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    sign_in @user

    get book_club_url(@club)
    assert_response :success

    assert_select "#members_dialog"
  end

  test "show renders Apply to Join button and dialog for non-member of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    sign_in users(:two)

    get book_club_url(@club)
    assert_response :success

    # Apply button targets the dialog and the dialog posts to membership requests
    assert_select "button#book_club_show_join_button", /Apply to Join/
    assert_select "#apply_dialog_#{@club.id}"
    assert_select "#apply_dialog_#{@club.id} form[action='/book_clubs/#{@club.id}/membership_requests']"
    assert_select "#apply_dialog_#{@club.id} button[disabled]", /Send Request/

    # No direct Join/Leave affordance for a private club non-member
    assert_select "button", text: /Join Club/, count: 0
    assert_select "button", text: /Leave Club/, count: 0
  end

  test "show links Apply to Join to sign in for signed-out visitor of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")

    get book_club_url(@club)
    assert_response :success

    assert_select "a#book_club_show_join_button[href='/users/sign_in']", /Apply to Join/
    assert_select "#apply_dialog_#{@club.id}", 0
  end

  test "card links Apply to Join to sign in for signed-out visitor of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")

    get discover_book_clubs_path
    assert_response :success

    assert_select "#book_club_#{@club.id} a[href='/users/sign_in']", text: /Apply to Join/
    assert_select "#apply_dialog_#{@club.id}", 0
  end

  test "show hides member count and members trigger for non-member of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    sign_in users(:two)

    get book_club_url(@club)
    assert_response :success

    assert_select "button[onclick*='members_dialog']", 0
    assert_select "span.text-sm.text-content-subtle.font-medium", count: 0
  end

  test "discover carousel shows member count on club card for non-member of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    sign_in users(:two)

    get discover_book_clubs_path
    assert_response :success

    # Count is public on cards; avatars stay gated
    assert_select "#book_club_#{@club.id} span.text-xs", /\d+ members?/
  end

  test "discover carousel shows member count on club card for member of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    sign_in @user

    get discover_book_clubs_path
    assert_response :success

    assert_select "#book_club_#{@club.id} span.text-xs", /\d+ members?/
  end

  test "show hides poll details on the current reading card for non-member of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    book_read = @club.book_reads.new(
      host: @user,
      meetup_time: 1.week.from_now,
      meetup_location: "Secret Spot"
    )
    poll = book_read.build_poll(text: "Which book should we read next?", end_date: 3.days.from_now)
    poll.poll_options.build(content: "Beloved")
    poll.poll_options.build(content: "Sula")
    book_read.save!
    sign_in users(:two)

    get book_club_url(@club)
    assert_response :success

    assert_select "h2", text: "Which book should we read next?", count: 0
    assert_no_match(/Voting in Progress/, @response.body)
    assert_select "figure span", text: "Poll", count: 0
    assert_select "span", text: "Members only"
  end

  test "show shows poll details on the current reading card for member of private club" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    book_read = @club.book_reads.new(
      host: @user,
      meetup_time: 1.week.from_now,
      meetup_location: "Secret Spot"
    )
    poll = book_read.build_poll(text: "Which book should we read next?", end_date: 3.days.from_now)
    poll.poll_options.build(content: "Beloved")
    poll.poll_options.build(content: "Sula")
    book_read.save!
    sign_in @user

    get book_club_url(@club)
    assert_response :success

    assert_select "h2", text: "Which book should we read next?"
    assert_match(/Voting in Progress/, @response.body)
  end

  test "show renders pending requests indicator for the club owner" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    @club.membership_requests.create!(user: users(:two), status: :pending)
    sign_in @user

    get book_club_url(@club)
    assert_response :success

    # Badge next to the member count, plus the live count in the dialog header
    assert_select "[data-pending-requests-badge]"
    assert_select "[data-pending-requests-badge] span", text: /1 pending request/
    assert_select "[data-pending-requests-count]", "1"
  end

  test "show renders no pending indicator for the owner without pending requests" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    sign_in @user

    get book_club_url(@club)

    # Wrapper stays present for turbo stream updates but renders no badge
    assert_select "[data-pending-requests-badge] span", count: 0
  end

  test "show renders no pending indicator for non-owners" do
    @club = book_clubs(:one)
    @club.update!(is_private: true, application_form_url: "https://test-form.com")
    @club.membership_requests.create!(user: users(:two), status: :pending)
    sign_in users(:two)

    get book_club_url(@club)

    assert_select "[data-pending-requests-badge]", count: 0
  end

  test "show renders Leave Club with confirmation for non-owner members" do
    @club = book_clubs(:one)
    @club.book_club_members.create!(user: users(:two))
    sign_in users(:two)

    get book_club_url(@club)
    assert_response :success

    # Action sits in the turbo-swappable wrapper; Leave always confirms
    assert_select "#book_club_show_join_button_container button#book_club_show_join_button[data-turbo-confirm]", /Leave Club/
  end

  test "show renders Join Club without confirmation for non-members of public clubs" do
    @club = book_clubs(:one)
    sign_in users(:two)

    get book_club_url(@club)
    assert_response :success

    assert_select "button#book_club_show_join_button", /Join Club/
    assert_select "button#book_club_show_join_button[data-turbo-confirm]", count: 0
  end

  test "show renders privacy badge and creator avatar" do
    @club = book_clubs(:one)
    sign_in users(:two)

    get book_club_url(@club)
    assert_response :success

    assert_select ".badge", /Public Club/
    assert_select "span", text: /Created by/
    # shared/avatar renders the owner's avatar with their name as title
    assert_select "div[title='Test User One']"
  end

  test "card renders Joined with confirmation for non-owner members" do
    book_clubs(:one).book_club_members.create!(user: users(:two))
    sign_in users(:two)

    get discover_book_clubs_path
    assert_response :success

    assert_select "#book_club_#{book_clubs(:one).id} button[data-turbo-confirm]", /Joined/
  end

  test "card renders Edit Club instead of join toggle for the owner" do
    sign_in users(:one) # owner of book_clubs(:one)

    get discover_book_clubs_path
    assert_response :success

    assert_select "#book_club_#{book_clubs(:one).id} a[href='#{edit_book_club_path(book_clubs(:one))}']", /Edit Club/
    assert_select "#book_club_#{book_clubs(:one).id} button", text: /Joined/, count: 0
    assert_select "#book_club_#{book_clubs(:one).id} button", text: /Join/, count: 0
  end

  test "club page shows an upcoming book swap with its guidelines" do
    swap = book_reads(:swap)
    swap.update_columns(meetup_time: 1.day.from_now)
    sign_in @user

    get book_club_url(swap.book_club)

    assert_response :success
    assert_match "December Book Swap", response.body
    assert_match "Bring 1–3 books in good condition. Leftovers get donated.", response.body
  end
end

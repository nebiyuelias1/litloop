require "test_helper"

# Account pages, their links, and sign up → confirm → sign in → reset.
class AuthFlowsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
  end

  private def last_email_text
    mail = ActionMailer::Base.deliveries.last
    (mail.html_part || mail.text_part || mail).body.decoded
  end

  test "sign in page links to sign up, forgot password and resend confirmation" do
    get new_user_session_path
    assert_response :success
    # Scoped to main: the navbar has its own Sign Up button.
    assert_select "main a[href=?]", new_user_registration_path
    assert_select "main a[href=?]", new_user_password_path
    assert_select "main a[href=?]", new_user_confirmation_path
  end

  test "sign up page links to sign in" do
    get new_user_registration_path
    assert_response :success
    assert_select "main a[href=?]", new_user_session_path
  end

  test "forgot password and resend confirmation pages link back to sign in" do
    [ new_user_password_path, new_user_confirmation_path ].each do |path|
      get path
      assert_response :success
      assert_select "main a[href=?]", new_user_session_path
    end
  end

  test "sign up sends a confirmation email whose link confirms the account" do
    assert_emails 1 do
      post user_registration_path, params: { user: {
        name: "New Reader", email: "new.reader@example.com",
        password: "secret123", password_confirmation: "secret123"
      } }
    end
    user = User.find_by!(email: "new.reader@example.com")
    assert_nil user.confirmed_at

    token = last_email_text[/confirmation_token=([^"&\s]+)/, 1]
    assert token, "confirmation email should contain a token link"
    get user_confirmation_path(confirmation_token: token)
    assert user.reload.confirmed_at
  end

  test "sign up with invalid details re-renders the form with errors" do
    assert_no_difference "User.count" do
      post user_registration_path, params: { user: {
        name: "", email: users(:one).email, password: "123", password_confirmation: "456"
      } }
    end
    assert_response :unprocessable_content
    assert_select "#error_explanation"
  end

  test "sign in with correct and incorrect passwords" do
    post user_session_path, params: { user: { email: users(:one).email, password: "wrong-password" } }
    assert_response :unprocessable_content
    assert_select "form[action=?]", user_session_path

    post user_session_path, params: { user: { email: users(:one).email, password: "password123" } }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "forgot password emails a reset link that sets a new password" do
    user = users(:two)
    assert_emails 1 do
      post user_password_path, params: { user: { email: user.email } }
    end
    assert_redirected_to new_user_session_path

    token = last_email_text[/reset_password_token=([^"&\s]+)/, 1]
    assert token, "reset email should contain a token link"

    get edit_user_password_path(reset_password_token: token)
    assert_response :success
    assert_select "input[name=?]", "user[password]"

    put user_password_path, params: { user: {
      reset_password_token: token, password: "brand-new-pass", password_confirmation: "brand-new-pass"
    } }
    assert_response :redirect
    assert user.reload.valid_password?("brand-new-pass")
  end

  test "reset password with an invalid token shows an error" do
    put user_password_path, params: { user: {
      reset_password_token: "not-a-real-token", password: "brand-new-pass", password_confirmation: "brand-new-pass"
    } }
    assert_response :unprocessable_content
    assert_select "#error_explanation"
  end

  test "every auth page renders in every locale without missing translations" do
    paths = [ new_user_session_path, new_user_registration_path, new_user_password_path, new_user_confirmation_path ]
    I18n.available_locales.each do |locale|
      paths.each do |path|
        get path, params: { locale: locale }
        assert_response :success, "#{path} in #{locale}"
        assert_no_match(/translation[ _]missing/i, response.body, "#{path} in #{locale}")
      end
    end
  end

  test "forgot password gives the same answer for unknown emails and sends nothing" do
    assert_no_emails do
      post user_password_path, params: { user: { email: "nobody-here@example.com" } }
    end
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_match I18n.t("devise.passwords.send_paranoid_instructions"), response.body
  end

  test "an expired or invalid reset link offers a new one" do
    put user_password_path, params: { user: {
      reset_password_token: "not-a-real-token", password: "brand-new-pass", password_confirmation: "brand-new-pass"
    } }
    assert_select "a[href=?]", new_user_password_path, text: I18n.t("auth.reset.request_new")
  end

  test "auth forms lock after the first submit" do
    [ new_user_session_path, new_user_registration_path, new_user_password_path, new_user_confirmation_path ].each do |path|
      get path
      assert_select "form[data-controller~=submit-once] button[type=submit][data-submit-once-target=button]", 1, path
    end
  end

  test "repeated sign-in attempts are rate limited" do
    AuthRateLimited.store = ActiveSupport::Cache::MemoryStore.new
    10.times do
      post user_session_path, params: { user: { email: users(:one).email, password: "wrong-password" } }
      assert_response :unprocessable_content
    end
    post user_session_path, params: { user: { email: users(:one).email, password: "wrong-password" } }
    assert_redirected_to new_user_session_path
    assert_equal I18n.t("auth.rate_limited"), flash[:alert]
  ensure
    AuthRateLimited.store = nil
  end

  test "password reset requests are rate limited" do
    AuthRateLimited.store = ActiveSupport::Cache::MemoryStore.new
    5.times { post user_password_path, params: { user: { email: users(:two).email } } }
    post user_password_path, params: { user: { email: users(:two).email } }
    assert_redirected_to new_user_password_path
    assert_equal I18n.t("auth.rate_limited"), flash[:alert]
  ensure
    AuthRateLimited.store = nil
  end
end

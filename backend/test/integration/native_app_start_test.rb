require "test_helper"

# Where the native apps start, and their tab/title bar messages.
class NativeAppStartTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  NATIVE = { "User-Agent" => "LitLoop iOS/1.0 Hotwire Native iOS; Turbo Native iOS" }.freeze

  test "a guest on a fresh install starts at the onboarding tour" do
    get root_path, headers: NATIVE
    assert_redirected_to onboarding_path
  end

  test "the tour shows once per install" do
    get root_path, headers: NATIVE
    assert_redirected_to onboarding_path
    get onboarding_path, headers: NATIVE
    assert_response :success

    get root_path, headers: NATIVE
    assert_response :success
  end

  # Android loads every tab at launch; Profile redirects guests to sign in.
  test "sign in loading in another tab doesn't skip the tour" do
    get new_user_session_path, headers: NATIVE
    get new_user_registration_path, headers: NATIVE
    get root_path, headers: NATIVE
    assert_redirected_to onboarding_path
  end

  # That redirect's flash would otherwise pop up on the tour.
  test "no sign-in flash in the apps when a tab needs an account" do
    get profile_path, headers: NATIVE
    assert_redirected_to new_user_session_path
    assert_nil flash[:alert]
  end

  test "the website still explains the redirect to sign in" do
    get profile_path
    assert_redirected_to new_user_session_path
    assert_equal I18n.t("devise.failure.unauthenticated"), flash[:alert]
  end

  test "signed-in members open straight on home" do
    sign_in users(:one)
    get root_path, headers: NATIVE
    assert_response :success
  end

  test "the website is unaffected" do
    get root_path
    assert_response :success
    get onboarding_path
    assert_nil cookies[:onboarded]
  end

  test "the tour asks the apps to hide the tab bar and title bar" do
    get onboarding_path, headers: NATIVE
    assert_select "[data-controller='bridge--tab-bar']:not([data-bridge--tab-bar-event-value])", 1
    assert_select "[data-controller='bridge--navigation-bar']", 1

    get onboarding_path
    assert_select "[data-controller='bridge--tab-bar']", 0
    assert_select "[data-controller='bridge--navigation-bar']", 0
  end

  test "account pages ask to hide the tab bar when opened on top of another page" do
    [ new_user_session_path, new_user_registration_path, new_user_password_path ].each do |path|
      get path, headers: NATIVE
      assert_select "[data-controller='bridge--tab-bar'][data-bridge--tab-bar-event-value='hide-when-pushed']", 1, path
    end

    get new_user_session_path
    assert_select "[data-controller='bridge--tab-bar']", 0
  end

  test "other app pages ask the apps to show the tab bar" do
    get root_path, headers: NATIVE.merge("Cookie" => "onboarded=1")
    assert_select "[data-controller='bridge--tab-bar'][data-bridge--tab-bar-event-value='show']", 1

    get root_path
    assert_select "[data-controller='bridge--tab-bar']", 0
  end
end

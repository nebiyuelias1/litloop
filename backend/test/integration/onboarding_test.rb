require "test_helper"

class OnboardingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guests see the tour, ending in sign up and sign in" do
    get onboarding_path
    assert_response :success
    assert_select "[data-controller=onboarding]"
    assert_select "[data-onboarding-target=slide]", 5
    assert_select "h1", 1
    assert_select "a[href=?]", new_user_registration_path
    assert_select "a[href=?]", new_user_session_path
  end

  test "the tour renders in every locale without missing translations" do
    I18n.available_locales.each do |locale|
      get onboarding_path, params: { locale: locale }
      assert_response :success, "onboarding in #{locale}"
      assert_no_match(/translation[ _]missing/i, response.body, "onboarding in #{locale}")
    end
  end

  test "signed-in members go straight home" do
    sign_in users(:one)
    get onboarding_path
    assert_redirected_to root_path
  end

  test "sign in and sign up link to the tour" do
    [ new_user_session_path, new_user_registration_path ].each do |path|
      get path
      assert_select "main a[href=?]", onboarding_path
    end
  end
end

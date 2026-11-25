require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end

  private

  # Signs in through the real UI. Turbo drives the form submissions with
  # async fetches, so we wait for each navigation to settle before
  # returning - otherwise a pending redirect can race and override the
  # test's next visit (landing on the wrong page).
  def login_as(user)
    visit profile_path
    if page.has_button?("Sign out")
      click_on "Sign out"
      assert_no_button "Sign out"
    end
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_on "Sign in"
    assert_no_button "Sign in"
  end
end

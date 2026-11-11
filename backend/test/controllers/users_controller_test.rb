require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    ENV["OTARI_MONTHLY_QUOTA"] = "5"
  end

  teardown { ENV["OTARI_MONTHLY_QUOTA"] = nil }

  test "profile shows the monthly Otari budget for a regular user" do
    sign_in users(:two)
    get profile_path
    assert_response :success

    assert_includes response.body, "AI Budget"
    assert_includes response.body, "5 of 5 left"
    assert_includes response.body, "0 of 5 used this month"
  end

  test "profile reflects the budget already spent this month" do
    user = users(:two)
    3.times { OtariBudget.record!(user: user, feature: "dna_generation") }

    sign_in user
    get profile_path
    assert_response :success

    assert_includes response.body, "2 of 5 left"
    assert_includes response.body, "3 of 5 used this month"
  end

  test "profile shows unlimited budget for admins" do
    sign_in users(:one)
    get profile_path
    assert_response :success

    assert_includes response.body, "Unlimited"
    refute_includes response.body, "left</span>"
  end
end

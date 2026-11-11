require "test_helper"

class OtariBudgetTest < ActiveSupport::TestCase
  setup do
    ENV["OTARI_MONTHLY_QUOTA"] = "5"
    @owner = users(:two)
    @club = BookClub.create!(name: "Budget Club", owner: @owner)
  end

  teardown { ENV["OTARI_MONTHLY_QUOTA"] = nil }

  test "uses the default quota from the environment" do
    assert_equal 5, OtariBudget.monthly_quota(@owner)
  end

  test "a per-user override wins over the default" do
    @owner.update!(otari_monthly_quota: 20)
    assert_equal 20, OtariBudget.monthly_quota(@owner)
  end

  test "allows spending within the quota and denies beyond it" do
    5.times { OtariBudget.record!(user: @owner, feature: "dna_generation", club: @club) }

    assert_equal 5, OtariBudget.units_used_this_month(@owner)
    assert_equal 0, OtariBudget.remaining(@owner)
    assert OtariBudget.allow?(@owner, feature: "dna_generation") == false
  end

  test "usage from previous months does not count against the budget" do
    OtariBudget.record!(user: @owner, feature: "dna_generation", club: @club)
    OtariUsage.where(user: @owner).update_all(created_at: 1.month.ago)

    assert_equal 0, OtariBudget.units_used_this_month(@owner)
    assert OtariBudget.allow?(@owner, feature: "dna_generation")
  end

  test "site admins are exempt from the quota but still metered" do
    admin = users(:one)
    10.times { OtariBudget.record!(user: admin, feature: "dna_generation") }

    assert OtariBudget.allow?(admin, feature: "dna_generation")
    assert_equal 10, OtariBudget.units_used_this_month(admin)
  end

  test "system-triggered usage (no user) is allowed" do
    assert OtariBudget.allow?(nil, feature: "dna_generation")
  end

  test "record! stores cost, club, model and token usage" do
    usage = OtariBudget.record!(user: @owner, feature: "dna_generation", club: @club,
      model: "openai/gpt-oss-120b",
      tokens: { "input_tokens" => 1200, "output_tokens" => 800, "total_tokens" => 2000 })

    assert usage.persisted?
    assert_equal @owner, usage.user
    assert_equal @club, usage.book_club
    assert_equal 1, usage.cost
    assert_equal 1200, usage.input_tokens
    assert_equal 2000, usage.total_tokens
  end

  test "metering failures never break the main flow" do
    OtariUsage.stub(:create!, ->(*) { raise "boom" }) do
      assert_nothing_raised do
        assert_nil OtariBudget.record!(user: @owner, feature: "dna_generation")
      end
    end
  end
end

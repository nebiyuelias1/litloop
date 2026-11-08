require "test_helper"

class CountryCodesTest < ActiveSupport::TestCase
  test "maps official names to ISO alpha-2 codes" do
    assert_equal "NG", CountryCodes.code_for("Nigeria")
    assert_equal "IL", CountryCodes.code_for("Israel")
    assert_equal "ET", CountryCodes.code_for("Ethiopia")
    assert_equal "US", CountryCodes.code_for("United States")
    assert_equal "GB", CountryCodes.code_for("United Kingdom")
  end

  test "handles common alias names" do
    assert_equal "US", CountryCodes.code_for("United States of America")
    assert_equal "CZ", CountryCodes.code_for("Czech Republic")
    assert_equal "SZ", CountryCodes.code_for("Swaziland")
    assert_equal "CD", CountryCodes.code_for("DR Congo")
  end

  test "rejects invented country names" do
    assert_nil CountryCodes.code_for("Atlantis")
    assert_nil CountryCodes.code_for("Wakanda")
    assert_nil CountryCodes.code_for("")
  end

  test "round-trips code back to name" do
    assert_equal "Nigeria", CountryCodes.name_for("NG")
    assert_nil CountryCodes.name_for("XX")
    assert_nil CountryCodes.name_for("Nigeria")
  end

  test "renders flag emoji from alpha-2 code" do
    assert_equal "🇳🇬", CountryCodes.flag_for("NG")
    assert_nil CountryCodes.flag_for("Nigeria")
  end
end

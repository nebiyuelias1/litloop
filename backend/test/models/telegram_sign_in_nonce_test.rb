require "test_helper"

class TelegramSignInNonceTest < ActiveSupport::TestCase
  test "consume! accepts a fresh nonce once" do
    assert_nothing_raised { TelegramSignInNonce.consume!("nonce-a") }
  end

  test "consume! rejects a replayed nonce" do
    TelegramSignInNonce.consume!("nonce-b")

    assert_raises(TelegramSignInNonce::AlreadyUsed) do
      TelegramSignInNonce.consume!("nonce-b")
    end
  end

  test "consume! prunes nonces older than the validity period" do
    stale = TelegramSignInNonce.create!(nonce: "stale", created_at: 2.days.ago)

    TelegramSignInNonce.consume!("fresh")

    assert_not TelegramSignInNonce.exists?(stale.id)
  end
end

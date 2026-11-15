# Records Telegram Login (OIDC) nonces that have been consumed, so a copy of a
# pre-sign-in session cookie (which carries the nonce) cannot replay an
# id_token. Consumption is atomic: the unique index on +nonce+ makes a second
# insert fail even under concurrent requests.
class TelegramSignInNonce < ApplicationRecord
  class AlreadyUsed < StandardError; end

  VALIDITY_PERIOD = 1.day

  validates :nonce, presence: true

  # Marks a nonce as used. Raises AlreadyUsed when it has been consumed before.
  def self.consume!(nonce)
    where(created_at: ...VALIDITY_PERIOD.ago).delete_all
    create!(nonce: nonce)
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyUsed
  end
end

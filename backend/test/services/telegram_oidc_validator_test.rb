require "test_helper"

class TelegramOidcValidatorTest < ActiveSupport::TestCase
  CLIENT_ID = "123456789"
  NONCE = "testnonce123"

  setup do
    @old_key = OpenSSL::PKey::RSA.generate(2048)
    @new_key = OpenSSL::PKey::RSA.generate(2048)
  end

  test "validates a token signed by a published key" do
    token = mint_token(claims, @old_key, kid: jwk(@old_key)[:kid])
    loader = static_loader({ keys: [ jwk(@old_key) ] })

    claims = TelegramOidcValidator.validate(id_token: token, client_id: CLIENT_ID, nonce: NONCE, jwks_loader: loader)

    assert_equal 987654321, claims["id"]
  end

  test "refreshes the JWKS when the token kid is unknown (key rotation)" do
    calls = []
    loader = ->(options) {
      calls << options
      calls.size == 1 ? { keys: [ jwk(@old_key) ] } : { keys: [ jwk(@new_key) ] }
    }
    # Signed with the NEW key, which is only published after rotation.
    token = mint_token(claims, @new_key, kid: jwk(@new_key)[:kid])

    result = TelegramOidcValidator.validate(id_token: token, client_id: CLIENT_ID, nonce: NONCE, jwks_loader: loader)

    assert result, "rotation should trigger a refresh and validate"
    assert calls.any? { |options| options[:invalidate] || options[:invalidated] },
      "the loader must be asked to invalidate its cache"
  end

  test "rejects a token signed by an unknown key" do
    rogue_key = OpenSSL::PKey::RSA.generate(2048)
    token = mint_token(claims, rogue_key, kid: jwk(rogue_key)[:kid])
    loader = static_loader({ keys: [ jwk(@old_key) ] })

    assert_nil TelegramOidcValidator.validate(id_token: token, client_id: CLIENT_ID, nonce: NONCE, jwks_loader: loader)
  end

  test "rejects a nonce mismatch" do
    token = mint_token(claims.merge(nonce: "somethingelse"), @old_key, kid: jwk(@old_key)[:kid])
    loader = static_loader({ keys: [ jwk(@old_key) ] })

    assert_nil TelegramOidcValidator.validate(id_token: token, client_id: CLIENT_ID, nonce: NONCE, jwks_loader: loader)
  end

  test "rejects a wrong audience" do
    token = mint_token(claims.merge(aud: "999999999"), @old_key, kid: jwk(@old_key)[:kid])
    loader = static_loader({ keys: [ jwk(@old_key) ] })

    assert_nil TelegramOidcValidator.validate(id_token: token, client_id: CLIENT_ID, nonce: NONCE, jwks_loader: loader)
  end

  test "rejects an expired token" do
    token = mint_token(claims.merge(exp: 1.hour.ago.to_i), @old_key, kid: jwk(@old_key)[:kid])
    loader = static_loader({ keys: [ jwk(@old_key) ] })

    assert_nil TelegramOidcValidator.validate(id_token: token, client_id: CLIENT_ID, nonce: NONCE, jwks_loader: loader)
  end

  private

  def claims
    now = Time.now.to_i
    {
      iss: "https://oauth.telegram.org",
      aud: CLIENT_ID,
      sub: "987654321",
      id: 987654321,
      name: "Test User",
      preferred_username: "testuser",
      iat: now,
      exp: now + 1.hour,
      nonce: NONCE
    }
  end

  def mint_token(claims_hash, key, kid:)
    JWT.encode(claims_hash, key, "RS256", { kid: kid })
  end

  def jwk(key)
    JWT::JWK.new(key).export
  end

  def static_loader(jwks)
    ->(_options) { jwks }
  end
end

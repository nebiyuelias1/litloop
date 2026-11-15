# frozen_string_literal: true

require "net/http"
require "json"

# Validates id_tokens from Telegram Login (OpenID Connect).
# See https://core.telegram.org/bots/telegram-login
class TelegramOidcValidator
  ISSUER = "https://oauth.telegram.org"
  JWKS_URL = ENV.fetch("TELEGRAM_OIDC_JWKS_URL", "https://oauth.telegram.org/.well-known/jwks.json")
  JWKS_CACHE_KEY = "telegram_oidc:jwks:v2"

  class << self
    # Returns the validated claims hash, or nil when the token is not a valid,
    # current Telegram id_token for this client.
    # `jwks_loader` may be a JWKS hash, or a callable that receives the JWT
    # loader options (used by tests to simulate key rotation).
    def validate(id_token:, client_id:, nonce: nil, jwks_loader: nil)
      return nil if id_token.blank? || client_id.blank?

      claims, = JWT.decode(
        id_token,
        nil,
        true,
        algorithms: [ "RS256" ],
        iss: ISSUER,
        verify_iss: true,
        aud: client_id,
        verify_aud: true,
        verify_expiration: true,
        jwks: jwks_loader_for(jwks_loader)
      )

      return nil if nonce.present? && claims["nonce"].to_s != nonce

      claims
    rescue StandardError => e
      Rails.logger.warn("Telegram OIDC validation failed: #{e.class}: #{e.message}")
      nil
    end

    private

    def jwks_loader_for(jwks_loader)
      if jwks_loader.respond_to?(:call)
        jwks_loader
      elsif jwks_loader
        ->(_options) { jwks_loader }
      else
        ->(options) {
          # ruby-jwt calls the loader with invalidate: true when the token's kid
          # is missing from the cached keys (signing key rotation).
          Rails.cache.delete(JWKS_CACHE_KEY) if options && (options[:invalidate] || options[:invalidated])
          cached_jwks
        }
      end
    end

    def cached_jwks
      Rails.cache.fetch(JWKS_CACHE_KEY, expires_in: 1.hour) do
        jwks = JSON.parse(Net::HTTP.get(URI(JWKS_URL)))
        # Telegram publishes RSA, EC and OKP keys; we verify RS256 tokens only,
        # and ruby-jwt cannot import the other key types.
        jwks["keys"] = jwks["keys"].select { |key| key["kty"] == "RSA" }
        jwks
      end
    end
  end
end

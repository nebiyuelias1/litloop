class TelegramLoginController < ApplicationController
  # Telegram Login (OpenID Connect): receives the id_token produced by the
  # login popup (web) or the native SDKs. CSRF applies — the caller is our own
  # login page, same session. See https://core.telegram.org/bots/telegram-login
  def oidc
    # Web popup flow (POST) requires the session nonce; the native apps deliver
    # the id_token through the OS-verified Telegram app channel, so their GET
    # requests skip it.
    nonce_required = request.post?
    nonce = session[:telegram_oidc_nonce]
    claims = nil

    if !nonce_required || nonce.present?
      claims = TelegramOidcValidator.validate(
        id_token: params[:id_token],
        client_id: telegram_client_id,
        nonce: nonce_required ? nonce : nil
      )
    end

    if claims
      session.delete(:telegram_oidc_nonce)
      user = User.from_oidc(claims)

      user.remember_me = true
      sign_in(user)
      render json: { status: "ok", redirect_url: root_path }
    else
      render json: { status: "error", error: "Telegram sign-in failed." }, status: :unauthorized
    end
  end

  private

  # The OIDC client id is the bot's numeric id — the bot token's prefix
  # (the JWT audience claim equals it, per core.telegram.org/bots/telegram-login).
  def telegram_client_id
    ENV["TELEGRAM_BOT_TOKEN"].to_s.split(":").first
  end
end

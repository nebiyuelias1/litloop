class TelegramLoginController < ApplicationController
  # The callback is a GET redirect from Telegram's servers, which cannot include
  # a Rails CSRF token. CSRF protection is provided by the OAuth `state` parameter
  # validated in the callback action.
  skip_before_action :verify_authenticity_token, only: [ :callback ]

  # Legacy widget callback (also used by the Telegram Mini App login flow).
  def callback
    if telegram_data_is_valid?
      user = User.from_telegram_auth(telegram_params)

      user.remember_me = true
      sign_in(user)
      redirect_to root_path, notice: "Successfully logged in with Telegram."
    else
      redirect_to new_user_session_path, alert: "Telegram authentication failed."
    end
  end

  # Telegram Login (OpenID Connect): receives the id_token produced by the
  # login popup (web) or the native SDKs. CSRF applies — the caller is our own
  # login page, same session. See https://core.telegram.org/bots/telegram-login
  def oidc
    nonce = session[:telegram_oidc_nonce]
    claims = nil

    if nonce.present?
      claims = TelegramOidcValidator.validate(
        id_token: params[:id_token],
        client_id: ENV["TELEGRAM_LOGIN_CLIENT_ID"],
        nonce: nonce
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

  def telegram_data_is_valid?
    data_check_string = telegram_params.to_h.except("hash").map { |k, v| "#{k}=#{v}" }.sort.join("\n")
    secret_key = Digest::SHA256.digest(ENV["TELEGRAM_BOT_TOKEN"])
    hash = OpenSSL::HMAC.hexdigest("sha256", secret_key, data_check_string)
    hash == telegram_params[:hash]
  end

  def telegram_params
    params.permit(:id, :first_name, :last_name, :username, :photo_url, :auth_date, :hash)
  end
end

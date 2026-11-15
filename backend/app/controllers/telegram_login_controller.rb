class TelegramLoginController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :callback ]

  # How long a completed native handoff waits for the app to poll for it.
  PENDING_HANDOFF_TTL = 10.minutes

  # The callback is a GET redirect from Telegram's servers (or an in-app deep
  # link), which cannot include a Rails CSRF token. Authenticity is provided by
  # the signed `hash` parameter, validated in telegram_data_valid?.
  def callback
    if telegram_data_valid?(telegram_params)
      sign_in_telegram_user(telegram_params)
      redirect_to root_path, notice: "Successfully logged in with Telegram."
    else
      redirect_to new_user_session_path, alert: "Telegram authentication failed."
    end
  end

  # Rendered in the external browser (Custom Tab / SFSafariViewController) after
  # a native Telegram sign-in. The user data arrives in the URL fragment
  # (#tgAuthResult=<base64>) which never reaches the server, so this page's JS
  # decodes it and relays it back into the app: via the litloop:// deep link,
  # and via the handoff endpoint + polling as the fallback.
  def native_return
    render layout: false
  end

  # Receives the parsed signed user data from the native_return page and parks
  # it, keyed by the state nonce the app's login page generated, until the app
  # polls for it.
  def handoff
    if valid_handoff_state? && telegram_data_valid?(telegram_params)
      Rails.cache.write(pending_handoff_key(params[:state]), telegram_params.to_h, expires_in: PENDING_HANDOFF_TTL)
      head :no_content
    else
      head :unprocessable_entity
    end
  end

  # Polled by the login page inside the app's WebView while the user completes
  # sign-in in the external browser. Only handoffs for state nonces generated
  # for this very session are accepted, so a crafted state can't be used to
  # capture someone else's authorization.
  def poll
    telegram_auth_states.each do |state|
      key = pending_handoff_key(state)
      data = Rails.cache.read(key)
      next unless data

      Rails.cache.delete(key)
      sign_in_telegram_user(data)
      return render json: { status: "ok", redirect_url: root_path }
    end

    render json: { status: "pending" }
  end

  private

  def telegram_data_valid?(data)
    data = data.to_h
    data_check_string = data.except("hash").map { |k, v| "#{k}=#{v}" }.sort.join("\n")
    secret_key = Digest::SHA256.digest(ENV["TELEGRAM_BOT_TOKEN"])
    hash = OpenSSL::HMAC.hexdigest("sha256", secret_key, data_check_string)
    hash == data["hash"]
  end

  def telegram_params
    params.permit(:id, :first_name, :last_name, :username, :photo_url, :auth_date, :hash)
  end

  def sign_in_telegram_user(data)
    user = User.from_telegram_auth(data.to_h.stringify_keys)
    user.remember_me = true
    sign_in(user)
  end

  def valid_handoff_state?
    params[:state].to_s.match?(/\A\h{32}\z/)
  end

  def pending_handoff_key(state)
    "telegram_handoff:#{state}"
  end

  def telegram_auth_states
    session[:telegram_auth_states] || []
  end
end

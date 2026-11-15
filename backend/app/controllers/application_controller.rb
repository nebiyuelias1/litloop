class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :set_time_zone
  helper_method :user_device_language, :register_telegram_auth_state!, :telegram_oauth_url

  before_action :set_locale

  protected

  # Native Telegram sign-in: generates a nonce bound to this session, stored
  # with the pending handoff after the user completes sign-in in the external
  # browser. TelegramLoginController#poll only accepts nonces from this list,
  # so a crafted state can't capture another user's authorization.
  def register_telegram_auth_state!
    session[:telegram_auth_states] ||= []
    session[:telegram_auth_states] << SecureRandom.hex(16)
    session[:telegram_auth_states] = session[:telegram_auth_states].last(10)
    session[:telegram_auth_states].last
  end

  # The Telegram OAuth page opens in the external browser (Hotwire routes
  # cross-origin urls there) and redirects back to the handoff page with the
  # signed user data in the URL fragment.
  def telegram_oauth_url(state:)
    bot_id = ENV["TELEGRAM_BOT_TOKEN"].to_s.split(":").first
    origin = request.base_url
    return_to = telegram_login_native_return_url(state: state)

    "https://oauth.telegram.org/auth?" + {
      bot_id: bot_id,
      origin: origin,
      request_access: "write",
      embed: 0,
      return_to: return_to
    }.to_query
  end

  def set_locale
    locale = params[:locale]
    matched_locale = I18n.available_locales.find { |l| l.to_s.downcase == locale.to_s.downcase }
    I18n.locale = (matched_locale || I18n.default_locale)
  end

  def default_url_options
    (I18n.locale == I18n.default_locale) ? {} : { locale: I18n.locale }
  end

  def set_time_zone(&block)
    # Some browsers report a fixed-offset identifier (e.g. "Etc/GMT 5") from
    # Intl.DateTimeFormat(), which is not a valid ActiveSupport::TimeZone name.
    # Fall back to the app default zone instead of raising.
    time_zone = Time.find_zone(cookies[:user_time_zone]) || Time.zone.name
    Time.use_zone(time_zone, &block)
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || super
  end

  def after_sign_up_path_for(resource)
    stored_location_for(resource) || super
  end

  def authorize_club_owner!(club, redirect_url: nil)
    unless club.owner == current_user || club.book_club_members.exists?(user: current_user, role: :admin)
      redirect_to (redirect_url || book_club_path(club)), alert: "You are not authorized to perform this action."
    end
  end

  private

  def user_device_language
    @user_device_language ||= begin
      lang = request.env["HTTP_ACCEPT_LANGUAGE"]&.split(",")&.first
      (lang.presence || "EN").upcase
    end
  end
end

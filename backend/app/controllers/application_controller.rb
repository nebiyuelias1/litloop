class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :set_time_zone
  helper_method :user_device_language, :telegram_oidc_nonce

  before_action :set_locale

  protected

  # Telegram Login (OIDC) replay protection: a nonce generated for this session
  # is included in the id_token and verified server-side on sign-in. It persists
  # until consumed so Turbo-restored login pages still validate.
  def telegram_oidc_nonce
    session[:telegram_oidc_nonce] ||= SecureRandom.hex(16)
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

  ONBOARDED_COOKIE = :onboarded

  def remember_onboarded
    cookies.permanent[ONBOARDED_COOKIE] = "1" if hotwire_native_app?
  end

  def onboarding_pending?
    hotwire_native_app? && !user_signed_in? && cookies[ONBOARDED_COOKIE].blank?
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

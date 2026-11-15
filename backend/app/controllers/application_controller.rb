class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :set_time_zone
  helper_method :user_device_language

  before_action :set_locale

  protected

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

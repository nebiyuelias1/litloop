require "net/http"
require "uri"
require "json"

class LineLoginController < ApplicationController
  # The callback is a GET redirect from LINE's servers, which cannot include
  # a Rails CSRF token. CSRF protection is provided by the OAuth `state` parameter
  # validated in the callback action.
  skip_before_action :verify_authenticity_token, only: [ :callback ]

  LINE_AUTH_URL = "https://access.line.me/oauth2/v2.1/authorize"
  LINE_TOKEN_URL = "https://api.line.me/oauth2/v2.1/token"
  LINE_TOKEN_VERIFY_URL = "https://api.line.me/oauth2/v2.1/verify"
  LINE_PROFILE_URL = "https://api.line.me/v2/profile"

  def authorize
    state = SecureRandom.hex(16)
    session[:line_oauth_state] = state

    query = URI.encode_www_form(
      response_type: "code",
      client_id: ENV["LINE_CHANNEL_ID"],
      redirect_uri: line_login_callback_url,
      state: state,
      scope: "profile"
    )

    redirect_to "#{LINE_AUTH_URL}?#{query}", allow_other_host: true
  end

  def callback
    if params[:error].present?
      redirect_to new_user_session_path, alert: "LINE authentication failed: #{params[:error_description]}"
      return
    end

    unless params[:state].present? && params[:state] == session.delete(:line_oauth_state)
      redirect_to new_user_session_path, alert: "LINE authentication failed: Invalid state parameter."
      return
    end

    access_token = exchange_code_for_token(params[:code])

    if access_token.nil?
      redirect_to new_user_session_path, alert: "LINE authentication failed: Could not obtain access token."
      return
    end

    sign_in_with_verified_profile(access_token)
  end

  # Native app flow: the LINE SDK returns the access token through the OS app
  # channel. The profile is fetched server-side with the token — client-sent
  # profile data is never trusted.
  def native
    profile = verified_native_profile(params[:access_token])

    if profile
      sign_in_with_verified_profile(profile)
    else
      redirect_to new_user_session_path, alert: "LINE authentication failed."
    end
  end

  private

  def sign_in_with_verified_profile(profile_or_token)
    profile = profile_or_token.is_a?(Hash) ? profile_or_token : fetch_profile(profile_or_token)

    if profile.nil?
      redirect_to new_user_session_path, alert: "LINE authentication failed: Could not fetch profile."
      return
    end

    user = User.from_line_auth(profile)
    user.remember_me = true
    sign_in(user)
    redirect_to root_path, notice: "Successfully logged in with LINE."
  end

  # Verifies the access token against LINE's API (token belongs to our channel
  # and has not expired), then returns the profile it resolves to.
  def verified_native_profile(access_token)
    return nil if access_token.blank? || ENV["LINE_CHANNEL_ID"].blank?

    verify_uri = URI("#{LINE_TOKEN_VERIFY_URL}?access_token=#{CGI.escape(access_token)}")
    verification = JSON.parse(Net::HTTP.get(verify_uri))
    return nil unless verification["client_id"] == ENV["LINE_CHANNEL_ID"]
    return nil if verification["expires_in"].to_i <= 0

    fetch_profile(access_token)
  rescue => e
    Rails.logger.warn "LINE native token verification failed: #{e.class}: #{e.message}"
    nil
  end

  def exchange_code_for_token(code)
    uri = URI(LINE_TOKEN_URL)
    response = Net::HTTP.post_form(uri, {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: line_login_callback_url,
      client_id: ENV["LINE_CHANNEL_ID"],
      client_secret: ENV["LINE_CHANNEL_SECRET"]
    })

    result = JSON.parse(response.body)
    result["access_token"]
  rescue => e
    Rails.logger.error "LINE token exchange error: #{e.message}"
    nil
  end

  def fetch_profile(access_token)
    uri = URI(LINE_PROFILE_URL)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{access_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    JSON.parse(response.body)
  rescue => e
    Rails.logger.error "LINE profile fetch error: #{e.message}"
    nil
  end
end

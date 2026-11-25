class Users::SessionsController < Devise::SessionsController
  include AuthRateLimited

  # Slows password guessing.
  rate_limit_auth to: 10, within: 3.minutes

  before_action :set_remember_me_for_native_app, only: [ :create ]

  private

  def set_remember_me_for_native_app
    if hotwire_native_app? && params[:user]
      params[:user][:remember_me] = "1"
    end
  end
end

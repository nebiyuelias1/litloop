class Users::RegistrationsController < Devise::RegistrationsController
  include AuthRateLimited

  # Each sign-up sends a confirmation email.
  rate_limit_auth to: 5, within: 15.minutes

  protected

  # Unconfirmed accounts land on sign in, beside the "check your email" notice.
  def after_inactive_sign_up_path_for(resource)
    new_user_session_path
  end

  private

  def sign_up_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def account_update_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :current_password, :avatar_url)
  end
end

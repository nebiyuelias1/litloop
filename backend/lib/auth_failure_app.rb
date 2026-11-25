# Skips Devise's "You need to sign in" flash in the native apps: they load
# every tab at launch, so the Profile tab's redirect would flash on the tour.
class AuthFailureApp < Devise::FailureApp
  NATIVE_APP = /(Turbo|Hotwire) Native/

  protected

  def is_flashing_format?
    super && !(sign_in_required? && NATIVE_APP.match?(request.user_agent.to_s))
  end

  # No warden message (e.g. `authenticate :user` routes) means :unauthenticated.
  def sign_in_required?
    (warden_message || :unauthenticated) == :unauthenticated
  end
end

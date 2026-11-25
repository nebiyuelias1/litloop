class Users::PasswordsController < Devise::PasswordsController
  include AuthRateLimited

  # Each request sends an email.
  rate_limit_auth to: 5, within: 15.minutes
end

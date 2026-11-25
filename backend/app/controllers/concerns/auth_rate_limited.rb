# Per-IP limits on sign in and the account forms that send email.
module AuthRateLimited
  extend ActiveSupport::Concern

  # nil means Rails.cache; tests set a real store (the test cache is a no-op).
  mattr_accessor :store

  # rate_limit captures its store at class load; this looks it up per request.
  module StoreProxy
    def self.increment(...) = (AuthRateLimited.store || Rails.cache).increment(...)
  end

  class_methods do
    def rate_limit_auth(to:, within:)
      rate_limit to: to, within: within, only: :create, store: StoreProxy, with: -> { auth_rate_limited }
    end
  end

  private

  def auth_rate_limited
    redirect_to url_for(action: :new), alert: t("auth.rate_limited")
  end
end

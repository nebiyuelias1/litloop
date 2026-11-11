# frozen_string_literal: true

# Per-user monthly budget for Otari-powered AI features.
#
# Every Otari call the app makes on a user's behalf is metered as an
# OtariUsage row. Club owners get a monthly unit quota — enforced at the
# trigger point (BookClubsController#generate_dna) and re-checked inside
# BookClubDnaJob so an enqueue/execute race can't overspend. Site admins are
# exempt from the quota but still metered; system-triggered usage (user: nil,
# e.g. admin-initiated enrichment) is allowed and metered too.
#
# Quota configuration:
#   ENV["OTARI_MONTHLY_QUOTA"]            — default quota for everyone
#   users.otari_monthly_quota             — per-user override (nil = default)
class OtariBudget
  FEATURES = %w[dna_generation book_enrichment cover_improvement].freeze

  # Unit cost per feature against the monthly quota.
  UNIT_COSTS = {
    "dna_generation" => 1,
    "book_enrichment" => 1,
    "cover_improvement" => 1
  }.freeze

  class << self
    # Default monthly quota, configurable per deployment.
    def default_monthly_quota
      Integer(ENV.fetch("OTARI_MONTHLY_QUOTA", 5))
    rescue ArgumentError, TypeError
      DEFAULT_FALLBACK_QUOTA
    end

    # Effective monthly quota for a user; per-user override wins.
    def monthly_quota(user)
      return default_monthly_quota if user.blank?

      user.otari_monthly_quota || default_monthly_quota
    end

    def units_used_this_month(user)
      return 0 if user.blank?

      OtariUsage.where(user_id: user.id, created_at: month_start..).sum(:cost)
    end

    def remaining(user)
      [ monthly_quota(user) - units_used_this_month(user), 0 ].max
    end

    # Whether the user may spend one unit of the feature right now.
    def allow?(user, feature: "dna_generation")
      return true if user.blank? || user.admin?

      remaining(user) >= UNIT_COSTS.fetch(feature, 1)
    end

    # Records one metered use. Metering must never break the main flow —
    # failures are logged and swallowed.
    def record!(user:, feature:, club: nil, model: nil, tokens: nil)
      usage = (tokens || {}).stringify_keys
      OtariUsage.create!(
        user: user,
        book_club: club,
        feature: feature,
        model: model,
        cost: UNIT_COSTS.fetch(feature, 1),
        input_tokens: usage["input_tokens"].to_i,
        output_tokens: usage["output_tokens"].to_i,
        total_tokens: usage["total_tokens"].to_i
      )
    rescue StandardError => e
      Rails.logger.warn("OtariBudget metering failed (#{feature}): #{e.class} #{e.message}")
      nil
    end

    private

    def month_start
      Time.current.beginning_of_month
    end
  end

  DEFAULT_FALLBACK_QUOTA = 5
  private_constant :DEFAULT_FALLBACK_QUOTA
end

# One metered use of an Otari-powered AI feature. Created by OtariBudget
# after a gateway call on a user's behalf; the monthly budget is the sum of
# this table's `cost` column for the current calendar month.
class OtariUsage < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :book_club, optional: true

  validates :feature, presence: true, inclusion: { in: OtariBudget::FEATURES }
end

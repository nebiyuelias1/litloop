class Poll < ApplicationRecord
  belongs_to :book_read

  # The option the organizer selected when finalizing; set from finalize → select_book.
  # Legacy polls finalized before this column exist get away with none.
  belongs_to :selected_poll_option, class_name: "PollOption", optional: true

  has_many :poll_options, dependent: :destroy
  has_many :poll_votes, through: :poll_options

  accepts_nested_attributes_for :poll_options, allow_destroy: true, reject_if: :all_blank

  validates :text, presence: true
  validates :end_date, presence: true
  validate :must_have_at_least_two_options

  def active?
    return false if finalized_at.present?
    end_date.nil? || end_date.future?
  end

  def winning_options
    options_with_counts = poll_options.left_joins(:poll_votes).group("poll_options.id").select("poll_options.*, COUNT(poll_votes.id) AS votes_count")
    max_votes = options_with_counts.map { |o| o.votes_count }.max
    options_with_counts.select { |o| o.votes_count == max_votes }
  end

  private

  def must_have_at_least_two_options
    if poll_options.reject(&:marked_for_destruction?).length < 2
      errors.add(:base, "must have at least two options")
    end
  end
end

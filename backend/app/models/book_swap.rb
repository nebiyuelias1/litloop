# A book trade/swap meetup: members bring books to give away or trade instead of
# reading one chosen title. Sits beside Poll as an alternative to a fixed book.
class BookSwap < ApplicationRecord
  belongs_to :book_read

  validates :title, presence: true
  validates :book_read_id, uniqueness: true, allow_nil: true
  validate :book_read_has_no_book_or_poll

  private

  # Saving through the session form already checks this on BookRead; this covers
  # swaps attached directly (e.g. from the admin dashboard).
  def book_read_has_no_book_or_poll
    return if book_read.blank?

    poll = book_read.poll
    if book_read.book_id.present? || (poll.present? && !poll.destroyed? && !poll.marked_for_destruction?)
      errors.add(:book_read, "already has a book or a poll")
    end
  end
end

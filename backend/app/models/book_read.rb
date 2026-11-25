class BookRead < ApplicationRecord
  belongs_to :book, optional: true
  belongs_to :book_club
  belongs_to :host, class_name: "User"

  has_one :poll, dependent: :destroy
  has_one :book_swap, dependent: :destroy
  has_many :discussion_questions, dependent: :destroy
  has_many :book_read_rsvps, dependent: :destroy
  has_many :rsvp_users, through: :book_read_rsvps, source: :user

  accepts_nested_attributes_for :poll, reject_if: :all_blank
  accepts_nested_attributes_for :book_swap, reject_if: :all_blank

  validates :meetup_time, presence: true
  validates :meetup_location, presence: true
  validates :max_capacity, numericality: { only_integer: true, greater_than_or_equal_to: 2 }, allow_nil: true
  validates :host, presence: true

  validate :has_exactly_one_selection
  validate :meetup_time_cannot_be_in_the_past, if: :will_save_change_to_meetup_time?

  def swap?
    book_swap.present? && !book_swap.marked_for_destruction?
  end

  # "book", "poll" or "swap". Chosen when the session is scheduled and fixed after that.
  def selection_type
    if swap?
      "swap"
    elsif poll.present?
      "poll"
    else
      "book"
    end
  end

  # Headline for the session: the chosen book, the poll question, or the swap's name.
  def display_title(fallback = I18n.t("new_reading_session"))
    book&.title.presence || poll&.text.presence || book_swap&.title.presence || fallback
  end

  # One-line summary under a swap's title: the host's guidelines, else the generic tagline.
  def swap_summary
    book_swap&.guidelines.to_s.squish.presence || I18n.t("swap_subtitle")
  end

  def can_post_discussion_question?(user)
    return false if user.blank? || swap?

    rsvp_users.exists?(id: user.id)
  end

  def full?
    max_capacity.present? && book_read_rsvps.going.count >= max_capacity
  end

  def visible_discussion_questions_for(user)
    questions = discussion_questions.includes(:question_translations)
    if user&.admin? || book_club.owner == user || book_club.book_club_members.exists?(user: user, role: :admin)
      questions.order(:position)
    else
      visible = questions.revealed
      visible = visible.or(questions.where(user: user)) if user
      visible.order(:position)
    end
  end

  CALENDAR_UPDATE_TRIGGER_ATTRIBUTES = %w[meetup_location meetup_time].freeze

  before_save :increment_calendar_sequence, if: :schedule_changed?
  after_commit :queue_schedule_update_invite, on: :update, if: :saved_change_to_schedule?

  private

  def schedule_changed?
    persisted? && CALENDAR_UPDATE_TRIGGER_ATTRIBUTES.any? { |attr| attribute_changed?(attr) }
  end

  def saved_change_to_schedule?
    CALENDAR_UPDATE_TRIGGER_ATTRIBUTES.any? { |attr| saved_change_to_attribute?(attr) }
  end

  def increment_calendar_sequence
    latest_seq = self.class.where(id: id).lock.pick(:calendar_sequence) || calendar_sequence || 0
    self.calendar_sequence = latest_seq + 1
  end

  def queue_schedule_update_invite
    delay = ENV.fetch("BOOK_READ_UPDATE_DEBOUNCE_MINUTES", 10).to_i.minutes
    SendBookReadInviteJob.set(wait: delay).perform_later(id, calendar_sequence)
  end

  # A session is either a fixed book, a poll to pick one, or a book swap.
  # A poll keeps its record once it picks a book, so book + poll is allowed.
  def has_exactly_one_selection
    has_poll = poll.present? && !poll.marked_for_destruction?
    # book covers an assigned but unsaved Book, which has no book_id yet
    has_book = book_id.present? || book.present?

    if swap?
      errors.add(:base, "A book swap can't also have a book or a poll") if has_book || has_poll
    elsif !has_book && !has_poll
      errors.add(:base, "You must select a specific book, create a poll, or set up a book swap for this session")
    end
  end

  def meetup_time_cannot_be_in_the_past
    if meetup_time.present? && meetup_time < Time.current
      errors.add(:meetup_time, "cannot be in the past")
    end
  end
end

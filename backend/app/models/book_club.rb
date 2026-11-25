require "uri"

class BookClub < ApplicationRecord
  belongs_to :owner, class_name: "User", optional: true

  has_one_attached :cover_photo
  has_one_attached :photo

  def name_initial
    name.presence&.strip&.first&.upcase || "B"
  end

  has_many :book_reads, dependent: :destroy
  has_many :books, through: :book_reads
  has_many :book_club_members, dependent: :destroy
  has_many :members, through: :book_club_members, source: :user
  has_many :membership_requests, dependent: :destroy

  # SQL form of private_info_visible_to?.
  scope :visible_to, ->(user) {
    clubs = where(is_private: false)
    next clubs unless user

    clubs.or(where(owner: user)).or(where(id: BookClubMember.where(user: user).select(:book_club_id)))
  }

  scope :by_relevance, -> {
    now = connection.quote(Time.current)
    recent_window_start = connection.quote(90.days.ago)
    order(Arel.sql(<<~SQL.squish))
      (
        book_clubs.book_club_members_count
        /* Use higher weight for upcoming reads */
        + 3 * (
          SELECT COUNT(*) FROM book_reads
          WHERE book_reads.book_club_id = book_clubs.id
            AND book_reads.meetup_time >= #{now}
        )
        /* Past book reads are a good signal but lower weight */
        + 1 * (
          SELECT COUNT(*) FROM book_reads
          WHERE book_reads.book_club_id = book_clubs.id
            AND book_reads.meetup_time >= #{recent_window_start}
            AND book_reads.meetup_time < #{now}
        )
      ) DESC, book_clubs.created_at DESC
    SQL
  }

  MAX_PHOTO_SIZE = 5.megabytes
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/jpg image/png image/webp image/gif].freeze

  validates :name, presence: true
  validates :application_form_url, presence: true, if: :is_private?
  validate :application_form_url_is_valid
  validate :acceptable_photo

  after_create :add_owner_as_admin

  def has_member?(user)
    return false unless user

    book_club_members.exists?(user: user)
  end

  def private_info_visible_to?(user)
    !is_private || (user.present? && (owner == user || has_member?(user)))
  end

  def pending_request_from?(user)
    return false unless user

    membership_requests.exists?(user: user, status: :pending)
  end

  def pending_membership_requests
    membership_requests.where(status: :pending).includes(:user)
  end

  private

  def application_form_url_is_valid
    return if application_form_url.blank?

    begin
      uri = URI.parse(application_form_url)
    rescue URI::InvalidURIError
      errors.add(:application_form_url, "must be a valid URL starting with http:// or https://")
      return
    end

    unless uri.is_a?(URI::HTTP) && uri.host.present?
      errors.add(:application_form_url, "must be a valid URL starting with http:// or https://")
    end
  end

  def acceptable_photo
    return unless photo.attached?

    if photo.content_type == "image/svg+xml" || photo.filename.to_s.downcase.end_with?(".svg")
      errors.add(:photo, "cannot be an SVG file for security reasons")
      return
    end

    unless ALLOWED_PHOTO_TYPES.include?(photo.content_type)
      errors.add(:photo, "must be a JPEG, PNG, WEBP, or GIF image")
      return
    end

    if photo.blob.byte_size > MAX_PHOTO_SIZE
      errors.add(:photo, "is too large (maximum size is 5MB)")
    end
  end

  def add_owner_as_admin
    if owner.present?
      book_club_members.create!(user: owner, role: :admin)
    end
  end
end

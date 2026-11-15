class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable, :confirmable

  has_many :ratings, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :review_likes, dependent: :destroy
  has_many :owned_book_clubs, class_name: "BookClub", foreign_key: "owner_id", dependent: :nullify
  has_many :book_read_rsvps, dependent: :destroy
  has_many :rsvp_book_reads, through: :book_read_rsvps, source: :book_read

  before_validation :normalize_name

  validates :name, presence: true

  def self.from_telegram_auth(auth)
    user = where(telegram_id: auth["id"]).first_or_initialize do |u|
      u.password = Devise.friendly_token[0, 20]
      # TODO: Find ways of getting email address
      u.email = "#{auth["id"]}@telegram.com"
      u.skip_confirmation!
    end
    user.name = [ auth["first_name"], auth["last_name"] ].join(" ").strip
    user.username = auth["username"]
    user.avatar_url = auth["photo_url"] if auth["photo_url"].present?
    user.telegram_id = auth["id"]
    user.save!
    user
  end

  # Sign-up/login via Telegram Login (OIDC id_token claims). Matches existing
  # users on telegram_id, the same id the legacy widget reported.
  def self.from_oidc(claims)
    telegram_id = claims["id"] || claims["sub"]
    given_name = claims["given_name"] || claims["name"].to_s.split(" ").first.to_s
    family_name = claims["family_name"] || claims["name"].to_s.split(" ").drop(1).join(" ")
    user = where(telegram_id: telegram_id).first_or_initialize do |u|
      u.password = Devise.friendly_token[0, 20]
      # TODO: Find ways of getting email address
      u.email = "#{telegram_id}@telegram.com"
      u.skip_confirmation!
    end
    user.name = [ given_name, family_name ].join(" ").strip
    user.username = claims["preferred_username"]
    user.avatar_url = claims["picture"] if claims["picture"].present?
    user.telegram_id = telegram_id
    user.save!
    user
  end

  def self.from_line_auth(auth)
    user = where(line_id: auth["userId"]).first_or_initialize do |u|
      u.password = Devise.friendly_token[0, 20]
      u.email = "#{auth["userId"]}@line.com"
      u.skip_confirmation!
    end
    user.name = auth["displayName"]
    user.username = auth["displayName"]
    user.avatar_url = auth["pictureUrl"] if auth["pictureUrl"].present?
    user.line_id = auth["userId"]
    user.save!
    user
  end

  def to_s
    name.presence || username.presence || anonymized_email || "Unknown"
  end

  def anonymized_email
    return nil if email.blank?
    user_part, domain_part = email.split("@")
    return email if domain_part.blank?

    if user_part.length <= 1
      "*@#{domain_part}"
    elsif user_part.length == 2
      "#{user_part[0]}*@#{domain_part}"
    else
      "#{user_part[0]}***#{user_part[-1]}@#{domain_part}"
    end
  end

  def name_initial
    (name.presence || username.presence || "U").strip.first.upcase
  end

  private

  def normalize_name
    self.name = name.to_s.strip.presence
  end
end

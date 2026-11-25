class UserMailer < ApplicationMailer
  default from: "#{Rails.configuration.x.app_name} <noreply@#{Rails.configuration.x.mail_from_domain}>" # this domain must be verified with Resend

  before_action :set_rsvp_params, only: [ :rsvp_confirmation, :book_read_updated_invite, :book_read_reminder_email ]
  before_action :set_membership_request_params, only: [ :membership_request_notification, :membership_request_decision ]

  def rsvp_confirmation
    attach_calendar_invite!
    mail(to: @user.email, subject: "RSVP Confirmation: #{(@book_read.book&.title || @book_read.book_swap&.title || "Book Read")}")
  end

  def book_read_updated_invite
    attach_calendar_invite!(description_suffix: " (Schedule Updated)")
    mail(to: @user.email, subject: "[Updated Calendar Invite] Book Read: #{(@book_read.book&.title || @book_read.book_swap&.title || "Book Read")}")
  end

  def book_read_reminder_email
    mail(to: @user.email, subject: "Reminder: Upcoming Book Read for #{(@book_read.book&.title || @book_read.book_swap&.title || "Discussion")}")
  end

  def membership_request_notification
    mail(to: @owner.email, subject: "New Join Request: #{@book_club.name}")
  end

  def membership_request_decision
    subject =
      if @membership_request.approved?
        "Join Request Approved: #{@book_club.name}"
      else
        "Join Request Rejected: #{@book_club.name}"
      end
    mail(to: @requesting_user.email, subject: subject)
  end

  private

  def set_rsvp_params
    @rsvp = params[:rsvp]
    @user = @rsvp.user
    @book_read = @rsvp.book_read
    @time_zone = params[:time_zone] || "Taipei"
  end

  def set_membership_request_params
    @membership_request = params[:membership_request]
    @book_club = @membership_request.book_club
    @owner = @book_club.owner
    @requesting_user = @membership_request.user
  end

  def attach_calendar_invite!(description_suffix: nil)
    mail_domain = Rails.configuration.x.mail_from_domain
    organizer_email = "noreply@#{mail_domain}"

    cal = Icalendar::Calendar.new
    cal.ip_method = "REQUEST"
    cal.event do |e|
      e.uid = calendar_event_uid
      e.sequence = @book_read.calendar_sequence || 0
      e.organizer = Icalendar::Values::CalAddress.new("mailto:#{organizer_email}", cn: Rails.configuration.x.app_name)
      e.attendee = [ Icalendar::Values::CalAddress.new("mailto:#{@user.email}", cn: @user.name) ]
      # Explicitly marking as UTC ensures calendars auto-adjust to user's local time
      e.dtstart = Icalendar::Values::DateTime.new(@book_read.meetup_time.utc, tzid: "UTC")
      e.dtend = Icalendar::Values::DateTime.new((@book_read.meetup_time + 2.hours).utc, tzid: "UTC")
      e.summary = "Book Read: #{(@book_read.book&.title || @book_read.book_swap&.title || "Discussion")}"
      e.description = "RSVP for #{@book_read.book_club.name}#{description_suffix}"
      e.location = @book_read.meetup_location
      e.ip_class = "PRIVATE"
      e.status = "CONFIRMED"
    end

    attachments["invite.ics"] = {
      mime_type: "text/calendar; method=REQUEST",
      content: cal.to_ical
    }
  end

  def calendar_event_uid
    mail_domain = Rails.configuration.x.mail_from_domain
    "book-read-#{@book_read.id}-rsvp-#{@rsvp.id}@#{mail_domain}"
  end
end

module ClubHelper
  # Human label for the signed-in viewer's relationship to a club.
  # Returns nil when the viewer is not signed in or not a member, so callers
  # can skip rendering a status badge entirely.
  def club_member_role_label(club, user)
    return nil unless user

    membership = club.book_club_members.find_by(user: user)
    return nil unless membership
    return "Owner" if club.owner_id == user.id

    membership.admin? ? "Admin" : "Member"
  end

  # Whether the viewer can edit a reading session. Mirrors the controller's
  # authorize_club_owner! check, plus the host of the read.
  def can_manage_book_read?(club, book_read, user)
    return false unless user
    return true if book_read.host_id == user.id

    club.owner_id == user.id || club.book_club_members.exists?(user: user, role: :admin)
  end

  # Short human hint for a meetup time, e.g. "In 18 days • Saturday Afternoon".
  def relative_meetup_hint(time)
    return if time.blank?

    days = (time.to_date - Time.zone.today).to_i
    phrase =
      if days.zero?
        t("today")
      elsif days == 1
        t("tomorrow")
      elsif days.positive?
        t("in_days", count: days)
      else
        t("days_ago", count: days.abs)
      end

    period = if time.hour < 12
      t("morning")
    elsif time.hour < 17
      t("afternoon")
    else
      t("evening")
    end

    "#{phrase} • #{I18n.t("date.day_names")[time.wday]} #{period}"
  end

  # URL for adding the book read meetup to Google Calendar.
  def google_calendar_url(book_read, book_club)
    return nil unless book_read&.meetup_time

    title = book_read.book&.title || book_read.poll&.text || "Book Club Meetup"
    details = "Book Club Meetup with #{book_club.name}. #{book_club_book_read_url(book_club, book_read)}"
    location = book_read.meetup_location.presence || ""
    start_time = book_read.meetup_time.utc.strftime("%Y%m%dT%H%M%SZ")
    end_time = (book_read.meetup_time + 2.hours).utc.strftime("%Y%m%dT%H%M%SZ")

    query = {
      action: "TEMPLATE",
      text: "#{book_club.name}: #{title}",
      dates: "#{start_time}/#{end_time}",
      details: details,
      location: location
    }.to_query

    "https://calendar.google.com/calendar/render?#{query}"
  end
end

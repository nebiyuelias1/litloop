require "test_helper"

class BookClubTest < ActiveSupport::TestCase
  test "automatically adds owner as admin upon creation" do
    owner = users(:one)

    club = BookClub.create!(
      name: "Test Club",
      owner: owner
    )

    membership = club.book_club_members.find_by(user: owner)

    assert_not_nil membership, "Owner should have a membership record"
    assert membership.admin?, "Owner should have the admin role"
  end

  test "rejects photo with invalid content type" do
    owner = users(:one)
    club = BookClub.new(name: "Invalid Type Club", owner: owner)

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("some file content"),
      filename: "document.pdf",
      content_type: "application/pdf"
    )
    club.photo.attach(blob)

    assert_not club.valid?
    assert_includes club.errors[:photo], "must be a JPEG, PNG, WEBP, or GIF image"
  end

  test "explicitly rejects SVG photo for security reasons" do
    owner = users(:one)
    club = BookClub.new(name: "SVG Club", owner: owner)

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("<svg></svg>"),
      filename: "logo.svg",
      content_type: "image/svg+xml"
    )
    club.photo.attach(blob)

    assert_not club.valid?
    assert_includes club.errors[:photo], "cannot be an SVG file for security reasons"
  end

  test "rejects photo exceeding maximum byte size" do
    owner = users(:one)
    club = BookClub.new(name: "Large Photo Club", owner: owner)

    oversized_data = "x" * (5.megabytes + 100)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(oversized_data),
      filename: "huge.jpg",
      content_type: "image/jpeg"
    )
    club.photo.attach(blob)

    assert_not club.valid?
    assert_includes club.errors[:photo], "is too large (maximum size is 5MB)"
  end

  test "accepts valid JPEG or PNG photo within size limits" do
    owner = users(:one)
    club = BookClub.new(name: "Valid Photo Club", owner: owner)

    valid_data = "fake image bytes"
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(valid_data),
      filename: "avatar.png",
      content_type: "image/png"
    )
    club.photo.attach(blob)

    assert club.valid?
  end

  test "accepts a valid application form URL" do
    club = BookClub.new(name: "Form Club", application_form_url: "https://docs.google.com/forms/d/abc123")
    assert club.valid?
  end

  test "rejects hostless application form URLs" do
    club = BookClub.new(name: "Bad Host Club", application_form_url: "https://?")
    assert_not club.valid?
    assert_includes club.errors[:application_form_url], "must be a valid URL starting with http:// or https://"

    club.application_form_url = "http://#"
    assert_not club.valid?
    assert_includes club.errors[:application_form_url], "must be a valid URL starting with http:// or https://"
  end

  test "rejects non-HTTP application form URLs" do
    club = BookClub.new(name: "FTP Club", application_form_url: "ftp://example.com")
    assert_not club.valid?
    assert_includes club.errors[:application_form_url], "must be a valid URL starting with http:// or https://"
  end

  test "allows blank application form URL" do
    club = BookClub.new(name: "No URL Club", application_form_url: "")
    assert club.valid?
  end

  test "owner can see private info even without a membership row" do
    club = book_clubs(:one)
    club.update!(is_private: true, application_form_url: "https://example.com/form")
    club.book_club_members.find_by(user: club.owner)&.destroy!

    assert club.private_info_visible_to?(club.owner)
  end

  test "by_relevance ranks clubs with more members and upcoming reads first" do
    quiet_club = BookClub.create!(name: "Quiet Club")
    small_club = BookClub.create!(name: "Small Club", owner: users(:one))
    active_club = BookClub.create!(name: "Active Club", owner: users(:two))
    active_club.book_club_members.create!(user: users(:three))
    active_club.book_reads.create!(host: users(:two), book: books(:one), meetup_time: 2.weeks.from_now, meetup_location: "Active Cafe")

    ranked_ids = BookClub.by_relevance.map(&:id)

    assert ranked_ids.index(active_club.id) < ranked_ids.index(small_club.id),
           "Club with more members and an upcoming read should rank higher than a smaller club"
    assert ranked_ids.index(small_club.id) < ranked_ids.index(quiet_club.id),
           "Club with one member should rank higher than an empty club"
  end

  test "by_relevance ignores meetups that have already happened" do
    stale_club = BookClub.create!(name: "Stale Club", owner: users(:one))
    travel_to 3.weeks.ago do
      stale_club.book_reads.create!(host: users(:one), book: books(:one), meetup_time: 1.week.from_now, meetup_location: "Old Cafe")
    end

    fresh_club = BookClub.create!(name: "Fresh Club", owner: users(:two))
    fresh_club.book_reads.create!(host: users(:two), book: books(:two), meetup_time: 1.week.from_now, meetup_location: "New Cafe")

    ranked_ids = BookClub.by_relevance.map(&:id)

    assert ranked_ids.index(fresh_club.id) < ranked_ids.index(stale_club.id),
           "Club with an upcoming read should rank higher than a club whose only read is in the past"
  end

  test "by_relevance breaks score ties with the newest club first" do
    older_club = BookClub.create!(name: "Older Club", owner: users(:one), created_at: 3.days.ago)
    newer_club = BookClub.create!(name: "Newer Club", owner: users(:two), created_at: 1.day.ago)

    assert_equal [ newer_club.id, older_club.id ],
                 BookClub.by_relevance.where(id: [ older_club.id, newer_club.id ]).map(&:id)
  end

  test "by_relevance credits a club that met recently even with nothing scheduled" do
    recently_active_club = BookClub.create!(name: "Recently Active Club", owner: users(:one))
    travel_to 3.weeks.ago do
      recently_active_club.book_reads.create!(host: users(:one), book: books(:one), meetup_time: 1.week.from_now, meetup_location: "Old Cafe")
    end
    idle_club = BookClub.create!(name: "Idle Club", owner: users(:two))

    ranked_ids = BookClub.by_relevance.map(&:id)

    assert ranked_ids.index(recently_active_club.id) < ranked_ids.index(idle_club.id),
           "Club that met within the last 90 days should outrank a newer idle club with the same member count"
  end

  test "by_relevance does not credit meetups older than 90 days" do
    ancient_club = BookClub.create!(name: "Ancient Club", owner: users(:one))
    travel_to 6.months.ago do
      ancient_club.book_reads.create!(host: users(:one), book: books(:one), meetup_time: 1.week.from_now, meetup_location: "Very Old Cafe")
    end
    idle_club = BookClub.create!(name: "Idle Club", owner: users(:two))

    ranked_ids = BookClub.by_relevance.map(&:id)

    assert ranked_ids.index(idle_club.id) < ranked_ids.index(ancient_club.id),
           "Meetups older than 90 days should earn no credit, so the newer idle club should win the tiebreak"
  end

  test "member can see private info and non-member or anonymous user cannot" do
    club = book_clubs(:one)
    club.update!(is_private: true, application_form_url: "https://example.com/form")
    member = users(:two)
    club.book_club_members.create!(user: member)
    outsider = users(:three)

    assert club.private_info_visible_to?(member)
    assert_not club.private_info_visible_to?(outsider)
    assert_not club.private_info_visible_to?(nil)
  end

  test "visible_to matches private_info_visible_to?" do
    club = book_clubs(:one)
    club.update!(is_private: true, application_form_url: "https://example.com/form")
    club.book_club_members.find_by(user: club.owner)&.destroy!
    club.book_club_members.create!(user: users(:two))

    [ club.owner, users(:two), users(:three), nil ].each do |user|
      assert_equal club.private_info_visible_to?(user), BookClub.visible_to(user).include?(club),
                   "mismatch for #{user&.email || 'a guest'}"
    end
    assert_includes BookClub.visible_to(nil), book_clubs(:two)
  end
end

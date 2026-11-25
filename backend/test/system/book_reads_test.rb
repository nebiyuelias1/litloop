require "application_system_test_case"

class BookReadsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @book_club = book_clubs(:one)
    Book.rebuild_search_index
    login_as @user
  end

  test "toggling between book and poll selection in book read form" do
    visit new_book_club_book_read_path(@book_club)

    assert_selector "h1", text: "Schedule a Book Read"

    # Default state (Book Selection)
    assert_selector "#book_selection_field", visible: true
    assert_no_selector "#poll_fields", visible: true

    # Toggle to Poll
    find("[data-book-read-form-target='selectionBtn']", text: "Poll").click
    assert_no_selector "#book_selection_field", visible: true
    assert_selector "#poll_fields", visible: true
    # Check for simplified event fields
    assert_selector "label", text: "Meetup Time"
    assert_selector "label", text: "Meetup Location"

    # Toggle back to Book
    find("[data-book-read-form-target='selectionBtn']", text: "Specific Book").click

    assert_selector "#book_selection_field", visible: true
    assert_no_selector "#poll_fields", visible: true
  end

  test "creating a book read with a specific book" do
    book = books(:one)
    visit new_book_club_book_read_path(@book_club)

    # Search for and select a book
    fill_in "book_search_input", with: book.title
    # Wait for autocomplete and click the first matching result
    assert_selector "[data-book-autocomplete-target='results'] div", text: book.title, wait: 5
    find("[data-book-autocomplete-target='results'] div", text: book.title, match: :first).click

    pick_datetime "Meetup Time", 1.week.from_now, hour: 15, minute: 30
    fill_in "Meetup Location", with: "Starbucks"

    click_on "Schedule Read"

    assert_text "Book read scheduled successfully"
    assert_text book.title
  end

  test "showing errors when creating a book read without a book or poll" do
    visit new_book_club_book_read_path(@book_club)

    pick_datetime "Meetup Time", 1.week.from_now, hour: 15, minute: 30
    fill_in "Meetup Location", with: "Starbucks"

    click_on "Schedule Read"

    assert_text "You must select a specific book, create a poll, or set up a book swap for this session"
  end

  test "creating a book read via a poll with options" do
    visit new_book_club_book_read_path(@book_club)

    # Toggle to Poll
    find("[data-book-read-form-target='selectionBtn']", text: "Poll").click

    fill_in "Poll Question", with: "What should we read next?"
    pick_datetime "Voting Ends On", 3.days.from_now, hour: 23, minute: 55

    # Add Poll Options
    within "#poll_options" do
      # Enter first option
      within ".poll-option-field:nth-child(1)" do
        fill_in "Enter book title or search...", with: "The Great Gatsby"
      end

      # Enter second option
      within ".poll-option-field:nth-child(2)" do
        fill_in "Enter book title or search...", with: "1984"
      end

      click_button "Add Another Option"

      # Enter third option
      within ".poll-option-field:nth-child(3)" do
        fill_in "Enter book title or search...", with: "Brave New World"
      end
    end

    pick_datetime "Meetup Time", 1.week.from_now, hour: 15, minute: 30
    fill_in "Meetup Location", with: "Public Library"

    click_on "Schedule Read"

    assert_text "Book read scheduled successfully"
    assert_text "What should we read next?"
    assert_text "The Great Gatsby"
    assert_text "1984"
    assert_text "Brave New World"
    assert_text "Public Library"
    assert_text "Voting ends on"
  end

  test "selection type persists after validation error" do
    visit new_book_club_book_read_path(@book_club)

    # Toggle to Poll
    find("[data-book-read-form-target='selectionBtn']", text: "Poll").click
    assert_selector "#poll_fields", visible: true

    # Fill some fields but miss a required one (meetup_time)
    fill_in "Poll Question", with: "Incomplete Poll"
    fill_in "Meetup Location", with: "Nowhere"

    click_on "Schedule Read"

    # Should show error
    assert_text "prohibited this book read from being saved"

    # Selection should still be Poll
    assert_selector "#poll_fields", visible: true
    assert_no_selector "#book_selection_field", visible: true

    # The Poll radio should be checked
    assert find("input[name='selection_type'][value='poll']", visible: false).checked?
  end

  test "shows finalize poll button when poll expired and not finalized" do
    poll = polls(:two)
    book_read = poll.book_read
    book_club = book_read.book_club
    poll.poll_options.build(content: "Option A")
    poll.poll_options.build(content: "Option B")
    poll.save!
    poll.update!(end_date: 1.days.ago, finalized_at: nil)

    login_as book_club.owner
    visit book_club_book_read_path(book_club, book_read)

    assert_selector "a", text: "Finalize Poll"
  end

  test "showing errors when creating a poll without options" do
    visit new_book_club_book_read_path(@book_club)

    # Toggle to Poll
    find("[data-book-read-form-target='selectionBtn']", text: "Poll").click

    fill_in "Poll Question", with: "Poll with no options"
    pick_datetime "Voting Ends On", 3.days.from_now, hour: 23, minute: 55

    pick_datetime "Meetup Time", 1.week.from_now, hour: 15, minute: 30
    fill_in "Meetup Location", with: "Public Library"

    # Ensure options are empty (they shouldn't be by default as we build 2, but let's assume we remove them or they are blank)
    # Our form builds 2 empty ones by default, so if we leave them blank they should be rejected by reject_if: :all_blank

    click_on "Schedule Read"

    assert_text "must have at least two options"
  end

  test "editing an existing book read with past poll end date allows submit" do
    book_read = book_reads(:one)
    Poll.create!(
      book_read: book_read,
      text: "Pick the next read",
      end_date: 1.day.ago,
      poll_options_attributes: [ { content: "Option 1" }, { content: "Option 2" } ]
    )

    visit edit_book_club_book_read_path(@book_club, book_read)
    fill_in "Meetup Location", with: "Updated Meetup Spot"

    click_on "Schedule Read"

    assert_text "Book read was successfully updated."
    assert_text "Updated Meetup Spot"
  end

  private

  def pick_datetime(label, target, hour:, minute:)
    fieldset = find("fieldset[data-controller='date-picker']", text: label)
    fieldset.find("div[data-action='click->date-picker#togglePopover']").click

    target_month = target.strftime("%B %Y")
    until fieldset.find("[data-date-picker-target='monthYear']").text == target_month
      fieldset.find("[data-action='click->date-picker#nextMonth']").click
    end

    fieldset.find("[data-date-picker-target='daysGrid'] button[data-day='#{target.day}']").click

    if fieldset.has_selector?("[data-date-picker-target='hourSelect']", visible: true)
      fieldset.find("[data-date-picker-target='hourSelect']").select(hour.to_s.rjust(2, "0"))
      fieldset.find("[data-date-picker-target='minuteSelect']").select(minute.to_s.rjust(2, "0"))
      fieldset.find("div[data-action='click->date-picker#togglePopover']").click
    end
  end

  test "creating a book swap shows it on the session and club pages" do
    visit new_book_club_book_read_path(@book_club)

    find("[data-book-read-form-target='selectionBtn']", text: "Book Swap").click
    assert_selector "#book_swap_fields", visible: true
    assert_no_selector "#book_selection_field", visible: true
    assert_no_selector "#poll_fields", visible: true

    fill_in "Swap Name", with: "December Book Swap"
    fill_in "Swap Guidelines", with: "Bring 1–3 books in good condition."
    pick_datetime "Meetup Time", 1.week.from_now, hour: 15, minute: 30
    fill_in "Meetup Location", with: "Tomoca Coffee"

    click_on "Schedule Read"

    assert_text "Book read scheduled successfully"
    assert_selector "h1", text: "December Book Swap"
    assert_text "Bring 1–3 books in good condition."
    assert_no_selector "#discussion_section"

    visit book_club_path(@book_club)
    assert_text "December Book Swap"
  end
end

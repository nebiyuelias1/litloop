require "test_helper"

class BookReadTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @book = books(:one)
    @club = book_clubs(:one)
    @book_read = BookRead.new(
      book: @book,
      book_club: @club,
      host: users(:one),
      meetup_time: 1.week.from_now,
      meetup_location: "Vino Vino Cafe"
    )
  end

  test "should be valid with valid attributes" do
    assert @book_read.valid?
  end

  test "should require a book" do
    @book_read.book = nil
    assert_not @book_read.valid?
  end

  test "should not require a poll" do
    @book_read.poll = nil
    assert @book_read.valid?
  end

  test "should allow having a poll" do
    @book_read.save!
    poll = @book_read.build_poll(
      text: "What to read?",
      end_date: 1.days.from_now,
      poll_options_attributes: [
        { content: "Book A" },
        { content: "Book B" }
      ]
    )
    assert poll.valid?, poll.errors.full_messages.to_sentence
  end

  test "should require a book_club" do
    @book_read.book_club = nil
    assert_not @book_read.valid?
  end

  test "should require a meetup time" do
    @book_read.meetup_time = nil
    assert_not @book_read.valid?
  end

  test "should not allow meetup_time in the past" do
    @book_read.meetup_time = 1.day.ago
    assert_not @book_read.valid?
    assert_includes @book_read.errors[:meetup_time], "cannot be in the past"
  end

  test "should allow meetup_time in the future" do
    @book_read.meetup_time = 1.day.from_now
    assert @book_read.valid?
  end

  test "should require a host" do
    @book_read.host = nil
    assert_not @book_read.valid?
  end

  test "should allow nil max_capacity" do
    @book_read.max_capacity = nil
    assert @book_read.valid?
  end

  test "should allow max_capacity of 2" do
    @book_read.max_capacity = 2
    assert @book_read.valid?
  end

  test "should not allow max_capacity below 2" do
    @book_read.max_capacity = 1
    assert_not @book_read.valid?
  end

  test "calendar_sequence defaults to 0 on creation" do
    @book_read.save!
    assert_equal 0, @book_read.calendar_sequence
  end

  test "updating meetup_location increments calendar_sequence and enqueues job" do
    @book_read.save!
    assert_enqueued_with(job: SendBookReadInviteJob, args: [ @book_read.id, 1 ]) do
      @book_read.update!(meetup_location: "New Room 101")
    end
    assert_equal 1, @book_read.calendar_sequence
  end

  test "updating meetup_time increments calendar_sequence and enqueues job" do
    @book_read.save!
    new_time = 2.weeks.from_now
    assert_enqueued_with(job: SendBookReadInviteJob, args: [ @book_read.id, 1 ]) do
      @book_read.update!(meetup_time: new_time)
    end
    assert_equal 1, @book_read.calendar_sequence
  end

  test "updating non-schedule attributes does not increment calendar_sequence or enqueue job" do
    @book_read.save!
    assert_no_enqueued_jobs(only: SendBookReadInviteJob) do
      @book_read.update!(max_capacity: 10)
    end
    assert_equal 0, @book_read.calendar_sequence
  end

  test "concurrent schedule updates atomically increment calendar_sequence without collision" do
    @book_read.save!
    latch = Queue.new
    exceptions = Queue.new

    threads = 5.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          read = BookRead.find(@book_read.id)
          latch.pop # Pause until released simultaneously
          read.update!(meetup_location: "Concurrent Room #{i}")
        end
      rescue => e
        exceptions.push(e)
      end
    end

    # Bounded wait until all 5 threads are ready at the barrier
    50.times do
      break if latch.num_waiting >= 5
      sleep 0.02
    end
    assert_equal 5, latch.num_waiting, "Worker threads failed to reach the barrier in time"

    # Release all 5 threads simultaneously
    5.times { latch.push(true) }
    threads.each(&:join)

    raise exceptions.pop unless exceptions.empty?

    @book_read.reload
    assert_equal 5, @book_read.calendar_sequence
  end

  test "is valid as a book swap with no book or poll" do
    @book_read.book = nil
    @book_read.build_book_swap(title: "December Book Swap")
    assert @book_read.valid?
    assert @book_read.swap?
  end

  test "is invalid as a book swap that also has a book" do
    @book_read.build_book_swap(title: "December Book Swap")
    assert_not @book_read.valid?
    assert_includes @book_read.errors[:base], "A book swap can't also have a book or a poll"
  end

  test "is invalid as a book swap that also has a poll" do
    @book_read.book = nil
    @book_read.build_book_swap(title: "December Book Swap")
    @book_read.build_poll(text: "Which?", end_date: 1.day.from_now,
      poll_options_attributes: [ { content: "A" }, { content: "B" } ])
    assert_not @book_read.valid?
  end

  test "is invalid with no book, poll or swap" do
    @book_read.book = nil
    assert_not @book_read.valid?
    assert_includes @book_read.errors[:base],
      "You must select a specific book, create a poll, or set up a book swap for this session"
  end

  test "display_title prefers book, then poll text, then swap title" do
    assert_equal @book.title, @book_read.display_title

    swap_read = book_reads(:swap)
    assert_equal "December Book Swap", swap_read.display_title

    @book_read.book = nil
    assert_equal "Fallback", @book_read.display_title("Fallback")
  end

  test "swap_summary uses the host's guidelines, squished" do
    swap = book_reads(:swap)
    swap.book_swap.guidelines = "Bring 1–3 books.\n\nLeftovers get donated."
    assert_equal "Bring 1–3 books. Leftovers get donated.", swap.swap_summary
  end

  test "swap_summary falls back to the tagline without guidelines" do
    swap = book_reads(:swap)
    swap.book_swap.guidelines = ""
    assert_equal I18n.t("swap_subtitle"), swap.swap_summary
  end

  test "nobody can post discussion questions on a swap" do
    swap = book_reads(:swap)
    BookReadRsvp.rsvp!(book_read: swap, user: users(:one), status: :going)
    assert_not swap.can_post_discussion_question?(users(:one))
  end
end

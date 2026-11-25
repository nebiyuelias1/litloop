require "test_helper"

class BookSwapTest < ActiveSupport::TestCase
  test "requires a title" do
    swap = BookSwap.new(book_read: book_reads(:swap))
    assert_not swap.valid?
    assert_includes swap.errors[:title], "can't be blank"
  end

  test "fixture is valid" do
    assert book_swaps(:one).valid?
  end

  test "cannot attach to a session that already has a book" do
    swap = BookSwap.new(book_read: book_reads(:two), title: "Swap")
    assert_not swap.valid?
    assert_includes swap.errors[:book_read], "already has a book or a poll"
  end

  test "a session can only have one swap" do
    swap = BookSwap.new(book_read: book_reads(:swap), title: "Second swap")
    assert_not swap.valid?
    assert_includes swap.errors[:book_read_id], "has already been taken"
  end

  test "cannot attach to a session with an unsaved book assigned" do
    book_read = book_reads(:swap)
    book_read.book = Book.new(title: "Unsaved")
    swap = BookSwap.new(book_read: book_read, title: "Swap")
    assert_not swap.valid?
    assert_includes swap.errors[:book_read], "already has a book or a poll"
  end

  test "a bookless session can still take a swap" do
    book_read = BookRead.new(book_club: book_clubs(:one), host: users(:one),
      meetup_time: 1.week.from_now, meetup_location: "Cafe")
    swap = book_read.build_book_swap(title: "Swap")
    assert swap.valid?
    assert book_read.valid?
  end
end

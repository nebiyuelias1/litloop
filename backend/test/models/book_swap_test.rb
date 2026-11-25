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
end

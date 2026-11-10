require "test_helper"

class BookTest < ActiveSupport::TestCase
  def setup
    Book.rebuild_search_index
  end

  test "books_fts virtual table exists" do
    sql_query = <<-SQL
      SELECT name FROM sqlite_master WHERE type='table' AND name='books_fts'
    SQL

    result = ActiveRecord::Base.connection.execute(sql_query)
    assert result.any?, "books_fts virtual table should exist"
  end

  test "should not save book without title" do
    book = Book.new(author: "Test Author")
    assert_not book.save, "Saved the book without a title"
  end

  test "books_fts is automatically populated on book creation" do
    book = Book.create!(
      title: "Test FTS Book",
      author: "Test Author",
      description: "A book for testing full-text search functionality"
    )

    result = ActiveRecord::Base.connection.execute(
      "SELECT rowid FROM books_fts WHERE books_fts MATCH 'Test'"
    )

    assert result.any?, "New book should be indexed in books_fts"

    book.destroy
  end

  test "books_fts is updated when book is updated" do
    book = Book.create!(
      title: "Original Title",
      author: "Original Author",
      description: "Original description"
    )

    book.update!(title: "Updated Unique Title")

    result = ActiveRecord::Base.connection.execute(
      "SELECT rowid FROM books_fts WHERE books_fts MATCH 'Updated Unique'"
    )

    assert result.any?, "Updated book should be searchable in books_fts"

    book.destroy
  end

  test "books_fts is cleaned up when book is deleted" do
    book = Book.create!(
      title: "Book to Delete",
      author: "Delete Author",
      description: "This book will be deleted"
    )

    book_id = book.id

    result = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([ "SELECT rowid FROM books_fts WHERE rowid = ?", book_id ])
    )
    assert result.any?, "Book should be in books_fts before deletion"

    book.destroy

    result = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([ "SELECT rowid FROM books_fts WHERE rowid = ?", book_id ])
    )

    assert_empty result, "Deleted book should be removed from books_fts"
  end

  test "full-text search works on multiple columns" do
    book1 = Book.create!(
      title: "Ruby Programming",
      author: "Test Author",
      description: "Learn Ruby programming language"
    )

    book2 = Book.create!(
      title: "Python Guide",
      author: "Ruby Smith",
      description: "Python programming guide"
    )

    result = Book.full_text_search("Ruby")

    rowids = result.map { |row| row.id }

    assert_includes rowids, book1.id, "Should find book with Ruby in title"
    assert_includes rowids, book2.id, "Should find book with Ruby in author"

    book1.destroy
    book2.destroy
  end

  test "use full text search for searching book" do
    books = Book.full_text_search("ለምትኬ")
    assert_includes books.pluck(:title), "ለምትኬ"
    assert_includes books.pluck(:author), "ደረጀ ለማ ደገፉ"

    books = Book.full_text_search("lamtké")
    assert_includes books.pluck(:title), "ለምትኬ"
    assert_includes books.pluck(:author), "ደረጀ ለማ ደገፉ"

    # TODO: Search using romanization
    # might need to standardize the romanization of amharic
    # books = Book.full_text_search("lemetke")
    # assert_includes books.pluck(:title), "ለምትኬ"
    # assert_includes books.pluck(:author), "ደረጀ ለማ ደገፉ"
  end

  test "rejects invalid country_of_origin codes" do
    book = Book.new(title: "Test Book", author: "Test Author", country_of_origin: "XX")
    assert_not book.valid?
    assert_includes book.errors[:country_of_origin], "is not a valid ISO 3166-1 alpha-2 code"

    book = Book.new(title: "Test Book", author: "Test Author", country_of_origin: "Nigeria")
    assert_not book.valid?, "names must not be stored; only ISO alpha-2 codes"
    book = Book.new(title: "Test Book", author: "Test Author", country_of_origin: "NG")
    assert book.valid?
  end

  test "enrichment attributes are accessible" do
    book = Book.new(
      title: "Things Fall Apart",
      author: "Chinua Achebe",
      country_of_origin: "NG",
      enriched_at: nil
    )

    assert_equal "NG", book.country_of_origin
    assert_nil book.enriched_at

    book.save!
    assert_nil Book.find(book.id).enriched_at, "enriched_at should default to nil (not yet enriched)"

    book.update!(enriched_at: Time.current)
    assert_not_nil Book.find(book.id).enriched_at

    book.destroy
  end
end

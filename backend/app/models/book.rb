class Book < ApplicationRecord
  validates :title, presence: true
  validates :author, presence: true
  validates :country_of_origin,
    inclusion: { in: ->(_) { CountryCodes::CODES }, message: "is not a valid ISO 3166-1 alpha-2 code" },
    allow_nil: true

  has_many :book_tags, dependent: :destroy
  has_many :tags, through: :book_tags
  has_many :ratings, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :book_reads, dependent: :destroy
  has_many :book_clubs, through: :book_reads

  after_create_commit :create_in_book_fts
  # after_create_commit  :create_telegram_discussion
  after_update_commit :update_in_book_fts
  after_destroy_commit :remove_from_book_fts

  scope :full_text_search, ->(query) do
    joins("join books_fts idx on books.id = idx.rowid")
      .where("books_fts match ?", sanitize_fts_query(query))
      .order(:rank)
  end

  def self.sanitize_fts_query(query)
    return "" if query.blank?
    # Escape existing double quotes and wrap the whole thing in double quotes
    # to handle special characters like apostrophes.
    # We add a * at the end for prefix matching as before.
    "\"#{query.gsub('"', '""')}\"*"
  end

  def self.rebuild_search_index
    sql_query = <<-SQL
        insert into books_fts (
          books_fts
        )
       values ('rebuild')
    SQL
    connection.execute sql_query
  end

  def average_rating
    ratings.average(:score)&.round(1) || 0
  end

  def user_rating(user)
    ratings.find_by(user: user)
  end

  private

  def create_in_book_fts
    sql_query = <<-SQL
        insert into books_fts (
          rowid,
          title,
          author,
          description,
          publisher,
          title_en,
          title_romanized,
          author_romanized
        )
       values (?, ?, ?, ?, ?, ?, ?, ?)
    SQL

    execute_sql_with_binds sql_query,
      id, title, author, description,
      publisher, title_en, title_romanized, author_romanized
  end

  def update_in_book_fts
    transaction do
      remove_from_book_fts
      create_in_book_fts
    end
  end

  def remove_from_book_fts
    sql_query = <<-SQL
        insert into books_fts (
          books_fts,
          rowid,
          title,
          author,
          description,
          publisher,
          title_en,
          title_romanized,
          author_romanized
        )
        values ('delete', ?, ?, ?, ?, ?, ?, ?, ?)
    SQL

    execute_sql_with_binds sql_query,
      id_previously_was,
      title_previously_was,
      author_previously_was,
      description_previously_was,
      publisher_previously_was,
      title_en_previously_was,
      title_romanized_previously_was,
      author_romanized_previously_was
  end

  def execute_sql_with_binds(*statement)
    self.class.connection.execute self.class.sanitize_sql(statement)
  end

  def create_telegram_discussion
    return if telegram_post_id.present?

    message_id = TelegramService.new(self).publish
    update_column(:telegram_post_id, message_id) if message_id
  end
end

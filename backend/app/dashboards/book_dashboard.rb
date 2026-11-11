require "administrate/base_dashboard"

class BookDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    title: Field::String,
    author: Field::String,
    author_romanized: Field::String,
    average_rating: Field::Number.with_options(decimals: 2),
    book_clubs: Field::HasMany,
    book_reads: Field::HasMany,
    book_tags: Field::HasMany,
    cover_image: Field::String,
    country_of_origin: Field::String,
    description: Field::Text,
    enriched_at: Field::DateTime,
    isbn: Field::String,
    language: Field::String,
    page_count: Field::Number,
    published_at: Field::Date,
    publisher: Field::String,
    ratings: Field::HasMany,
    reviews: Field::HasMany,
    reviews_count: Field::Number,
    source: Field::String,
    source_url: Field::String,
    tags: Field::HasMany,
    telegram_post_id: Field::String,
    title_en: Field::String,
    title_romanized: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    title
    author
    language
    average_rating
    reviews_count
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    title
    author
    author_romanized
    average_rating
    reviews_count
    description
    cover_image
    country_of_origin
    isbn
    language
    page_count
    published_at
    publisher
    tags
    book_clubs
    created_at
    enriched_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    title
    author
    author_romanized
    description
    cover_image
    isbn
    language
    page_count
    published_at
    publisher
    country_of_origin
    tags
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how books are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(book)
    "#{book.title} by #{book.author}"
  end
end

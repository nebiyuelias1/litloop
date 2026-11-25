require "administrate/base_dashboard"

class BookSwapDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    book_read: Field::BelongsTo,
    title: Field::String,
    guidelines: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    book_read
    title
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    book_read
    title
    guidelines
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    book_read
    title
    guidelines
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(book_swap)
    book_swap.title
  end
end

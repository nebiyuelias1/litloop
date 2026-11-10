class AddAiMetadataFieldsToBooks < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :country_of_origin, :string
    add_column :books, :enriched_at, :datetime
  end
end

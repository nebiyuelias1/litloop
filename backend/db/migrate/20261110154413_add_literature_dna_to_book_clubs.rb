class AddLiteratureDnaToBookClubs < ActiveRecord::Migration[8.0]
  def change
    add_column :book_clubs, :literature_dna, :json
    add_column :book_clubs, :dna_generated_at, :datetime
  end
end

class CreateBookSwaps < ActiveRecord::Migration[8.0]
  def change
    create_table :book_swaps do |t|
      t.references :book_read, null: false, foreign_key: true, index: { unique: true }
      t.string :title, null: false
      t.text :guidelines

      t.timestamps
    end
  end
end

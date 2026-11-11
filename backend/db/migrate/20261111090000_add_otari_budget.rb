class AddOtariBudget < ActiveRecord::Migration[8.0]
  def change
    # Metering ledger: one row per Otari-powered AI run, attributed to the
    # user who triggered it (nil user = system-triggered). Costs are unit
    # costs against the owner's monthly quota; token counts are the raw
    # gateway usage when reported.
    create_table :otari_usages do |t|
      t.references :user, foreign_key: true
      t.references :book_club, foreign_key: true
      t.string :feature, null: false
      t.string :model
      t.integer :cost, default: 1, null: false
      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.integer :total_tokens, default: 0, null: false
      t.datetime :created_at, null: false
    end
    add_index :otari_usages, :feature
    add_index :otari_usages, :created_at

    # Per-user monthly quota override (nil = use the default quota).
    add_column :users, :otari_monthly_quota, :integer
  end
end

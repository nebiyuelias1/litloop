class CreateTelegramSignInNonces < ActiveRecord::Migration[8.0]
  def change
    create_table :telegram_sign_in_nonces do |t|
      t.string :nonce, null: false
      t.timestamps
    end
    add_index :telegram_sign_in_nonces, :nonce, unique: true
  end
end

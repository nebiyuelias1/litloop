class AddSelectedPollOptionToPolls < ActiveRecord::Migration[8.0]
  def change
    add_reference :polls, :selected_poll_option, null: true,
      foreign_key: { to_table: :poll_options }
  end
end

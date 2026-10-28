class CreateScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :scheduled_messages do |t|
      t.references :account, null: false, foreign_key: true
      # Nullable so a conversation destroy can nullify the reference and the executor can
      # fail the row terminal (conversation_gone) instead of orphaning it.
      t.references :conversation, null: true, foreign_key: true
      t.text :content, null: false
      t.datetime :scheduled_at, null: false
      t.text :internal_note
      t.integer :status, null: false, default: 0
      t.integer :retry_count, null: false, default: 0
      t.integer :max_retries, null: false, default: 3
      t.references :message, null: true, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.datetime :sent_at
      t.text :error

      t.timestamps
    end
    add_index :scheduled_messages, [:status, :scheduled_at]
  end
end

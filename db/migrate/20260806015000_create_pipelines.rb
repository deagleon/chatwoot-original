class CreatePipelines < ActiveRecord::Migration[7.1]
  def change
    create_table :pipelines do |t|
      t.references :account, null: false
      t.string :name, null: false
      t.datetime :archived_at
      t.timestamps
    end
    add_index :pipelines, :archived_at
  end
end

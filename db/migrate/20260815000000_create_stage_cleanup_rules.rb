class CreateStageCleanupRules < ActiveRecord::Migration[7.1]
  def change
    create_table :stage_cleanup_rules do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :pipeline_stage, null: false, foreign_key: { on_delete: :cascade }
      t.string :cleanup_time, null: false
      t.boolean :active, null: false, default: true
      t.date :last_run_on

      t.timestamps
    end
  end
end

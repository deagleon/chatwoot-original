class AddPipelineStageToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :pipeline_stage_id, :bigint
    add_column :conversations, :pipeline_stage_changed_at, :datetime
    add_index :conversations, :pipeline_stage_id
  end
end

class BackfillCaptainAssistantResponsesKnowledgeColumns < ActiveRecord::Migration[7.0]
  def up
    add_column :captain_assistant_responses, :question, :string unless column_exists?(:captain_assistant_responses, :question)
    add_column :captain_assistant_responses, :answer, :text unless column_exists?(:captain_assistant_responses, :answer)
    add_column :captain_assistant_responses, :embedding, :vector, limit: 1536 unless column_exists?(:captain_assistant_responses, :embedding)
    add_column :captain_assistant_responses, :assistant_id, :bigint unless column_exists?(:captain_assistant_responses, :assistant_id)
    add_column :captain_assistant_responses, :documentable_type, :string unless column_exists?(:captain_assistant_responses, :documentable_type)
    add_column :captain_assistant_responses, :documentable_id, :bigint unless column_exists?(:captain_assistant_responses, :documentable_id)

    add_index :captain_assistant_responses, :assistant_id, if_not_exists: true
    add_index :captain_assistant_responses, %i[documentable_id documentable_type],
              name: 'idx_cap_asst_resp_on_documentable', if_not_exists: true
    add_index :captain_assistant_responses, :embedding, using: :ivfflat, name: 'vector_idx_knowledge_entries_embedding',
              opclass: :vector_l2_ops, if_not_exists: true
  end

  def down
    remove_index :captain_assistant_responses, name: 'vector_idx_knowledge_entries_embedding' if index_exists?(:captain_assistant_responses, :embedding, name: 'vector_idx_knowledge_entries_embedding')
    remove_index :captain_assistant_responses, name: 'idx_cap_asst_resp_on_documentable' if index_exists?(:captain_assistant_responses, %i[documentable_id documentable_type], name: 'idx_cap_asst_resp_on_documentable')
    remove_index :captain_assistant_responses, :assistant_id if index_exists?(:captain_assistant_responses, :assistant_id)
    remove_column :captain_assistant_responses, :documentable_id if column_exists?(:captain_assistant_responses, :documentable_id)
    remove_column :captain_assistant_responses, :documentable_type if column_exists?(:captain_assistant_responses, :documentable_type)
    remove_column :captain_assistant_responses, :assistant_id if column_exists?(:captain_assistant_responses, :assistant_id)
    remove_column :captain_assistant_responses, :embedding if column_exists?(:captain_assistant_responses, :embedding)
    remove_column :captain_assistant_responses, :answer if column_exists?(:captain_assistant_responses, :answer)
    remove_column :captain_assistant_responses, :question if column_exists?(:captain_assistant_responses, :question)
  end
end

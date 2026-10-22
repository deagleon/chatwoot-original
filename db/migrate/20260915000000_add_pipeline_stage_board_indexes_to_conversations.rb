class AddPipelineStageBoardIndexesToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Board de pipelines: toda query é account-scoped (base_relation) + filtro
    # por stage + ordenação por last_activity_at (default) ou
    # pipeline_stage_changed_at (FIFO). Sem compostos, cada coluna varre o
    # índice simples de pipeline_stage_id + sort em memória — crítico em
    # contas com milhares de conversas por stage.
    add_index :conversations, [:account_id, :pipeline_stage_id, :last_activity_at, :id],
              name: 'index_conversations_on_stage_last_activity',
              algorithm: :concurrently,
              if_not_exists: true
    add_index :conversations, [:account_id, :pipeline_stage_id, :pipeline_stage_changed_at],
              name: 'index_conversations_on_stage_changed_at',
              algorithm: :concurrently,
              if_not_exists: true
  end
end

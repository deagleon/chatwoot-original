class AddTrelloSyncFields < ActiveRecord::Migration[7.1]
  def change
    add_column :pipelines, :trello_board_id, :string
    add_column :pipeline_stages, :trello_list_id, :string
    add_column :conversations, :trello_card_id, :string

    add_index :pipelines, %i[account_id trello_board_id],
              name: 'index_pipelines_on_account_id_and_trello_board_id', unique: true, where: 'trello_board_id IS NOT NULL'
    add_index :pipeline_stages, %i[pipeline_id trello_list_id],
              name: 'index_pipeline_stages_on_pipeline_id_and_trello_list_id', unique: true, where: 'trello_list_id IS NOT NULL'
    add_index :conversations, %i[account_id trello_card_id],
              name: 'index_conversations_on_account_id_and_trello_card_id', unique: true, where: 'trello_card_id IS NOT NULL'
  end
end

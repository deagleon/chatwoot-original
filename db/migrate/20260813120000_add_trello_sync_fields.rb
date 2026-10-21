class AddTrelloSyncFields < ActiveRecord::Migration[7.1]
  # if_not_exists: this migration was renumbered from 20260813000000, so databases that
  # already applied it under the old version must be able to run it again safely.
  def change
    add_column :pipelines, :trello_board_id, :string, if_not_exists: true
    add_column :pipeline_stages, :trello_list_id, :string, if_not_exists: true
    add_column :conversations, :trello_card_id, :string, if_not_exists: true

    add_index :pipelines, %i[account_id trello_board_id],
              name: 'index_pipelines_on_account_id_and_trello_board_id', unique: true, where: 'trello_board_id IS NOT NULL',
              if_not_exists: true
    add_index :pipeline_stages, %i[pipeline_id trello_list_id],
              name: 'index_pipeline_stages_on_pipeline_id_and_trello_list_id', unique: true, where: 'trello_list_id IS NOT NULL',
              if_not_exists: true
    add_index :conversations, %i[account_id trello_card_id],
              name: 'index_conversations_on_account_id_and_trello_card_id', unique: true, where: 'trello_card_id IS NOT NULL',
              if_not_exists: true
  end
end

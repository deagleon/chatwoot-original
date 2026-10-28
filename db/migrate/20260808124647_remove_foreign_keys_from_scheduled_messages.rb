class RemoveForeignKeysFromScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    # A tabela não usa FKs de banco — igual às demais tabelas de negócio (o ARPE, por
    # exemplo) — e os FKs NO ACTION originais quebravam a deleção de usuário (created_by),
    # de conta e o cascade de destroy das messages. A integridade fica no modelo
    # (dependent: :nullify em Conversation) e no fluxo de deleção existente.
    # if_exists: bancos carregados via schema (sem FKs) não podem falhar aqui.
    remove_foreign_key :scheduled_messages, :accounts, if_exists: true
    remove_foreign_key :scheduled_messages, :conversations, if_exists: true
    remove_foreign_key :scheduled_messages, :messages, if_exists: true
    remove_foreign_key :scheduled_messages, :users, column: :created_by_id, if_exists: true
  end
end

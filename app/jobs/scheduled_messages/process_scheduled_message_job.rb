class ScheduledMessages::ProcessScheduledMessageJob < ApplicationJob
  include Events::Types

  queue_as :high

  # At-most-once: o claim é atômico; executing só existe dentro da transação que
  # commita sent; um retry pós-commit encontra o estado terminal e não recria.
  def perform(scheduled_message_id)
    scheduled_message = ScheduledMessage.find_by(id: scheduled_message_id)
    return if scheduled_message.nil?

    # 1. Claim atômico; claim perdido (corrida com o sweep ou reclaim) encerra sem ação.
    return unless scheduled_message.claim!

    # 2. Re-check pós-claim: conversa inexistente é falha terminal direta, sem retry.
    conversation = scheduled_message.conversation
    unless conversation
      scheduled_message.fail_terminal!('conversation_gone')
      return
    end

    begin
      execute(scheduled_message, conversation)
    rescue StandardError => e
      handle_creation_failure(scheduled_message, e)
    end
  end

  private

  def execute(scheduled_message, conversation)
    scheduled_message.with_lock do
      scheduled_message.update!(status: :executing)

      # Conversa resolvida no fire-time: reabre na MESMA transação que cria a Message;
      # um rollback da criação também desfaz a reabertura (D9). Nunca toggle manual —
      # isso seria um segundo toggle além dos callbacks da Message.
      conversation.open! if conversation.resolved?

      # Criação única da Message; após o commit, os callbacks reais de
      # Message#after_create_commit rodam — eventos e o único send_reply →
      # SendReplyJob. Nunca chamar message.send_reply aqui.
      message = Messages::MessageBuilder.new(
        scheduled_message.created_by,
        conversation,
        {
          content: scheduled_message.content,
          message_type: 'outgoing',
          content_attributes: { scheduled_message_id: scheduled_message.id }
        }
      ).perform

      # Liga message_id e commita terminal na mesma transação.
      scheduled_message.update!(message: message, status: :sent, sent_at: Time.current)
    end

    # Pós-commit: o realtime só é emitido com o sent já persistido.
    Rails.configuration.dispatcher.dispatch(SCHEDULED_MESSAGE_UPDATED, Time.zone.now, scheduled_message: scheduled_message)
  end

  # Falha ANTES do commit da Message (validação/flooding do MessageBuilder, rollback
  # sem Message persistida): retries limitados. O lock! do with_lock recarrega a row —
  # a transação de execução reverteu o status para processing no banco, e o objeto em
  # memória ainda carregava o status da tentativa que falhou.
  def handle_creation_failure(scheduled_message, error)
    ChatwootExceptionTracker.new(error, account: scheduled_message.account).capture_exception

    scheduled_message.with_lock do
      next unless scheduled_message.processing?

      new_retry_count = scheduled_message.retry_count + 1
      if new_retry_count < scheduled_message.max_retries
        scheduled_message.update!(status: :pending, retry_count: new_retry_count, error: nil)
      else
        scheduled_message.update!(status: :failed, retry_count: new_retry_count, error: error.message)
      end
    end

    # Pós-commit: reflete no realtime o retorno a pending ou a falha terminal.
    Rails.configuration.dispatcher.dispatch(SCHEDULED_MESSAGE_UPDATED, Time.zone.now, scheduled_message: scheduled_message)
  end
end

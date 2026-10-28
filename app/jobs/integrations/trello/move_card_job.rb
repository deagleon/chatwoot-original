# frozen_string_literal: true

class Integrations::Trello::MoveCardJob < ApplicationJob
  queue_as :medium

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    card_id = conversation.trello_card_id
    stage = conversation.pipeline_stage
    return if card_id.blank? || stage.blank? || stage.trello_list_id.blank?

    hook = find_hook(conversation, stage)
    return if hook.blank?

    move_card(hook, conversation, card_id, stage.trello_list_id)
  end

  private

  def find_hook(conversation, stage)
    pipeline = stage.pipeline
    return if pipeline.blank? || pipeline.trello_board_id.blank?

    hook = conversation.account.hooks.find_by(app_id: 'trello', reference_id: pipeline.trello_board_id)
    return if hook.blank? || hook.disabled?

    hook
  end

  def move_card(hook, conversation, card_id, list_id)
    client = Trello.new(api_key: hook.settings['api_key'], token: hook.access_token)
    client.move_card(card_id, list_id)
  rescue Trello::ApiError => e
    if e.status == 404
      # The card was deleted while disconnected; drop the stale link instead
      # of retrying forever.
      conversation.update!(trello_card_id: nil)
      Rails.logger.info("Trello: card #{card_id} not found; unlinked conversation #{conversation.id}")
      return
    end
    if e.status == 401
      hook.disable
      Rails.logger.error("Trello: disabling hook #{hook.id} after 401")
    end
    raise
  end
end

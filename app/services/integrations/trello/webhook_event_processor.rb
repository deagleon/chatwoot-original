class Integrations::Trello::WebhookEventProcessor
  pattr_initialize [:hook!, :payload!]

  ACTION_HANDLERS = {
    'createCard' => :handle_create_card,
    'updateCard' => :handle_update_card,
    'deleteCard' => :handle_delete_card,
    'commentCard' => :handle_comment_card,
    'createList' => :handle_create_list,
    'updateList' => :handle_update_list,
    'updateBoard' => :handle_update_board,
    'deleteBoard' => :handle_delete_board
  }.freeze

  def perform
    action = payload['action']
    return if action.blank? || board_mismatch?(action)

    handle_action(action)
  end

  private

  def board_mismatch?(action)
    board_id = action.dig('data', 'board', 'id')
    return false if board_id.blank? || board_id == hook.reference_id

    Rails.logger.warn("Trello: webhook board #{board_id} does not match hook #{hook.id}")
    true
  end

  def handle_action(action)
    handler = ACTION_HANDLERS[action['type']]
    return if handler.blank?

    send(handler, action)
  end

  def handle_create_card(action)
    card_id = action.dig('data', 'card', 'id')
    list = action.dig('data', 'list')
    return if card_id.blank? || list.blank?

    full_card = fetch_card(card_id)
    stage = Integrations::Trello::StageSyncService.new(pipeline: pipeline, list: list).perform
    return if stage.blank?

    Integrations::Trello::WhatsappConversationService.new(hook: hook, card: full_card, stage: stage).perform
  end

  def handle_update_card(action)
    card = action.dig('data', 'card')
    return if card.blank?

    conversation = hook.account.conversations.find_by(trello_card_id: card['id'])
    handle_card_change(action, conversation)
  end

  def handle_card_change(action, conversation)
    if action.dig('data', 'listAfter').present?
      handle_card_move(action, conversation) if conversation
    elsif action.dig('data', 'old').key?('closed')
      handle_card_closed_change(action, conversation)
    end
  end

  def handle_card_closed_change(action, conversation)
    return if conversation.blank?

    # A closed/archived card drops the conversation link but keeps the WhatsApp
    # conversation untouched; reopening the card does not re-link it.
    conversation.update!(trello_card_id: nil) if action.dig('data', 'old', 'closed') == false
  end

  def handle_card_move(action, conversation)
    list_after = action.dig('data', 'listAfter')
    stage = Integrations::Trello::StageSyncService.new(pipeline: pipeline, list: list_after).perform
    conversation.move_to_stage!(stage) unless conversation.pipeline_stage_id == stage.id
  end

  def handle_delete_card(action)
    card = action.dig('data', 'card')
    return if card.blank?

    conversation = hook.account.conversations.find_by(trello_card_id: card['id'])
    conversation&.update!(trello_card_id: nil)
  end

  def handle_comment_card(action)
    return if action.dig('memberCreator', 'id') == hook.settings['member_id']

    card_id = action.dig('data', 'card', 'id')
    return if card_id.blank?

    conversation = hook.account.conversations.find_by(trello_card_id: card_id)
    return if conversation.blank?

    # Card comments land as internal activity notes so agents see the context
    # without anything being sent to the customer on WhatsApp.
    Conversations::ActivityMessageJob.perform_later(
      conversation,
      {
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        message_type: :activity,
        content: I18n.t('conversations.activity.trello.card_comment_note', text: action.dig('data', 'text').to_s)
      }
    )
  end

  def handle_create_list(action)
    list = action.dig('data', 'list')
    return if list.blank?

    Integrations::Trello::StageSyncService.new(pipeline: pipeline, list: list).perform
  end

  def handle_update_list(action)
    list = action.dig('data', 'list')
    return if list.blank?

    if action.dig('data', 'old').key?('closed')
      return handle_list_closed(list) unless action.dig('data', 'old', 'closed')

      # List reopened: recreate the stage if it was destroyed on close.
      return Integrations::Trello::StageSyncService.new(pipeline: pipeline, list: list).perform
    end

    stage = pipeline.pipeline_stages.find_by(trello_list_id: list['id'])
    return unless stage

    stage.update!(name: list['name']) if action.dig('data', 'old', 'name').present?
  end

  def handle_list_closed(list)
    stage = pipeline.pipeline_stages.find_by(trello_list_id: list['id'])
    return if stage.blank?

    if stage.conversations.exists?
      Rails.logger.warn("Trello: list #{list['id']} closed but stage #{stage.id} has conversations; keeping stage")
    else
      stage.destroy!
    end
  end

  def handle_update_board(action)
    old = action.dig('data', 'old')
    return if old.blank? || !old.key?('closed')

    old['closed'] ? pipeline&.update!(archived_at: nil) : pipeline&.archive!
  end

  def handle_delete_board(_action)
    pipeline&.archive!
  end

  def fetch_card(card_id)
    client.card(card_id)
  rescue Trello::ApiError
    action = payload['action']
    action.dig('data', 'card')
  end

  def pipeline
    @pipeline ||= hook.account.pipelines.find_by(trello_board_id: hook.reference_id)
  end

  def client
    @client ||= Trello.new(api_key: hook.settings['api_key'], token: hook.access_token)
  end
end

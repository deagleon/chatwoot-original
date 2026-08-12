class Integrations::Trello::BackfillJob < ApplicationJob
  queue_as :low

  def perform(hook_id)
    hook = Integrations::Hook.find_by(id: hook_id)
    return if hook.blank? || hook.disabled?

    pipeline = hook.account.pipelines.find_by(trello_board_id: hook.settings['board_id'])
    return if pipeline.blank?

    client = Trello.new(api_key: hook.settings['api_key'], token: hook.access_token)
    board_id = hook.settings['board_id']
    list_names = client.board_lists(board_id).to_h { |list| [list['id'], list['name']] }

    client.open_cards(board_id).each do |card|
      hook = Integrations::Hook.find_by(id: hook.id)
      break if hook.blank? || hook.disabled?

      stage = Integrations::Trello::StageSyncService.new(
        pipeline: pipeline,
        list: { 'id' => card['idList'], 'name' => list_names[card['idList']] || card['idList'] }
      ).perform
      Integrations::Trello::WhatsappConversationService.new(hook: hook, card: card, stage: stage).perform
    end
  end
end

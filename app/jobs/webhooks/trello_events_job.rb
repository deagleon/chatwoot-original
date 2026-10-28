class Webhooks::TrelloEventsJob < ApplicationJob
  queue_as :medium

  def perform(hook_id, payload)
    hook = Integrations::Hook.find_by(id: hook_id)
    return if hook.blank? || hook.disabled?

    Integrations::Trello::WebhookEventProcessor.new(hook: hook, payload: payload).perform
  end
end

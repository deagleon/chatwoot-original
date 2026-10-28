class Webhooks::TrelloController < ActionController::API
  def process_payload
    hook = Integrations::Hook.where(app_id: 'trello')
                             .where("settings ->> 'webhook_secret' = ?", params[:webhook_secret])
                             .first
    return head :not_found unless hook

    return head :ok if request.head?

    # Trello payloads have a top-level `action` key that collides with the
    # Rails path parameter of the same name, so the body must be parsed raw.
    Webhooks::TrelloEventsJob.perform_later(hook.id, JSON.parse(request.raw_post))
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end

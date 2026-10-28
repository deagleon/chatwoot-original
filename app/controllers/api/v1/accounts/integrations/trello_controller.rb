class Api::V1::Accounts::Integrations::TrelloController < Api::V1::Accounts::Integrations::BaseController
  before_action :check_authorization, only: %i[create destroy]
  before_action :normalize_credentials, only: %i[boards create]

  NETWORK_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, SocketError, HTTParty::Error,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT
  ].freeze

  def boards
    # HookPolicy has no `boards?` predicate; listing boards is admin-only like hook creation.
    authorize(:hook, :create?)
    return render_missing_params unless required_params_present?(%w[api_key token])

    render json: client.boards
  rescue Trello::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    return render_missing_params unless required_params_present?(%w[api_key token board_id whatsapp_inbox_id])
    return render_duplicate_hook if duplicate_hook?
    return render_invalid_whatsapp_inbox if whatsapp_inbox.blank?

    @hook = create_hook_for_board
    register_remote_webhook
    Integrations::Trello::BackfillJob.perform_later(@hook.id)
  rescue Trello::ApiError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, *NETWORK_ERRORS => e
    cleanup_after_failed_create
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    hook = Current.account.hooks.find_by(app_id: 'trello', reference_id: params[:board_id])
    return render json: { error: 'Hook not found' }, status: :not_found if hook.blank?

    delete_remote_webhook(hook) if hook.settings['webhook_id'].present?
    # Destroy the hook before unlinking the pipeline so in-flight webhook jobs
    # no-op on the missing hook instead of hitting a nil pipeline.
    hook.destroy!
    unlink_pipeline
    head :ok
  end

  private

  def normalize_credentials
    # Pasted API keys/tokens often carry trailing whitespace, which Trello
    # rejects with "invalid app token".
    params[:api_key] = params[:api_key].to_s.strip
    params[:token] = params[:token].to_s.strip
  end

  def create_hook_for_board
    lists = fetch_open_lists
    webhook_secret = SecureRandom.hex(16)

    ActiveRecord::Base.transaction do
      create_pipeline(lists)
      create_hook(webhook_secret)
    end
  end

  def fetch_open_lists
    client.board_lists(params[:board_id]).reject { |list| list['closed'] }
  end

  def create_pipeline(lists)
    # Legacy connections may leave a pipeline still holding this board link
    # (archived under the old model); unlink it so the unique index on
    # (account_id, trello_board_id) never blocks a fresh connection.
    stale_pipeline = Current.account.pipelines.find_by(trello_board_id: params[:board_id])
    if stale_pipeline
      stale_pipeline.pipeline_stages.update_all(trello_list_id: nil)
      stale_pipeline.update!(trello_board_id: nil)
    end

    @created_pipeline = Current.account.pipelines.create!(
      name: board_name,
      trello_board_id: params[:board_id],
      pipeline_stages_attributes: lists.map.with_index do |list, index|
        { name: list['name'], color: stage_color(index), position: index + 1, trello_list_id: list['id'] }
      end
    )
  end

  def create_hook(webhook_secret)
    Current.account.hooks.create!(
      app_id: 'trello',
      reference_id: params[:board_id],
      access_token: params[:token],
      settings: {
        api_key: params[:api_key],
        board_id: params[:board_id],
        board_name: board_name,
        webhook_secret: webhook_secret,
        member_id: member_id,
        whatsapp_inbox_id: whatsapp_inbox.id.to_s
      }
    )
  end

  def unlink_pipeline
    pipeline = Current.account.pipelines.find_by(trello_board_id: params[:board_id])
    return if pipeline.blank?

    # Disconnecting keeps the pipeline and its WhatsApp conversations intact;
    # only the Trello mapping is dropped so the board can be reconnected later.
    pipeline.pipeline_stages.update_all(trello_list_id: nil)
    pipeline.update!(trello_board_id: nil)
  end

  def whatsapp_inbox
    @whatsapp_inbox ||= Current.account.inboxes.find_by(id: params[:whatsapp_inbox_id])
    return if @whatsapp_inbox.blank?

    @whatsapp_inbox if valid_whatsapp_inbox?(@whatsapp_inbox)
  end

  def valid_whatsapp_inbox?(inbox)
    inbox.whatsapp? || inbox.api? || inbox.twilio_whatsapp? ||
      # Registros legados de Twilio-WhatsApp podem ter medium sem o valor
      # esperado; o phone_number "whatsapp:+..." é o sinal mais confiável neles.
      (inbox.twilio? && inbox.channel.phone_number.to_s.starts_with?('whatsapp'))
  end

  def register_remote_webhook
    webhook = client.create_webhook(
      board_id: params[:board_id],
      callback_url: "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/webhooks/trello/#{@hook.settings['webhook_secret']}"
    )
    @hook.update!(settings: @hook.settings.merge('webhook_id' => webhook['id']))
  end

  def cleanup_after_failed_create
    @hook&.destroy!
    @created_pipeline&.destroy!
  end

  def delete_remote_webhook(hook)
    client = Trello.new(api_key: hook.settings['api_key'], token: hook.access_token)
    client.delete_webhook(hook.settings['webhook_id'])
  rescue Trello::ApiError => e
    Rails.logger.warn "Failed to delete Trello webhook #{hook.settings['webhook_id']}: #{e.message}"
  end

  def client
    @client ||= Trello.new(api_key: params[:api_key], token: params[:token])
  end

  def duplicate_hook?
    Current.account.hooks.exists?(app_id: 'trello', reference_id: params[:board_id])
  end

  def board_name
    @board_name ||= fetch_board_name
  end

  def fetch_board_name
    board = client.boards.find { |item| item['id'] == params[:board_id] }
    board ? board['name'] : params[:board_id]
  end

  def member_id
    @member_id ||= client.member_me['id']
  end

  def stage_color(index)
    colors = Integrations::Trello::StageSyncService::STAGE_COLORS
    colors[index % colors.size]
  end

  def required_params_present?(keys)
    keys.all? { |key| params[key].present? }
  end

  def render_missing_params
    render json: { error: 'Missing required parameters' }, status: :unprocessable_entity
  end

  def render_duplicate_hook
    render json: { error: 'Trello board is already connected' }, status: :unprocessable_entity
  end

  def render_invalid_whatsapp_inbox
    render json: { error: 'WhatsApp inbox not found' }, status: :unprocessable_entity
  end
end

class Api::V1::Accounts::Conversations::ScheduledMessagesController < Api::V1::Accounts::Conversations::BaseController
  include Events::Types

  before_action :ensure_feature_enabled
  before_action :set_scheduled_message, only: [:update, :destroy, :retry]

  # BaseController#conversation já resolve @conversation por display_id na conta atual
  # e autoriza :show? (qualquer agente com acesso à conversa; hook Enterprise incluso).

  def index
    # Estados transitórios (processing/executing) não são exibidos na listagem.
    @scheduled_messages = @conversation.scheduled_messages
                                       .includes(:account, :created_by)
                                       .where(status: [ScheduledMessage.statuses[:pending], ScheduledMessage.statuses[:sent],
                                                       ScheduledMessage.statuses[:failed], ScheduledMessage.statuses[:cancelled]])
                                       .order(scheduled_at: :desc)
  end

  def create
    @scheduled_message = @conversation.scheduled_messages.create!(
      scheduled_message_params.merge(account: Current.account, created_by: Current.user)
    )
    Rails.configuration.dispatcher.dispatch(SCHEDULED_MESSAGE_CREATED, Time.zone.now, scheduled_message: @scheduled_message)
  end

  # Editar apenas enquanto pending; a corrida com o sweep é decidida pelo with_lock
  # (o perdedor renderiza 409 com o estado atual).
  def update
    @scheduled_message.with_lock do
      next render_conflict unless @scheduled_message.pending?

      @scheduled_message.update!(scheduled_message_params)
      Rails.configuration.dispatcher.dispatch(SCHEDULED_MESSAGE_UPDATED, Time.zone.now, scheduled_message: @scheduled_message)
    end
  end

  def destroy
    @scheduled_message.with_lock do
      next render_conflict unless @scheduled_message.pending?

      @scheduled_message.update!(status: :cancelled)
      Rails.configuration.dispatcher.dispatch(SCHEDULED_MESSAGE_CANCELLED, Time.zone.now, scheduled_message: @scheduled_message)
    end
  end

  # Retry manual: volta a pending e enfileira execução imediata (não espera o sweep).
  # O enqueue fica dentro do lock para que um 409 (recusa) não dispare execução.
  def retry
    @scheduled_message.with_lock do
      next render_conflict unless @scheduled_message.failed?

      @scheduled_message.retry_manual!
      Rails.configuration.dispatcher.dispatch(SCHEDULED_MESSAGE_UPDATED, Time.zone.now, scheduled_message: @scheduled_message)
      ScheduledMessages::ProcessScheduledMessageJob.perform_later(@scheduled_message.id)
    end
  end

  private

  def scheduled_message_params
    params.permit(:content, :scheduled_at, :internal_note)
  end

  def set_scheduled_message
    @scheduled_message = @conversation.scheduled_messages.find(params[:id])
  end

  def render_conflict
    render json: { error: "cannot modify #{@scheduled_message.status} scheduled message", status: @scheduled_message.status },
           status: :conflict
  end

  def ensure_feature_enabled
    render json: { error: 'Feature not enabled' }, status: :not_found unless Current.account.feature_enabled?('scheduled_messages')
  end
end

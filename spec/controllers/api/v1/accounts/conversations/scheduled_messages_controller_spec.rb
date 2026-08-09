require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Conversations::ScheduledMessagesController', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  before do
    account.enable_features!(:scheduled_messages)
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  def scheduled_params(attributes = {})
    { content: 'Bom dia!', scheduled_at: 2.hours.from_now.iso8601 }.merge(attributes)
  end

  def create_scheduled(attributes = {})
    create(:scheduled_message, { account: account, conversation: conversation, created_by: agent,
                                 content: 'x', scheduled_at: 2.hours.from_now }.merge(attributes))
  end

  describe 'GET index' do
    it 'lista as mensagens agendadas, sem os estados transitórios' do
      pending = create_scheduled(content: 'pendente')
      sent = create_scheduled(content: 'enviada', status: :sent, sent_at: Time.current)
      processing = create_scheduled(content: 'processando', status: :processing)

      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      ids = response.parsed_body['payload'].pluck('id')
      expect(ids).to include(pending.id, sent.id)
      expect(ids).not_to include(processing.id)
    end
  end

  describe 'POST create' do
    it 'cria mensagem pending' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages",
           params: scheduled_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('pending')
    end

    it 'rejeita data no passado' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages",
           params: scheduled_params(scheduled_at: 1.minute.ago.iso8601),
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'serializa scheduled_at com offset do fuso da conta' do
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages",
           params: scheduled_params, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['scheduled_at']).to match(/-\d{2}:\d{2}$/)
    end

    it 'responde 404 para conversa de outra conta' do
      other_account = create(:account)
      create(:account_user, account: other_account, user: agent, role: :agent)

      post "/api/v1/accounts/#{other_account.id}/conversations/#{conversation.display_id}/scheduled_messages",
           params: scheduled_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'responde 401 para agente sem acesso à conversa' do
      outsider = create(:user, account: account)

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages",
           params: scheduled_params, headers: outsider.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'gate: sem a flag responde 404' do
      account.disable_features!(:scheduled_messages)
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages",
           params: scheduled_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH update' do
    it 'edita apenas pending' do
      scheduled = create_scheduled(content: 'antigo')
      patch "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages/#{scheduled.id}",
            params: scheduled_params(content: 'novo'), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(scheduled.reload.content).to eq('novo')
    end

    it 'responde 409 com o estado atual para status != pending' do
      scheduled = create_scheduled(status: :sent, sent_at: Time.current)
      patch "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages/#{scheduled.id}",
            params: scheduled_params(content: 'novo'), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['status']).to eq('sent')
    end

    it 'rejeita data no passado na edição' do
      scheduled = create_scheduled
      patch "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages/#{scheduled.id}",
            params: scheduled_params(scheduled_at: 1.minute.ago.iso8601), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE cancel' do
    it 'cancela pending' do
      scheduled = create_scheduled
      delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages/#{scheduled.id}",
             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(scheduled.reload).to be_cancelled
    end

    it 'responde 409 para processing' do
      scheduled = create_scheduled(status: :processing)
      delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages/#{scheduled.id}",
             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['status']).to eq('processing')
    end
  end

  describe 'POST retry' do
    it 'volta a pending, zera retry_count e enfileira execução imediata' do
      scheduled = create_scheduled(status: :failed, retry_count: 3, error: 'boom')
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages/#{scheduled.id}/retry",
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(scheduled.reload).to be_pending
      expect(scheduled.retry_count).to eq(0)
      expect(scheduled.error).to be_nil
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |j| j[:job] })
        .to include(ScheduledMessages::ProcessScheduledMessageJob)
    end

    it 'responde 409 para status != failed, sem enfileirar execução' do
      scheduled = create_scheduled
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/scheduled_messages/#{scheduled.id}/retry",
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['status']).to eq('pending')
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |j| j[:job] })
        .not_to include(ScheduledMessages::ProcessScheduledMessageJob)
    end
  end
end

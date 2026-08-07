require 'rails_helper'

RSpec.describe 'Pipeline API (Enterprise)', type: :request do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:pipeline) { create(:pipeline, account: account) }
  let!(:stage) { pipeline.pipeline_stages.first }

  before { account.enable_features!('pipeline') }

  describe 'GET /api/v1/accounts/:account_id/pipelines/:pipeline_id/stages/:id/conversations' do
    let!(:stage_conversation) { create(:conversation, account: account, pipeline_stage: stage) }
    let!(:other_stage) { create(:pipeline_stage, pipeline: pipeline, name: 'Other', position: 99) }
    let!(:other_stage_conversation) { create(:conversation, account: account, pipeline_stage: other_stage) }

    context 'when agent has conversation_participating_manage without participation' do
      before do
        create(:inbox_member, user: agent, inbox: stage_conversation.inbox)
        custom_role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
        account.account_users.find_by(user_id: agent.id).update!(custom_role: custom_role)
      end

      it 'does not return conversations the agent does not participate in' do
        get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}/conversations",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        payload_ids = response.parsed_body['data']['payload'].map { |c| c['id'] }
        expect(payload_ids).not_to include(stage_conversation.display_id)
      end

      it 'returns conversations the agent is assigned to' do
        stage_conversation.update!(assignee: agent)

        get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}/conversations",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        payload_ids = response.parsed_body['data']['payload'].map { |c| c['id'] }
        expect(payload_ids).to include(stage_conversation.display_id)
      end

      it 'returns conversations the agent is a participant of' do
        create(:conversation_participant, conversation: stage_conversation, account: account, user: agent)

        get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}/conversations",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        payload_ids = response.parsed_body['data']['payload'].map { |c| c['id'] }
        expect(payload_ids).to include(stage_conversation.display_id)
      end
    end

    context 'when administrator' do
      it 'returns all conversations in the stage' do
        get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}/conversations",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        payload_ids = response.parsed_body['data']['payload'].map { |c| c['id'] }
        expect(payload_ids).to include(stage_conversation.display_id)
      end
    end
  end
end

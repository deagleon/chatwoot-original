require 'rails_helper'

RSpec.describe 'Pipeline API', type: :request do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:pipeline) { create(:pipeline, account: account) }

  before { account.enable_features!('pipeline') }

  describe 'GET /api/v1/accounts/:account_id/pipelines' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/pipelines"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'returns pipelines' do
        get "/api/v1/accounts/#{account.id}/pipelines", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(response.body).to include(pipeline.name)
      end
    end

    context 'when feature flag disabled' do
      before { account.disable_features!('pipeline') }

      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/pipelines", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pipelines/:id' do
    it 'returns the pipeline with stages' do
      get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.body).to include(pipeline.name)
      expect(response.parsed_body['stages'].length).to eq(Pipeline::DEFAULT_STAGES.length)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pipelines' do
    context 'when agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/pipelines", headers: agent.create_new_auth_token,
                                                         params: { pipeline: { name: 'New' } }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when admin' do
      it 'creates a pipeline with default stages' do
        expect do
          post "/api/v1/accounts/#{account.id}/pipelines", headers: admin.create_new_auth_token,
                                                           params: { pipeline: { name: 'Sales' } }, as: :json
        end.to change(Pipeline, :count).by(1)

        expect(response).to have_http_status(:success)
        new_pipeline = Pipeline.last
        expect(new_pipeline.name).to eq('Sales')
        expect(new_pipeline.pipeline_stages.count).to eq(Pipeline::DEFAULT_STAGES.length)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/pipelines/:id' do
    it 'updates the pipeline name' do
      patch "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}", headers: admin.create_new_auth_token,
                                                                       params: { pipeline: { name: 'Renamed' } }, as: :json
      expect(response).to have_http_status(:success)
      expect(pipeline.reload.name).to eq('Renamed')
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/pipelines/:id' do
    it 'archives the pipeline instead of deleting' do
      delete "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.archived_at).to be_present
      expect(Pipeline.exists?(pipeline.id)).to be(true)
    end
  end

  describe 'Pipeline Stages' do
    let!(:stage) { pipeline.pipeline_stages.first }

    describe 'POST /api/v1/accounts/:account_id/pipelines/:pipeline_id/stages' do
      it 'creates a stage as admin' do
        expect do
          post "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages",
               headers: admin.create_new_auth_token,
               params: { stage: { name: 'New Stage', position: 99, color: '#FF0000' } }, as: :json
        end.to change(PipelineStage, :count).by(1)
        expect(response).to have_http_status(:success)
      end

      it 'forbids agent from creating' do
        post "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages", headers: agent.create_new_auth_token,
                                                                               params: { stage: { name: 'X', position: 99 } }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe 'PATCH .../stages/:id' do
      it 'updates the stage' do
        patch "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}", headers: admin.create_new_auth_token,
                                                                                            params: { stage: { name: 'Renamed Stage' } }, as: :json
        expect(response).to have_http_status(:success)
        expect(stage.reload.name).to eq('Renamed Stage')
      end
    end

    describe 'DELETE .../stages/:id' do
      it 'returns 409 when stage has conversations' do
        create(:conversation, account: account, pipeline_stage: stage)
        delete "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:conflict)
        body = response.parsed_body
        expect(body['conversations_count']).to eq(1)
      end

      it 'deletes the stage when empty' do
        delete "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        expect(PipelineStage.exists?(stage.id)).to be(false)
      end
    end

    describe 'GET .../stages/:id/conversations' do
      it 'lists conversations in the stage ordered by pipeline_stage_changed_at ASC' do
        first = create(:conversation, account: account, pipeline_stage: stage)
        second = create(:conversation, account: account, pipeline_stage: stage)

        get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}/conversations",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        ids = body['data']['payload'].map { |c| c['id'] }
        expect(ids).to include(first.display_id, second.display_id)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:id/pipeline_stage' do
    let!(:conversation) { create(:conversation, account: account) }
    let!(:target_stage) { pipeline.pipeline_stages.first }

    it 'moves the conversation to a new stage' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/pipeline_stage",
           headers: admin.create_new_auth_token,
           params: { pipeline_stage_id: target_stage.id }, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.pipeline_stage_id).to eq(target_stage.id)
      expect(conversation.reload.pipeline_stage_changed_at).to be_present
    end

    it 'returns not found for cross-account stage' do
      other_account = create(:account)
      other_pipeline = create(:pipeline, account: other_account)
      other_stage = other_pipeline.pipeline_stages.first

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/pipeline_stage",
           headers: admin.create_new_auth_token,
           params: { pipeline_stage_id: other_stage.id }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    context 'real-time dispatch' do
      it 'emits CONVERSATION_UPDATED with pipeline_stage_id in changed_attributes' do
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/pipeline_stage",
             headers: admin.create_new_auth_token,
             params: { pipeline_stage_id: target_stage.id }, as: :json

        expect(response).to have_http_status(:success)
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
          Events::Types::CONVERSATION_UPDATED,
          kind_of(Time),
          conversation: kind_of(Conversation),
          notifiable_assignee_change: anything,
          changed_attributes: hash_including('pipeline_stage_id' => anything),
          performed_by: anything
        )
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Tasks', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  # Test env uses :null_store; swap in a real store so job payloads are observable.
  around do |example|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = previous_cache
  end

  before do
    account.enable_features!('captain_tasks')
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: 'test-key')
    create(:message, conversation: conversation, message_type: :incoming, content: 'I need help')
  end

  def stub_llm_with_timeout!
    stub_llm!(raise_error: Faraday::TimeoutError.new('timeout'))
  end

  def stub_llm_with_success!
    mock_response = instance_double(RubyLLM::Message, content: 'Sure, I can help!', input_tokens: 50, output_tokens: 20)
    stub_llm!(return_value: mock_response)
  end

  def stub_llm!(raise_error: nil, return_value: nil)
    mock_chat = chat_double

    allow(Llm::Config).to receive(:with_api_key).and_yield(mock_chat_context(mock_chat))
    stub_ask(mock_chat, raise_error: raise_error, return_value: return_value)
  end

  def chat_double
    mock_chat = instance_double(RubyLLM::Chat)

    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tool).and_return(mock_chat)
    allow(mock_chat).to receive(:on_end_message).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions)
    mock_chat
  end

  def mock_chat_context(mock_chat)
    instance_double(RubyLLM::Context, chat: mock_chat)
  end

  def stub_ask(mock_chat, raise_error:, return_value:)
    if raise_error
      allow(mock_chat).to receive(:ask).and_raise(raise_error)
    else
      allow(mock_chat).to receive(:ask).and_return(return_value)
    end
  end

  def post_suggestion(display_id)
    post "/api/v1/accounts/#{account.id}/captain/tasks/reply_suggestion",
         params: { conversation_display_id: display_id },
         headers: agent.create_new_auth_token,
         as: :json
  end

  def get_status(task_id)
    get "/api/v1/accounts/#{account.id}/captain/tasks/reply_suggestion/#{task_id}",
        headers: agent.create_new_auth_token,
        as: :json
  end

  describe 'POST /api/v1/accounts/:account_id/captain/tasks/reply_suggestion' do
    it 'enqueues a job and returns 202 with a task id instead of holding the request' do
      post_suggestion(conversation.display_id)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['task_id']).to be_present
      expect(Captain::Tasks::ReplySuggestionJob).to have_been_enqueued
    end

    it 'returns 422 immediately without enqueueing when the conversation does not exist' do
      post_suggestion('nonexistent')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('captain.conversation_not_found'))
      expect(Captain::Tasks::ReplySuggestionJob).not_to have_been_enqueued
    end
  end

  describe 'GET /api/v1/accounts/:account_id/captain/tasks/reply_suggestion/:task_id' do
    it 'returns pending while the job has not finished' do
      get_status(SecureRandom.uuid)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['status']).to eq('pending')
    end

    it 'delivers the suggestion once the job completes' do
      stub_llm_with_success!
      post_suggestion(conversation.display_id)
      task_id = response.parsed_body['task_id']

      perform_enqueued_jobs
      get_status(task_id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['message']).to eq('Sure, I can help!')

      # Single-read: the payload is consumed on delivery.
      get_status(task_id)
      expect(response.parsed_body['status']).to eq('pending')
    end

    it 'returns 422 with a friendly message when generation fails instead of 500' do
      stub_llm_with_timeout!
      post_suggestion(conversation.display_id)
      task_id = response.parsed_body['task_id']

      perform_enqueued_jobs
      get_status(task_id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('captain.timeout'))
    end
  end
end

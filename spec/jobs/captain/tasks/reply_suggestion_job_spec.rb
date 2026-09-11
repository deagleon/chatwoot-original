# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Tasks::ReplySuggestionJob, type: :job do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:task_id) { SecureRandom.uuid }
  let(:cache_key) { described_class.cache_key_for(task_id) }
  let(:mock_response) do
    instance_double(RubyLLM::Message, content: 'Sure, I can help!', input_tokens: 50, output_tokens: 20)
  end
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_context) { instance_double(RubyLLM::Context, chat: mock_chat) }

  before do
    account.enable_features!('captain_tasks')
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: 'test-key')
    create(:message, conversation: conversation, message_type: :incoming, content: 'I need help')

    allow(Llm::Config).to receive(:with_api_key).and_yield(mock_context)
    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tool).and_return(mock_chat)
    allow(mock_chat).to receive(:on_end_message).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  def perform_job
    described_class.perform_now(
      account_id: account.id,
      conversation_display_id: conversation.display_id,
      user_id: agent.id,
      task_id: task_id
    )
  end

  def read_payload
    JSON.parse(Redis::Alfred.get(cache_key))
  end

  it 'writes the completed payload to the cache' do
    perform_job

    payload = read_payload
    expect(payload['status']).to eq('completed')
    expect(payload['message']).to eq('Sure, I can help!')
  end

  it 'writes a friendly failure payload when the LLM times out' do
    allow(mock_chat).to receive(:ask).and_raise(Faraday::TimeoutError, 'timeout')

    perform_job

    payload = read_payload
    expect(payload['status']).to eq('failed')
    expect(payload['error']).to eq(I18n.t('captain.timeout'))
  end

  it 'writes a failure payload instead of raising when records are gone' do
    expect do
      described_class.perform_now(
        account_id: account.id,
        conversation_display_id: conversation.display_id,
        user_id: -1,
        task_id: task_id
      )
    end.not_to raise_error

    expect(read_payload['status']).to eq('failed')
  end
end

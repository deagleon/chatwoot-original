require 'rails_helper'

RSpec.describe ScheduledMessages::ProcessScheduledMessageJob do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  before { account.enable_features!(:scheduled_messages) }

  # Rows criadas no passado com scheduled_at ainda válido na criação, para que
  # estejam vencidas (claimáveis) no momento da execução.
  def create_due(overrides = {})
    travel_to(1.hour.ago) do
      create(:scheduled_message, { account: account, conversation: conversation, created_by: agent,
                                   content: 'Bom dia!', scheduled_at: 1.minute.from_now }.merge(overrides))
    end
  end

  describe 'claim atômico' do
    it 'apenas um worker executa em corrida' do
      scheduled = create_due
      scheduled.claim!

      expect { described_class.perform_now(scheduled.id) }.not_to change(Message, :count)
    end
  end

  describe 'conversa resolvida' do
    it 'cria a Message, reabre a conversa e enfileira SendReplyJob uma única vez' do
      conversation.resolved!
      scheduled = create_due

      expect { described_class.perform_now(scheduled.id) }.to change(Message, :count).by(1)
      expect(scheduled.reload).to be_sent
      expect(scheduled.message_id).to be_present
      expect(conversation.reload.status).to eq('open')
      expect(scheduled.message.content_attributes['scheduled_message_id']).to eq(scheduled.id)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j[:job] == SendReplyJob }).to eq(1)
    end
  end

  describe 'idempotência pós-commit' do
    it 'retry pós-commit encontra sent e não recria a Message' do
      scheduled = create_due
      described_class.perform_now(scheduled.id)

      expect { described_class.perform_now(scheduled.id) }.not_to change(Message, :count)
    end
  end

  describe 'conversa inexistente' do
    it 'falha terminal direta com error conversation_gone, sem retry' do
      scheduled = create_due
      scheduled.conversation.destroy!

      described_class.perform_now(scheduled.id)
      expect(scheduled.reload).to be_failed
      expect(scheduled.error).to eq('conversation_gone')
      expect(scheduled.retry_count).to eq(0)
    end
  end

  describe 'falha transitória de criação' do
    it 'incrementa retry_count e volta a pending enquanto < max_retries' do
      scheduled = create_due
      allow_any_instance_of(Messages::MessageBuilder).to receive(:perform) # rubocop:disable RSpec/AnyInstance
        .and_raise(ActiveRecord::RecordInvalid.new(Message.new))

      described_class.perform_now(scheduled.id)
      expect(scheduled.reload).to be_pending
      expect(scheduled.retry_count).to eq(1)

      described_class.perform_now(scheduled.id)
      expect(scheduled.reload.retry_count).to eq(2)
    end

    it 'vira failed + error ao esgotar max_retries' do
      scheduled = create_due
      allow_any_instance_of(Messages::MessageBuilder).to receive(:perform) # rubocop:disable RSpec/AnyInstance
        .and_raise(ActiveRecord::RecordInvalid.new(Message.new))
      scheduled.update!(retry_count: 3)

      described_class.perform_now(scheduled.id)
      expect(scheduled.reload).to be_failed
      expect(scheduled.error).to be_present
    end
  end

  describe 'rollback pós-criação (crash no meio)' do
    it 'devolve a row a processing sem Message órfã' do
      scheduled = create_due
      # Fallback para os demais update! (claim, executing) e raise só no commit do sent.
      allow_any_instance_of(ScheduledMessage).to receive(:update!).and_call_original # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(ScheduledMessage).to receive(:update!) # rubocop:disable RSpec/AnyInstance
        .with(hash_including(status: :sent)).and_raise(ActiveRecord::Rollback)

      expect { described_class.perform_now(scheduled.id) }.not_to raise_error
      expect(Message.where("content_attributes->>'scheduled_message_id' = ?", scheduled.id.to_s)).to be_empty
      expect(scheduled.reload).to be_processing
    end
  end

  describe 'corrida de dois workers' do
    it 'apenas um cria a Message (claim atômico com lock de linha)' do
      scheduled = create_due

      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.perform_now(scheduled.id)
          end
        end
      end
      threads.each(&:join)

      # content_attributes é json + store (double-encoded no banco), então a
      # verificação usa o accessor do modelo em vez de extração SQL ->>.
      messages = Message.where(conversation_id: conversation.id)
      expect(messages.count).to eq(1)
      expect(messages.first.content_attributes['scheduled_message_id']).to eq(scheduled.id)
      expect(scheduled.reload).to be_sent
    end
  end

  describe 'entrega at-most-once do canal' do
    it 'enfileira SendReplyJob exatamente uma vez (callback real de Message#after_create_commit)' do
      scheduled = create_due
      described_class.perform_now(scheduled.id)

      send_reply_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == SendReplyJob }
      expect(send_reply_jobs.length).to eq(1)
    end
  end
end

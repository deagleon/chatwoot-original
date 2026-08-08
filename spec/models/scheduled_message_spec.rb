require 'rails_helper'

RSpec.describe ScheduledMessage do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def build_message(attributes = {})
    described_class.new(
      { account: account, conversation: conversation, created_by: agent, content: 'Bom dia!',
        scheduled_at: 1.hour.from_now }.merge(attributes)
    )
  end

  describe 'validações' do
    it 'rejeita scheduled_at no passado (server-side, autoritativo)' do
      message = build_message(scheduled_at: 1.minute.ago)
      expect(message).not_to be_valid
      expect(message.errors[:scheduled_at]).to be_present
    end

    it 'aceita scheduled_at futuro' do
      expect(build_message).to be_valid
    end

    it 'rejeita internal_note acima de 500 chars' do
      expect(build_message(internal_note: 'x' * 501)).not_to be_valid
    end

    it 'não revalida o futuro do scheduled_at em transições de lifecycle' do
      message = build_message.tap(&:save!)
      travel_to(2.hours.from_now) { expect(message.claim!).to be(true) }
    end
  end

  describe 'lifecycle' do
    it 'percorre pending → processing → executing → sent' do
      # Criada no passado para que scheduled_at já tenha vencido no momento do claim.
      message = travel_to(2.hours.ago) { build_message.tap(&:save!) }
      expect(message).to be_pending

      expect(message.claim!).to be(true)
      expect(message).to be_processing

      message.with_lock { message.update!(status: :executing) }
      expect(message).to be_executing

      message.update!(status: :sent, sent_at: Time.current)
      expect(message).to be_sent
    end

    it 'claim! falha para row já processing' do
      message = travel_to(2.hours.ago) { build_message.tap(&:save!) }
      expect(message.claim!).to be(true)
      expect(message.claim!).to be(false)
    end

    it 'stale processing é reclaimável após STALE_PROCESSING_TIMEOUT' do
      message = travel_to(2.hours.ago) { build_message.tap(&:save!) }
      expect(message.claim!).to be(true)
      expect(message).to be_processing

      # Margem de 1 minuto: travel_to congela em segundos inteiros, e o claim grava
      # updated_at com fração de segundo — sem a margem o lock ficaria além do limite.
      travel_to((described_class::STALE_PROCESSING_TIMEOUT + 1.minute).from_now) do
        expect(message.stale_processing?).to be(true)
        expect(message.claim!).to be(true)
        expect(message).to be_processing
      end
    end
  end

  describe 'scopes' do
    it 'due: pending vencidas, não as futuras' do
      overdue = travel_to(2.hours.ago) { build_message(scheduled_at: 1.hour.from_now).tap(&:save!) }
      future = build_message(content: 'futura').tap(&:save!)

      expect(described_class.due).to contain_exactly(overdue)
      expect(described_class.due).not_to include(future)
    end

    it 'sweepable: due + processing stale, sem as demais' do
      due = travel_to(2.hours.ago) { build_message(scheduled_at: 1.hour.from_now).tap(&:save!) }
      stale = travel_to(2.hours.ago) { build_message(content: 'stale', status: :processing).tap(&:save!) }
      future = build_message(content: 'futura').tap(&:save!)

      expect(described_class.sweepable).to contain_exactly(due, stale)
      expect(described_class.sweepable).not_to include(future)
    end

    it 'for_enabled_accounts: apenas contas com a flag habilitada' do
      enabled_account = create(:account)
      enabled_account.enable_features!(:scheduled_messages)
      enabled = build_message(account: enabled_account,
                              conversation: create(:conversation, account: enabled_account)).tap(&:save!)
      disabled = build_message(content: 'sem flag').tap(&:save!)

      expect(described_class.for_enabled_accounts).to include(enabled)
      expect(described_class.for_enabled_accounts).not_to include(disabled)
    end
  end

  describe 'cancel!' do
    it 'cancela apenas pending' do
      message = build_message.tap(&:save!)
      message.cancel!
      expect(message).to be_cancelled
      expect { message.reload.cancel! }.to raise_error(ScheduledMessage::NotPendingError)
    end
  end

  describe 'retry_manual!' do
    it 'volta para pending, zera retry_count e limpa error' do
      message = build_message.tap(&:save!)
      message.update!(status: :failed, retry_count: 3, error: 'boom')
      message.retry_manual!
      expect(message).to be_pending
      expect(message.retry_count).to eq(0)
      expect(message.error).to be_nil
    end
  end

  describe 'fail_terminal!' do
    it 'marca failed com o erro informado' do
      message = build_message.tap(&:save!)
      message.fail_terminal!('conversation_gone')
      expect(message).to be_failed
      expect(message.error).to eq('conversation_gone')
    end
  end

  describe 'purge_terminal!' do
    it 'purga terminais antigos em lotes' do
      old_sent = build_message.tap(&:save!)
      old_sent.update!(status: :sent, updated_at: 31.days.ago)
      recent_failed = build_message(content: 'recente').tap(&:save!)
      recent_failed.update!(status: :failed, updated_at: 1.day.ago)

      described_class.purge_terminal!
      expect(described_class.find_by(id: old_sent.id)).to be_nil
      expect(described_class.find_by(id: recent_failed.id)).to be_present
    end
  end

  describe 'deleção de entidades relacionadas' do
    it 'exclui o usuário criador com mensagens agendadas pendentes e enviadas' do
      build_message.tap(&:save!)
      sent = build_message(content: 'enviada').tap(&:save!)
      sent.update!(status: :sent, sent_at: Time.current)

      expect { agent.destroy! }.not_to raise_error
    end

    it 'exclui a conversa com mensagem agendada enviada e preserva a row com conversation_id nulo' do
      sent = build_message.tap(&:save!)
      message = Messages::MessageBuilder.new(agent, conversation, { content: 'Bom dia!', message_type: 'outgoing' }).perform
      sent.update!(message: message, status: :sent, sent_at: Time.current)

      expect do
        perform_enqueued_jobs(only: ActiveRecord::DestroyAssociationAsyncJob) { conversation.destroy! }
      end.not_to raise_error
      expect(sent.reload.conversation).to be_nil
      expect(Message.find_by(id: message.id)).to be_nil
    end

    it 'exclui a conta com mensagens agendadas' do
      build_message.tap(&:save!)
      sent = build_message(content: 'enviada').tap(&:save!)
      sent.update!(status: :sent, sent_at: Time.current)

      expect { account.destroy! }.not_to raise_error
    end
  end
end

require 'rails_helper'

RSpec.describe ScheduledMessages::TriggerDueJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  before { account.enable_features!(:scheduled_messages) }

  it 'enqueues workers for due pending rows but not future ones' do
    due = travel_to(1.hour.ago) do
      create(:scheduled_message, account: account, conversation: conversation, created_by: agent, content: 'x',
                                 scheduled_at: 1.minute.from_now)
    end
    future = create(:scheduled_message, account: account, conversation: conversation, created_by: agent, content: 'y')

    expect { job.perform }.to have_enqueued_job(ScheduledMessages::ProcessScheduledMessageJob).exactly(:once)
    expect(ScheduledMessages::ProcessScheduledMessageJob).to have_been_enqueued.with(due.id)
    expect(ScheduledMessages::ProcessScheduledMessageJob).not_to have_been_enqueued.with(future.id)
  end

  it 're-enqueues stale processing rows so they get retried' do
    stale = travel_to(1.hour.ago) do
      create(:scheduled_message, account: account, conversation: conversation, created_by: agent, content: 'x',
                                 scheduled_at: 59.minutes.from_now, status: :processing)
    end

    expect { job.perform }.to have_enqueued_job(ScheduledMessages::ProcessScheduledMessageJob).with(stale.id)
  end

  it 'caps enqueues at the configured sweep limit' do
    create(:installation_config, name: 'SCHEDULED_MESSAGES_SWEEP_LIMIT',
                                 serialized_value: { value: 1 }.with_indifferent_access)
    travel_to(1.hour.ago) do
      create_list(:scheduled_message, 2, account: account, conversation: conversation, created_by: agent,
                                         content: 'x', scheduled_at: 1.minute.from_now)
    end

    expect { job.perform }.to have_enqueued_job(ScheduledMessages::ProcessScheduledMessageJob).exactly(:once)
  end

  it 'purges terminal rows past the retention window' do
    old = travel_to(31.days.ago) do
      create(:scheduled_message, account: account, conversation: conversation, created_by: agent, content: 'x',
                                 scheduled_at: 1.minute.from_now)
    end
    old.update!(status: :sent, updated_at: 31.days.ago)

    job.perform

    expect { old.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'skips rows for accounts with the flag disabled so they cannot starve others' do
    enabled = travel_to(1.hour.ago) do
      create(:scheduled_message, account: account, conversation: conversation, created_by: agent, content: 'x',
                                 scheduled_at: 1.minute.from_now)
    end
    disabled_account = create(:account)
    travel_to(1.hour.ago) do
      create(:scheduled_message, account: disabled_account, conversation: create(:conversation, account: disabled_account),
                                 created_by: create(:user, account: disabled_account), content: 'y', scheduled_at: 1.minute.from_now)
    end

    expect { job.perform }.to have_enqueued_job(ScheduledMessages::ProcessScheduledMessageJob).exactly(:once)
    expect(ScheduledMessages::ProcessScheduledMessageJob).to have_been_enqueued.with(enabled.id)
  end
end

# == Schema Information
#
# Table name: scheduled_messages
#
#  id              :bigint           not null, primary key
#  content         :text             not null
#  error           :text
#  internal_note   :text
#  max_retries     :integer          default(3), not null
#  retry_count     :integer          default(0), not null
#  scheduled_at    :datetime         not null
#  sent_at         :datetime
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint
#  created_by_id   :bigint           not null
#  message_id      :bigint
#
# Indexes
#
#  index_scheduled_messages_on_account_id               (account_id)
#  index_scheduled_messages_on_conversation_id          (conversation_id)
#  index_scheduled_messages_on_created_by_id            (created_by_id)
#  index_scheduled_messages_on_message_id               (message_id)
#  index_scheduled_messages_on_status_and_scheduled_at  (status,scheduled_at)
#
class ScheduledMessage < ApplicationRecord
  class NotPendingError < StandardError; end

  belongs_to :account
  # Nullable so a conversation destroy can nullify the reference and the executor can
  # fail the row terminal (conversation_gone) instead of orphaning it.
  belongs_to :conversation, optional: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :message, optional: true

  # A processing row whose lock is older than this is treated as abandoned and reclaimed.
  STALE_PROCESSING_TIMEOUT = 15.minutes
  # Terminal rows are purged after this to keep the table bounded.
  RETENTION_WINDOW = 30.days

  enum status: { pending: 0, processing: 1, executing: 2, sent: 3, failed: 4, cancelled: 5 }

  validates :content, presence: true
  # Authoritative future rule; only checked when scheduled_at is (re)set, since lifecycle
  # transitions move rows through statuses after it passes.
  validates :scheduled_at, presence: true, on: :create
  validates :scheduled_at, comparison: { greater_than: ->(_record) { Time.current }, message: :must_be_in_the_future },
                           if: :scheduled_at_changed?
  validates :internal_note, length: { maximum: 500 }, allow_nil: true

  # Sweep: due pending rows, plus processing rows whose lock went stale.
  scope :due, -> { pending.where(scheduled_at: ..Time.current) }
  scope :stale_processing, -> { processing.where(updated_at: ...STALE_PROCESSING_TIMEOUT.ago) }
  scope :sweepable, -> { due.or(stale_processing) }

  # Excludes rows whose account disabled scheduled messages, so one disabled account's
  # backlog can't fill the sweep limit and starve enabled accounts.
  scope :for_enabled_accounts, -> { joins(:account).merge(Account.feature_scheduled_messages) }

  scope :expired_terminal, -> { where(status: [statuses[:sent], statuses[:cancelled], statuses[:failed]], updated_at: ...RETENTION_WINDOW.ago) }

  def self.purge_terminal!
    expired_terminal.in_batches(of: 1000).delete_all
  end

  # Espelha app/views/api/v1/models/_scheduled_message.json.jbuilder para o realtime.
  def push_event_data
    timezone = account.reporting_timezone.presence || 'UTC'
    {
      id: id,
      content: content,
      scheduled_at: scheduled_at.in_time_zone(timezone).iso8601,
      status: status,
      internal_note: internal_note,
      message_id: message_id,
      sent_at: sent_at&.in_time_zone(timezone)&.iso8601,
      error: error,
      created_by: created_by&.push_event_data
    }
  end

  # Atomic claim: only one worker can move a row into processing, so a row re-enqueued by an
  # overlapping sweep (or after a stale reclaim) cannot double-execute. A stale processing row
  # is reclaimed directly (no pending window), and refreshing updated_at renews the lock,
  # keeping the row out of the stale window while this worker holds it.
  def claim!
    with_lock do
      next false unless (pending? && scheduled_at <= Time.current) || stale_processing?

      update!(status: :processing, updated_at: Time.current)
      true
    end
  end

  # The claim renews updated_at, so a processing row past the timeout means its worker died.
  def stale_processing?
    processing? && updated_at < STALE_PROCESSING_TIMEOUT.ago
  end

  # Manual retry of a failed row: back to pending, reset retries and clear the error.
  # The worker is enqueued by the caller.
  def retry_manual!
    with_lock do
      raise NotPendingError, "cannot retry #{status} message" unless failed?

      update!(status: :pending, retry_count: 0, error: nil)
    end
  end

  # Direct terminal failure (e.g. conversation gone) — no retry.
  def fail_terminal!(error)
    update!(status: :failed, error: error)
  end
end

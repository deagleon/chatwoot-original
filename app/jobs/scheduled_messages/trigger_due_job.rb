class ScheduledMessages::TriggerDueJob < ApplicationJob
  queue_as :scheduled_jobs

  DEFAULT_SWEEP_LIMIT = 1000

  def perform
    started_at = Time.current
    purged = ScheduledMessage.purge_terminal!

    rows = ScheduledMessage.sweepable.for_enabled_accounts.order(:scheduled_at).limit(sweep_limit).to_a
    rows.each { |row| ScheduledMessages::ProcessScheduledMessageJob.perform_later(row.id) }

    log_summary(enqueued: rows.size, capped: rows.size >= sweep_limit, purged: purged, started_at: started_at)
  end

  private

  def sweep_limit
    (InstallationConfig.find_by(name: 'SCHEDULED_MESSAGES_SWEEP_LIMIT')&.value || DEFAULT_SWEEP_LIMIT).to_i
  end

  def log_summary(enqueued:, capped:, purged:, started_at:)
    summary = { event: 'completed', enqueued: enqueued, capped: capped, purged: purged,
                duration_ms: ((Time.current - started_at) * 1000).round }
    Rails.logger.info("[ScheduledMessages::TriggerDueJob] #{summary.to_json}")
  end
end

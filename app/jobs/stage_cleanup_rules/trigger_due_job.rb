class StageCleanupRules::TriggerDueJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    StageCleanupRule.active.includes(:pipeline_stage, :account).find_each do |rule|
      next unless rule.due?

      # Claim idempotente: apenas um worker pode enfileirar o processamento do dia,
      # mesmo com execuções concorrentes do cron. Incluir last_run_on NULL: regras
      # novas nunca seriam reivindicadas por where.not (SQL trata NULL à parte).
      claimed = StageCleanupRule.where(id: rule.id)
                                .where('last_run_on IS NULL OR last_run_on != ?', rule.local_today)
                                .update_all(last_run_on: rule.local_today) # rubocop:disable Rails/SkipsModelValidations
      StageCleanupRules::ProcessRuleJob.perform_later(rule.id) if claimed == 1
    end
  end
end

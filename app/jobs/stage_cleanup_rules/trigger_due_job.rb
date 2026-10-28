class StageCleanupRules::TriggerDueJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    StageCleanupRule.active.includes(:pipeline_stage, :account).find_each do |rule|
      # Calcula a ocorrência uma única vez por regra por sweep: a decisão de due
      # e o claim precisam usar o mesmo valor, senão um sweep que cruzar o limite
      # local HH:MM entre as duas chamadas gravaria a data errada.
      occurrence = rule.last_occurrence
      next unless rule.due?(occurrence)

      # Claim idempotente: apenas um worker pode enfileirar o processamento da ocorrência,
      # mesmo com execuções concorrentes do cron. Incluir last_run_on NULL: regras
      # novas nunca seriam reivindicadas por where.not (SQL trata NULL à parte).
      # Grava a data da ocorrência (e não a data local de hoje): ocorrências de 23:56-23:59
      # só disparam no sweep após a meia-noite, e gravar "hoje" pularia a ocorrência do próprio dia.
      occurrence_date = occurrence.to_date
      claimed = StageCleanupRule.where(id: rule.id)
                                .where('last_run_on IS NULL OR last_run_on < ?', occurrence_date)
                                .update_all(last_run_on: occurrence_date) # rubocop:disable Rails/SkipsModelValidations
      StageCleanupRules::ProcessRuleJob.perform_later(rule.id) if claimed == 1
    end
  end
end

class StageCleanupRules::ProcessRuleJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(rule_id)
    rule = StageCleanupRule.find_by(id: rule_id)
    return if rule.blank? || rule.pipeline_stage.blank?

    rule.pipeline_stage.conversations.find_each { |conversation| conversation.move_to_stage!(nil) }
  end
end

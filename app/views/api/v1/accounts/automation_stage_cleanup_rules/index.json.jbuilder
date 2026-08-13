json.payload do
  json.array! @rules do |rule|
    json.partial! 'api/v1/accounts/automation_stage_cleanup_rules/stage_cleanup_rule', formats: [:json], rule: rule
  end
end

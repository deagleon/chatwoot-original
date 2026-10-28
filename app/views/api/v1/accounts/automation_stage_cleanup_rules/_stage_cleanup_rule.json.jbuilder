json.id rule.id
json.cleanup_time rule.cleanup_time
json.active rule.active
json.last_run_on rule.last_run_on
json.pipeline_stage do
  json.id rule.pipeline_stage.id
  json.name rule.pipeline_stage.name
  json.pipeline do
    json.id rule.pipeline_stage.pipeline.id
    json.name rule.pipeline_stage.pipeline.name
  end
end

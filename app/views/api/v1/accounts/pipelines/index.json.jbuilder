json.payload do
  json.array! @pipelines, partial: 'api/v1/accounts/pipelines/pipeline', as: :pipeline
end

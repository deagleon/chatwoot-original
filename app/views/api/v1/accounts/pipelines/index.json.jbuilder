json.payload do
  json.array! @pipelines do |pipeline|
    json.id pipeline.id
    json.name pipeline.name
    json.archived_at pipeline.archived_at
    json.stages do
      json.array! pipeline.pipeline_stages.order(:position) do |stage|
        json.id stage.id
        json.name stage.name
        json.position stage.position
        json.color stage.color
        json.conversations_count stage.conversations_count
      end
    end
  end
end

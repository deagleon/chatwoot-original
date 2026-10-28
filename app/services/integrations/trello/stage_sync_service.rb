class Integrations::Trello::StageSyncService
  pattr_initialize [:pipeline!, :list!]

  STAGE_COLORS = %w[#6B7280 #3B82F6 #F59E0B #10B981 #EF4444 #8B5CF6].freeze

  def perform
    existing = pipeline.pipeline_stages.find_by(trello_list_id: list['id'])
    return existing if existing

    position = (pipeline.pipeline_stages.maximum(:position) || 0) + 1
    pipeline.pipeline_stages.create!(
      name: list['name'],
      color: STAGE_COLORS[(position - 1) % STAGE_COLORS.size],
      position: position,
      trello_list_id: list['id']
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # A concurrent create for the same list wins either way; only retryable
    # conflicts land here, and Sidekiq retries recompute the position if the
    # conflicting row belongs to a different list.
    pipeline.pipeline_stages.find_by!(trello_list_id: list['id'])
  end
end

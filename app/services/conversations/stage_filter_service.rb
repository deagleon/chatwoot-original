class Conversations::StageFilterService < Conversations::FilterService
  def initialize(params, user, account, stage)
    @stage = stage
    super(params, user, account)
  end

  def perform
    @conversations = base_relation.where(pipeline_stage_id: @stage.id)
    apply_search_query if @params[:q].present?

    {
      conversations: conversations,
      count: @conversations.count
    }
  end

  private

  def apply_search_query
    search = "%#{@params[:q]}%"
    @conversations = @conversations
                     .joins('INNER JOIN contacts ON conversations.contact_id = contacts.id')
                     .joins('LEFT JOIN messages ON messages.conversation_id = conversations.id')
                     .where(
                       'CAST(conversations.display_id AS TEXT) ILIKE :search OR ' \
                       'contacts.name ILIKE :search OR ' \
                       'contacts.email ILIKE :search OR ' \
                       'contacts.phone_number ILIKE :search OR ' \
                       'messages.content ILIKE :search',
                       search: search
                     ).select('DISTINCT conversations.*')
  end

  def conversations
    @conversations.order(pipeline_stage_changed_at: :asc).page(current_page)
  end
end

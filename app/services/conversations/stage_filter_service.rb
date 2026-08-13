class Conversations::StageFilterService < Conversations::FilterService
  def initialize(params, user, account, stage)
    @stage = stage
    super(params, user, account)
  end

  def perform
    @conversations = base_relation.where(pipeline_stage_id: @stage.id)
    apply_inbox_filter
    apply_assignee_filter
    apply_label_filter
    apply_status_filter
    apply_search_query if @params[:q].present?

    {
      conversations: conversations,
      count: @conversations.count
    }
  end

  private

  def apply_inbox_filter
    inbox_ids = Array(@params[:inbox_ids]).map(&:to_i).reject(&:zero?)
    @conversations = @conversations.where(inbox_id: inbox_ids) if inbox_ids.present?
  end

  def apply_assignee_filter
    assignee_id = @params[:assignee_id].to_i
    @conversations = @conversations.where(assignee_id: assignee_id) if assignee_id.positive?
  end

  def apply_label_filter
    label = @params[:label].to_s
    @conversations = @conversations.tagged_with(label) if label.present?
  end

  def apply_status_filter
    statuses = Array(@params[:status]).map(&:to_s).reject(&:blank?)
    @conversations = @conversations.where(status: statuses) if statuses.present?
  end

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
    @conversations.order(sort_order).page(current_page)
  end

  def sort_order
    case @params[:sort_by]
    when 'last_activity_at'
      { last_activity_at: :desc, id: :desc }
    else
      { pipeline_stage_changed_at: :asc }
    end
  end
end

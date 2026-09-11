class Api::V1::Accounts::Captain::TasksController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def rewrite
    result = Captain::RewriteService.new(
      account: Current.account,
      content: params[:content],
      operation: params[:operation],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def summarize
    result = Captain::SummaryService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def reply_suggestion
    conversation = Current.account.conversations.find_by(display_id: params[:conversation_display_id])
    return render json: { error: I18n.t('captain.conversation_not_found') }, status: :unprocessable_content if conversation.nil?

    task_id = SecureRandom.uuid
    Captain::Tasks::ReplySuggestionJob.perform_later(
      account_id: Current.account.id,
      conversation_display_id: conversation.display_id,
      user_id: Current.user.id,
      task_id: task_id
    )
    render json: { task_id: task_id }, status: :accepted
  end

  def reply_suggestion_status
    cache_key = Captain::Tasks::ReplySuggestionJob.cache_key_for(params[:task_id])
    raw_payload = Redis::Alfred.get(cache_key)
    return render json: { status: 'pending' }, status: :accepted if raw_payload.nil?

    Redis::Alfred.delete(cache_key)
    payload = JSON.parse(raw_payload)
    if payload['error']
      render json: { error: payload['error'] }, status: :unprocessable_content
    else
      render json: { message: payload['message'], follow_up_context: payload['follow_up_context'] }.compact
    end
  end

  def label_suggestion
    result = Captain::LabelSuggestionService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def follow_up
    result = Captain::FollowUpService.new(
      account: Current.account,
      follow_up_context: params[:follow_up_context]&.to_unsafe_h,
      user_message: params[:message],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  private

  def render_result(result)
    if result.nil?
      render json: { message: nil }
    elsif result[:error]
      render json: { error: result[:error] }, status: :unprocessable_content
    else
      response_data = { message: result[:message] }
      response_data[:follow_up_context] = result[:follow_up_context] if result[:follow_up_context]
      render json: response_data
    end
  end

  def check_authorization
    authorize(:'captain/tasks')
  end
end

Api::V1::Accounts::Captain::TasksController.prepend_mod_with('Api::V1::Accounts::Captain::TasksController')

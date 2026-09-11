# frozen_string_literal: true

class Captain::Tasks::ReplySuggestionJob < ApplicationJob
  CACHE_KEY_PREFIX = 'captain:tasks:reply_suggestion'
  RESULT_TTL = 10.minutes

  def self.cache_key_for(task_id)
    "#{CACHE_KEY_PREFIX}:#{task_id}"
  end

  def perform(account_id:, conversation_display_id:, user_id:, task_id:)
    result = Captain::AsyncReplySuggestionService.new(
      account: Account.find(account_id),
      conversation_display_id: conversation_display_id,
      user: User.find(user_id)
    ).perform

    Rails.cache.write(self.class.cache_key_for(task_id), result_payload(result), expires_in: RESULT_TTL)
  rescue ActiveRecord::RecordNotFound => e
    Rails.cache.write(self.class.cache_key_for(task_id), { status: 'failed', error: e.message }, expires_in: RESULT_TTL)
  end

  private

  def result_payload(result)
    return { status: 'failed', error: result[:error] } if result[:error]

    { status: 'completed', message: result[:message], follow_up_context: result[:follow_up_context] }.compact
  end
end

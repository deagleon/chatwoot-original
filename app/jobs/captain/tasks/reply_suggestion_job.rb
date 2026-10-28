# frozen_string_literal: true

class Captain::Tasks::ReplySuggestionJob < ApplicationJob
  queue_as :default

  CACHE_KEY_PREFIX = 'captain:tasks:reply_suggestion'
  RESULT_TTL = 10.minutes.to_i

  def self.cache_key_for(task_id)
    "#{CACHE_KEY_PREFIX}:#{task_id}"
  end

  def perform(account_id:, conversation_display_id:, user_id:, task_id:)
    result = Captain::AsyncReplySuggestionService.new(
      account: Account.find(account_id),
      conversation_display_id: conversation_display_id,
      user: User.find(user_id)
    ).perform

    write_result(task_id, result_payload(result))
  rescue ActiveRecord::RecordNotFound => e
    write_result(task_id, { 'status' => 'failed', 'error' => e.message })
  end

  private

  # NOTE: results go to shared Redis, never Rails.cache. Web and Sidekiq run
  # in separate containers with isolated filesystems, so the default file
  # store would make every status poll miss and hang the client forever.
  def write_result(task_id, payload)
    Redis::Alfred.setex(self.class.cache_key_for(task_id), payload.to_json, RESULT_TTL)
  end

  def result_payload(result)
    return { 'status' => 'failed', 'error' => result[:error] } if result[:error]

    { 'status' => 'completed', 'message' => result[:message], 'follow_up_context' => result[:follow_up_context] }.compact
  end
end

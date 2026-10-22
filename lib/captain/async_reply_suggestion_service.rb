class Captain::AsyncReplySuggestionService < Captain::ReplySuggestionService
  private

  # Background execution: no rack-timeout wall, so allow slow-but-good
  # responses instead of failing fast like the sync path.
  def request_timeout
    55
  end
end

class Captain::ReplySuggestionService < Captain::BaseTaskService
  # Generous ceiling for a chat reply: clips pathological completions,
  # bounding tail latency and cost per generation.
  REPLY_SUGGESTION_MAX_TOKENS = 1000

  pattr_initialize [:account!, :conversation_display_id!, :user!]

  def perform
    return { error: I18n.t('captain.conversation_not_found') } if conversation.nil?

    make_api_call(
      feature: 'editor',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: formatted_conversation }
      ]
    )
  end

  private

  def chat_params
    { max_tokens: REPLY_SUGGESTION_MAX_TOKENS }
  end

  def system_prompt
    template = prompt_from_file('reply')
    render_liquid_template(template, prompt_variables)
  end

  def prompt_variables
    {
      'channel_type' => conversation.inbox.channel_type,
      'agent_name' => user.name,
      'agent_signature' => user.message_signature.presence
    }
  end

  def render_liquid_template(template_content, variables = {})
    Liquid::Template.parse(template_content).render(variables)
  end

  def formatted_conversation
    LlmFormatter::ConversationLlmFormatter.new(conversation).format(token_limit: TOKEN_LIMIT)
  end

  def event_name
    'reply_suggestion'
  end

  def use_account_openai_hook?
    true
  end
end

Captain::ReplySuggestionService.prepend_mod_with('Captain::ReplySuggestionService')

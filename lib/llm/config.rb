require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    def with_api_key(api_key, api_base: nil)
      initialize!
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = api_base
        # OpenRouter is used as an OpenAI-compatible gateway; models whose
        # registry provider is "openrouter" require these keys.
        config.openrouter_api_key = api_key
        config.openrouter_api_base = api_base
      end

      yield context
    end

    # Creates a chat for the given model, falling back to assume_model_exists
    # when the model is not in the local registry (e.g. newly released
    # OpenRouter models). The model id is then sent to the configured endpoint
    # as-is instead of raising "Unknown model".
    def chat(model:, context: nil, **)
      build_chat(context, model, **)
    rescue RubyLLM::ModelNotFoundError
      build_chat(context, model, provider: fallback_provider, assume_model_exists: true, **)
    end

    private

    def build_chat(context, model, **)
      context ? context.chat(model: model, **) : RubyLLM.chat(model: model, **)
    end

    def fallback_provider
      openai_endpoint.to_s.include?('openrouter') ? :openrouter : :openai
    end

    def configure_ruby_llm
      RubyLLM.configure do |config|
        apply_system_credentials(config)
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    def apply_system_credentials(config)
      api_key = system_api_key
      endpoint = openai_endpoint&.chomp('/')
      config.openai_api_key = api_key if api_key.present?
      config.openai_api_base = endpoint if endpoint.present?
      config.openrouter_api_key = api_key if api_key.present?
      config.openrouter_api_base = "#{endpoint}/v1" if endpoint.present?
    end

    def system_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    end
  end
end

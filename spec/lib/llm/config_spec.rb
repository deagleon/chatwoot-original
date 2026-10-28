require 'rails_helper'

RSpec.describe Llm::Config do
  describe '.configure_ruby_llm' do
    it 'adds the API version to the configured OpenAI endpoint' do
      original_base = RubyLLM.config.openai_api_base
      InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT').update!(value: 'https://example.test/')

      described_class.send(:configure_ruby_llm)

      expect(RubyLLM.config.openai_api_base).to eq('https://example.test/v1')
    ensure
      RubyLLM.configure { |config| config.openai_api_base = original_base }
    end
  end

  describe '.with_api_key' do
    it 'fails fast below the rack timeout by default' do
      described_class.with_api_key('k', api_base: 'https://x/v1') do |context|
        expect(context.config.request_timeout).to eq(12)
        expect(context.config.max_retries).to eq(0)
      end
    end

    it 'allows overriding the timeout when the service timeout differs' do
      described_class.with_api_key('k', api_base: 'https://x/v1', request_timeout: 25, max_retries: 0) do |context|
        expect(context.config.request_timeout).to eq(25)
        expect(context.config.max_retries).to eq(0)
      end
    end
  end
end

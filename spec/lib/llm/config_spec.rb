# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::Config do
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

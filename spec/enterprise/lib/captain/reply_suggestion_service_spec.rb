# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::ReplySuggestionService do
  describe '#use_search_tool?' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, account: account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:service) do
      described_class.new(account: account, conversation_display_id: conversation.display_id, user: agent)
    end

    it 'returns true when captain_integration is enabled' do
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with('captain_integration').and_return(true)

      expect(service.send(:use_search_tool?)).to be(true)
    end

    it 'returns false when captain_integration is disabled' do
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with('captain_integration').and_return(false)

      expect(service.send(:use_search_tool?)).to be(false)
    end
  end
end

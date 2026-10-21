require 'rails_helper'

RSpec.describe Captain::ReplySuggestionService do
  describe '#use_search_tool?' do
    subject(:use_search_tool?) { service.send(:use_search_tool?) }

    let(:account) { create(:account) }
    let(:service) { described_class.new(account: account, conversation_display_id: 1, user: nil) }

    context 'when Captain is enabled for the account' do
      before { account.enable_features!('captain_integration') }

      it { is_expected.to be(true) }
    end

    context 'when Captain is disabled for the account' do
      before { account.disable_features!('captain_integration') }

      it { is_expected.to be(false) }
    end
  end
end

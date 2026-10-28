require 'rails_helper'

describe Conversations::StageFilterService do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:pipeline) { create(:pipeline, account: account) }
  let!(:stage) { pipeline.pipeline_stages.first }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  let!(:older_conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: admin, pipeline_stage: stage)
  end
  let!(:newer_conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: admin, pipeline_stage: stage)
  end

  before do
    create(:inbox_member, user: admin, inbox: inbox)
    # Force distinct pipeline_stage_changed_at values so FIFO ordering is deterministic
    older_conversation.update!(pipeline_stage_changed_at: 2.hours.ago)
    newer_conversation.update!(pipeline_stage_changed_at: 1.hour.ago)
  end

  describe '#perform' do
    it 'returns only conversations in the given stage' do
      other_stage = pipeline.pipeline_stages.second
      create(:conversation, account: account, inbox: inbox, pipeline_stage: other_stage)

      result = described_class.new({ page: 1 }, admin, account, stage).perform

      expect(result[:conversations].pluck(:id)).to contain_exactly(older_conversation.id, newer_conversation.id)
    end

    it 'orders conversations by pipeline_stage_changed_at ASC (FIFO)' do
      result = described_class.new({ page: 1 }, admin, account, stage).perform

      expect(result[:conversations].first.id).to eq(older_conversation.id)
      expect(result[:conversations].second.id).to eq(newer_conversation.id)
    end

    it 'returns the total count' do
      result = described_class.new({ page: 1 }, admin, account, stage).perform
      expect(result[:count]).to eq(2)
    end

    it 'filters by contact name via q' do
      older_conversation.contact.update!(name: 'Alice Unique')
      result = described_class.new({ page: 1, q: 'Alice Unique' }, admin, account, stage).perform

      expect(result[:conversations].pluck(:id)).to eq([older_conversation.id])
    end

    it 'filters by message snippet via q' do
      create(:message, account: account, inbox: inbox, conversation: older_conversation, content: 'snippet unique text')
      result = described_class.new({ page: 1, q: 'snippet unique' }, admin, account, stage).perform

      expect(result[:conversations].pluck(:id)).to include(older_conversation.id)
      expect(result[:conversations].pluck(:id)).not_to include(newer_conversation.id)
    end

    it 'returns empty when no conversations match the stage' do
      empty_stage = create(:pipeline_stage, pipeline: pipeline, name: 'Empty', position: 99)
      result = described_class.new({ page: 1 }, admin, account, empty_stage).perform

      expect(result[:conversations]).to be_empty
      expect(result[:count]).to eq(0)
    end
  end
end

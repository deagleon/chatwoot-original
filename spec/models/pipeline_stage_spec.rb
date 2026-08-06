# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PipelineStage do
  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:stage) { pipeline.pipeline_stages.first }

  describe 'associations' do
    it { is_expected.to belong_to(:pipeline) }
    it { is_expected.to have_many(:conversations).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:position) }

    it 'validates position uniqueness per pipeline' do
      duplicate = pipeline.pipeline_stages.build(name: 'Duplicate', position: stage.position)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:position]).to be_present
    end
  end

  describe '.with_conversations_count' do
    it 'returns conversations_count for each stage' do
      create(:conversation, account: account, pipeline_stage: stage)
      create(:conversation, account: account, pipeline_stage: stage)

      stages = described_class.with_conversations_count.where(pipeline_id: pipeline.id)
      found = stages.find { |s| s.id == stage.id }
      expect(found.conversations_count).to eq(2)
    end
  end

  describe '#conversations_count' do
    it 'returns count from scope attribute when loaded' do
      loaded = described_class.with_conversations_count.find(stage.id)
      expect(loaded.conversations_count).to eq(0)
    end

    it 'falls back to actual count when not loaded via scope' do
      create(:conversation, account: account, pipeline_stage: stage)
      expect(stage.conversations_count).to eq(1)
    end
  end

  describe '#reorder!' do
    it 'updates position' do
      stage.reorder!(5)
      expect(stage.reload.position).to eq(5)
    end
  end

  describe 'destruction' do
    let!(:conversation) { create(:conversation, account: account, pipeline_stage: stage) }

    it 'blocks destroy when conversations exist' do
      expect { stage.destroy }.not_to change(described_class, :count)
      expect(stage.errors[:base]).to be_present
    end

    it 'allows destroy when no conversations exist' do
      conversation.update!(pipeline_stage_id: nil)
      expect { described_class.find(stage.id).destroy }.to change(described_class, :count).by(-1)
    end
  end
end

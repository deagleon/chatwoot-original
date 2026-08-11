# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pipeline do
  let(:account) { create(:account) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:pipeline_stages).dependent(:destroy_async) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe 'scopes' do
    let!(:active_pipeline) { create(:pipeline, account: account) }
    let!(:archived_pipeline) { create(:pipeline, account: account, archived_at: Time.current) }

    it 'returns active pipelines' do
      expect(described_class.active).to include(active_pipeline)
      expect(described_class.active).not_to include(archived_pipeline)
    end
  end

  describe 'default stages creation' do
    let!(:pipeline) { create(:pipeline, account: account) }

    it 'creates 4 default stages' do
      expect(pipeline.pipeline_stages.count).to eq(4)
    end

    it 'creates stages with correct names and positions' do
      stages = pipeline.pipeline_stages.order(:position)
      expect(stages.map(&:name)).to eq(%w[Pendente Follow-up Proposta Finalizado])
      expect(stages.map(&:position)).to eq([1, 2, 3, 4])
    end

    it 'creates stages in the same transaction' do
      invalid_pipeline = build(:pipeline, account: account, name: nil)
      expect { invalid_pipeline.save! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(PipelineStage.count).to eq(pipeline.pipeline_stages.count)
    end
  end

  describe '#archive!' do
    let(:pipeline) { create(:pipeline, account: account) }

    it 'sets archived_at' do
      pipeline.archive!
      expect(pipeline.archived_at).to be_present
    end

    it 'does not dissociate conversations from its stages' do
      stage = pipeline.pipeline_stages.first
      conversation = create(:conversation, account: account, pipeline_stage: stage)
      pipeline.archive!
      expect(conversation.reload.pipeline_stage_id).to eq(stage.id)
    end
  end

  describe '#archived?' do
    let(:pipeline) { create(:pipeline, account: account) }

    it 'returns false for active pipeline' do
      expect(pipeline.archived?).to be false
    end

    it 'returns true after archive!' do
      pipeline.archive!
      expect(pipeline.archived?).to be true
    end
  end
end

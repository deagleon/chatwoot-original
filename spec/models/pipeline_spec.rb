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

  describe 'custom stages via nested attributes' do
    it 'creates the provided stages and skips defaults' do
      pipeline = described_class.create!(
        account: account,
        name: 'Sales',
        pipeline_stages_attributes: [
          { name: 'Lead', color: '#FF0000', position: 1 },
          { name: 'Won', color: '#00FF00', position: 2 }
        ]
      )

      expect(pipeline.pipeline_stages.map(&:name)).to eq(%w[Lead Won])
      expect(pipeline.pipeline_stages.map(&:position)).to eq([1, 2])
      expect(pipeline.pipeline_stages.first.color).to eq('#FF0000')
    end

    it 'reorders and renames stages on update' do
      pipeline = create(:pipeline, account: account)
      first, second, third, fourth = pipeline.pipeline_stages.order(:position).to_a

      pipeline.update!(
        pipeline_stages_attributes: [
          { id: second.id, name: 'Renamed', color: second.color, position: 1 },
          { id: first.id, name: first.name, color: first.color, position: 2 },
          { id: third.id, name: third.name, color: third.color, position: 3 },
          { id: fourth.id, name: fourth.name, color: fourth.color, position: 4 }
        ]
      )

      expect(pipeline.pipeline_stages.reload.order(:position).map(&:id)).to eq([second.id, first.id, third.id, fourth.id])
      expect(pipeline.pipeline_stages.find(second.id).name).to eq('Renamed')
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

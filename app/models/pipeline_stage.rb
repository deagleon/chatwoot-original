# == Schema Information
#
# Table name: pipeline_stages
#
#  id          :bigint           not null, primary key
#  color       :string
#  name        :string           not null
#  position    :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  pipeline_id :bigint           not null
#
# Indexes
#
#  index_pipeline_stages_on_pipeline_id               (pipeline_id)
#  index_pipeline_stages_on_pipeline_id_and_position  (pipeline_id,position) UNIQUE
#
class PipelineStage < ApplicationRecord
  belongs_to :pipeline
  has_many :conversations, dependent: :restrict_with_error

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :pipeline_id }

  scope :with_conversations_count, lambda {
    left_joins(:conversations)
      .select('pipeline_stages.*, COUNT(conversations.id) AS conversations_count')
      .group('pipeline_stages.id')
  }

  def conversations_count
    self[:conversations_count] || conversations.count
  end

  def reorder!(new_position)
    update!(position: new_position)
  end
end

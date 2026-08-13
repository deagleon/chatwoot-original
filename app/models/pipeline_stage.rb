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
#  index_pipeline_stages_on_pipeline_id  (pipeline_id)
#
class PipelineStage < ApplicationRecord
  belongs_to :pipeline
  has_many :conversations, dependent: :restrict_with_error
  has_many :stage_cleanup_rules, dependent: :destroy

  validates :name, presence: true
  # Position is a display-order hint; duplicate positions are tolerated during
  # batch reorders (nested attribute updates swap adjacent stages mid-save).
  validates :position, presence: true

  def conversations_count
    self[:conversations_count] || conversations.count
  end
end

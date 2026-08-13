# == Schema Information
#
# Table name: pipelines
#
#  id          :bigint           not null, primary key
#  archived_at :datetime
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_pipelines_on_account_id   (account_id)
#  index_pipelines_on_archived_at  (archived_at)
#
class Pipeline < ApplicationRecord
  DEFAULT_STAGES = [
    { name: 'Pendente', color: '#6B7280' },
    { name: 'Follow-up', color: '#3B82F6' },
    { name: 'Proposta', color: '#F59E0B' },
    { name: 'Finalizado', color: '#10B981' }
  ].freeze

  belongs_to :account
  has_many :pipeline_stages, dependent: :destroy_async
  accepts_nested_attributes_for :pipeline_stages, allow_destroy: true

  validates :name, presence: true

  scope :active, -> { where(archived_at: nil) }

  after_create :create_default_stages!

  def archive!
    update!(archived_at: Time.current)
  end

  def archived?
    archived_at.present?
  end

  private

  def create_default_stages!
    # Custom stages are provided through nested attributes at creation; the
    # defaults only apply when the pipeline is created without any.
    return if pipeline_stages.any?

    DEFAULT_STAGES.each_with_index do |stage, index|
      pipeline_stages.create!(name: stage[:name], color: stage[:color], position: index + 1)
    end
  end
end

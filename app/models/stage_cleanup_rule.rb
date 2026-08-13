# == Schema Information
#
# Table name: stage_cleanup_rules
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(TRUE), not null
#  cleanup_time      :string           not null
#  last_run_on       :date
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  pipeline_stage_id :bigint           not null
#
# Indexes
#
#  index_stage_cleanup_rules_on_account_id         (account_id)
#  index_stage_cleanup_rules_on_pipeline_stage_id  (pipeline_stage_id)
#
class StageCleanupRule < ApplicationRecord
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  belongs_to :account
  belongs_to :pipeline_stage

  validates :cleanup_time, presence: true, format: { with: TIME_FORMAT }
  validate :pipeline_stage_must_belong_to_account

  scope :active, -> { where(active: true) }

  def timezone
    ActiveSupport::TimeZone[account.reporting_timezone] || 'UTC'
  end

  def local_now
    Time.current.in_time_zone(timezone)
  end

  def local_today
    local_now.to_date
  end

  def due?
    active? && local_now.strftime('%H:%M') >= cleanup_time && last_run_on != local_today
  end

  private

  def pipeline_stage_must_belong_to_account
    errors.add(:pipeline_stage, :invalid) unless pipeline_stage&.pipeline&.account_id == account_id
  end
end

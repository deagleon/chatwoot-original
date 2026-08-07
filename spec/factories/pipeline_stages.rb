# frozen_string_literal: true

FactoryBot.define do
  factory :pipeline_stage do
    pipeline
    sequence(:name) { |n| "Stage #{n}" }
    color { '#3B82F6' }
    position { 1 }
  end
end

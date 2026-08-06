# frozen_string_literal: true

FactoryBot.define do
  factory :pipeline do
    account
    sequence(:name) { |n| "Pipeline #{n}" }
  end
end

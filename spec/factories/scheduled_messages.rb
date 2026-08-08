FactoryBot.define do
  factory :scheduled_message do
    account
    conversation { association :conversation, account: account }
    created_by { association :user, account: account }
    content { 'Bom dia!' }
    scheduled_at { 1.hour.from_now }
    status { :pending }
  end
end

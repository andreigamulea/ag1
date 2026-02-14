FactoryBot.define do
  factory :invoice do
    order
    sequence(:invoice_number) { |n| n + 1000 }
    series { "AY" }
    emitted_at { Time.current }
  end
end

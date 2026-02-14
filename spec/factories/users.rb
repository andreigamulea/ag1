FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@test.com" }
    password { "password123" }
    active { true }
    role { 0 }

    trait :admin do
      role { 1 }
    end
  end
end

FactoryBot.define do
  factory :option_value do
    option_type
    sequence(:name) { |n| "Value #{n}" }
    sequence(:presentation) { |n| "Value #{n}" }
    position { 0 }
  end
end

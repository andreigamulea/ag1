FactoryBot.define do
  factory :option_type do
    sequence(:name) { |n| "OptionType #{n}" }
    sequence(:presentation) { |n| "Option Type #{n}" }
    position { 0 }
  end
end

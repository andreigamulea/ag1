FactoryBot.define do
  factory :variant_external_id do
    variant
    sequence(:source) { |n| "source#{n}" }
    source_account { 'default' }
    sequence(:external_id) { |n| "EXT-#{n}" }
  end
end

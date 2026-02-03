FactoryBot.define do
  factory :product_option_type do
    product
    option_type
    position { 0 }
  end
end

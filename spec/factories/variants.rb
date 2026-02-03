FactoryBot.define do
  factory :variant do
    product
    sequence(:sku) { |n| "VAR-SKU-#{n}" }
    price { 49.99 }
    stock { 10 }
    status { :active }
    vat_rate { 19 }
  end
end

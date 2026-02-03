FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "Product #{n}" }
    sequence(:slug) { |n| "product-#{n}" }
    sequence(:sku) { |n| "SKU-#{n}" }
    price { 99.99 }
    stock_status { :in_stock }
    product_type { :physical }
    delivery_method { :shipping }
    vat { 19 }
  end
end

FactoryBot.define do
  factory :order_item do
    order
    product
    quantity { 1 }
    price { 100.0 }
    vat { 19 }
    product_name { "Test Product" }
    unit_price { 100.0 }
  end
end

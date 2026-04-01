# app/services/order_item_builder.rb
# Construiește order items din coș și adaugă liniile speciale (discount, transport)

class OrderItemBuilder
  def initialize(order, cart, pricing_calculator)
    @order = order
    @cart = cart.transform_keys { |k| k.to_s.to_i }
    @pricing_calculator = pricing_calculator
  end

  # Adaugă toate itemurile din coș
  def build_all!
    product_ids = @cart.keys
    return false if product_ids.empty?

    products = Product.where(id: product_ids).index_by(&:id)

    @cart.each do |product_id, data|
      product = products[product_id]
      next unless product

      quantity = data["quantity"].to_i
      price = product.price
      total_price = price * quantity

      @order.order_items.build(
        product: product,
        product_name: product.name,
        quantity: quantity,
        price: price,
        vat: product.vat || 0,
        total_price: total_price
      )
    end

    true
  end

  # Adaugă linie de discount
  def add_discount_item(discount_amount)
    return if discount_amount <= 0

    @order.order_items.build(
      product: nil,
      product_name: "Discount",
      quantity: 1,
      price: -discount_amount,
      vat: 0,
      total_price: -discount_amount
    )
  end

  # Adaugă linie de transport
  def add_shipping_item(shipping_cost)
    @order.order_items.build(
      product: nil,
      product_name: "Transport",
      quantity: 1,
      price: shipping_cost,
      vat: 0,
      total_price: shipping_cost
    )
  end
end

# app/services/pricing_calculator.rb
# Calculează toți parametrii de preț (subtotal, TVA, discount, transport, total)
# Consolidează logică din: ApplicationController, OrdersController, CartController

class PricingCalculator
  def initialize(cart, coupon = nil)
    @cart = cart.transform_keys { |k| k.to_s.to_i }
    @coupon = coupon
  end

  # Returnează subtotal produse (fără discount, fără transport)
  def subtotal
    @subtotal ||= products_for_cart.sum do |product_id, product|
      quantity = @cart[product_id].try(:[], "quantity").to_i
      product.price * quantity
    end
  end

  # Returnează discount din cupon
  def discount_amount
    @discount ||= begin
      return 0 unless @coupon.present?

      coupon = resolve_coupon(@coupon)
      return 0 unless coupon&.usable?

      target_subtotal = calculate_target_subtotal(coupon)
      target_quantity = calculate_target_quantity(coupon)

      # Verifică condiții
      return 0 unless valid_coupon_conditions?(coupon, target_subtotal, target_quantity)

      calculate_discount_value(coupon, target_subtotal)
    end
  end

  # Returnează TVA total pe toate produsele
  def vat_total
    @vat_total ||= products_for_cart.sum do |product_id, product|
      quantity = @cart[product_id].try(:[], "quantity").to_i
      calculate_vat_for_item(product.price, product.vat, quantity)
    end
  end

  # Returnează cost transport (0 dacă nu e produs fizic sau discount free_shipping)
  def shipping_cost
    @shipping_cost ||= begin
      return 0 unless has_physical_products?

      # Free shipping dacă cupon e aplicat și are free_shipping
      if @coupon.present?
        coupon = resolve_coupon(@coupon)
        return 0 if coupon&.free_shipping?
      end

      # 20 RON dacă subtotal < 200, altfel 0
      subtotal < 200 ? 20 : 0
    end
  end

  # Returnează TOTAL: subtotal - discount + transport
  def total
    [subtotal - discount_amount + shipping_cost, 0].max
  end

  # Returnează hash cu breakdown pentru afișare
  def breakdown
    {
      subtotal: subtotal.round(2),
      discount: discount_amount.round(2),
      vat: vat_total.round(2),
      shipping: shipping_cost.round(2),
      total: total.round(2)
    }
  end

  private

  # Preluează produsele din bază pe baza IDs din coș
  def products_for_cart
    @products_for_cart ||= begin
      product_ids = @cart.keys
      return {} if product_ids.empty?

      Product.where(id: product_ids).index_by(&:id)
    end
  end

  # Verifică dacă coșul conține produse din categoria "fizic"
  def has_physical_products?
    @has_physical_products ||= products_for_cart.values.any? do |product|
      product.categories.any? { |cat| cat.name.downcase == "fizic" }
    end
  end

  # Calculează subtotal-ul țintă pentru verificare cupon
  def calculate_target_subtotal(coupon)
    return subtotal if coupon.product_id.blank?

    product = products_for_cart[coupon.product_id]
    return 0 unless product

    quantity = @cart[coupon.product_id].try(:[], "quantity").to_i
    product.price * quantity
  end

  # Calculează cantitate-țintă pentru verificare cupon
  def calculate_target_quantity(coupon)
    return @cart.sum { |_, data| data["quantity"].to_i } if coupon.product_id.blank?

    @cart[coupon.product_id].try(:[], "quantity").to_i || 0
  end

  # Verifică condiții cupon (min. value, min. quantity, product-specific)
  def valid_coupon_conditions?(coupon, target_subtotal, target_quantity)
    valid = true
    valid &&= target_subtotal >= coupon.minimum_cart_value.to_f if coupon.minimum_cart_value.present?
    valid &&= target_quantity >= coupon.minimum_quantity.to_i if coupon.minimum_quantity.present?
    valid &&= @cart.key?(coupon.product_id) if coupon.product_id.present?
    valid
  end

  # Calculează valoarea discount-ului pe baza tipului cupon
  def calculate_discount_value(coupon, target_subtotal)
    case coupon.discount_type
    when "percentage"
      (target_subtotal * coupon.discount_value.to_f / 100.0).round(2)
    when "fixed"
      [coupon.discount_value.to_f, target_subtotal].min.round(2)
    else
      0
    end
  end

  # Calculează TVA pentru un singur item
  def calculate_vat_for_item(price, vat_rate, quantity)
    return 0 if vat_rate.to_f <= 0

    brut = price * quantity
    vat_rate_decimal = vat_rate.to_f / 100
    (brut * vat_rate_decimal / (1 + vat_rate_decimal)).round(2)
  end

  # Rezolvă cupon din parametru (poate fi object sau hash)
  def resolve_coupon(coupon_data)
    return coupon_data if coupon_data.is_a?(Coupon)

    if coupon_data.is_a?(Hash)
      Coupon.find_by(code: coupon_data["code"])
    end
  end
end

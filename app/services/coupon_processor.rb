# app/services/coupon_processor.rb
# Valideaza și aplică cupoane. Consolidează logică din: CartController, OrdersController, ApplicationController

class CouponProcessor
  attr_reader :coupon, :errors

  def initialize(coupon_code, cart, pricing_calculator = nil)
    @coupon_code = coupon_code&.strip&.upcase
    @cart = cart
    @pricing_calculator = pricing_calculator
    @coupon = nil
    @errors = []
  end

  # Validează cuponul complet (existență, activ, dată, utilizări)
  def valid?
    @errors = []

    return false if @coupon_code.blank?

    find_coupon
    return false if @coupon.nil?

    check_active
    check_expiration
    check_usage_limit
    check_conditions

    @errors.empty?
  end

  # Aplică cuponul (salvează în sesiune pentru later use)
  def apply!
    return false unless valid?

    {
      code: @coupon.code,
      discount_type: @coupon.discount_type,
      discount_value: @coupon.discount_value,
      product_id: @coupon.product_id,
      free_shipping: @coupon.free_shipping
    }
  end

  # Returnează detalii discount pentru afișare
  def discount_breakdown
    return { amount: 0 } if !valid? || !@pricing_calculator

    {
      amount: @pricing_calculator.discount_amount.round(2),
      coupon_code: @coupon.code,
      coupon_type: @coupon.discount_type
    }
  end

  private

  # Caută cuponul în bază
  def find_coupon
    @coupon = Coupon.find_by("UPPER(code) = ?", @coupon_code)
    @errors << "Cuponul nu există." if @coupon.nil?
  end

  # Verifică dacă cuponul e activ
  def check_active
    return if @coupon.nil?

    unless @coupon.active?
      @errors << "Cuponul este inactiv."
    end
  end

  # Verifică dacă cuponul e expirat
  def check_expiration
    return if @coupon.nil?

    now = Time.current
    if @coupon.starts_at.present? && now < @coupon.starts_at
      @errors << "Cuponul nu a început încă."
    end

    if @coupon.expires_at.present? && now > @coupon.expires_at
      @errors << "Cuponul a expirat."
    end
  end

  # Verifică limita de utilizări
  def check_usage_limit
    return if @coupon.nil?

    if @coupon.usage_limit.present? && @coupon.usage_count.to_i >= @coupon.usage_limit
      @errors << "Cuponul a fost deja utilizat de prea multe ori."
    end
  end

  # Verifică condiții specifice (min. cart value, min. quantity, product-specific)
  def check_conditions
    return if @coupon.nil?

    # Dacă e cupon product-specific, trebuie ca produsul să fie în coș
    if @coupon.product_id.present?
      unless @cart.key?(@coupon.product_id.to_s)
        @errors << "Cuponul se aplică doar pentru produsul specific care nu e în coș."
      end
    end
  end
end

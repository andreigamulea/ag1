class ApplicationController < ActionController::Base
  helper CdnHelper
  before_action :load_cart
  before_action :set_cart_totals

  before_action :set_cart_totals

def set_cart_totals
  @cart ||= session[:cart] || {}
  @cart_items_count = @cart.values.sum { |data| data["quantity"].to_i }

  @cart_products = Product.find(@cart.keys)
  @subtotal = @cart.sum do |product_id, data|
    product = Product.find_by(id: product_id)
    product ? product.price * data["quantity"].to_i : 0
  end

  @discount = 0
  if session[:applied_coupon]
    coupon = Coupon.find_by(code: session[:applied_coupon]["code"])
    if coupon.present? && coupon.active &&
       (coupon.starts_at.nil? || coupon.starts_at <= Time.current) &&
       (coupon.expires_at.nil? || coupon.expires_at >= Time.current)

      total_quantity = @cart.sum { |_id, data| data["quantity"].to_i }

      valid = true
      valid &&= @subtotal >= coupon.minimum_cart_value.to_f if coupon.minimum_cart_value.present?
      valid &&= total_quantity >= coupon.minimum_quantity.to_i if coupon.minimum_quantity.present?
      valid &&= @cart.keys.map(&:to_i).include?(coupon.product_id) if coupon.product_id.present?

      if valid
        if coupon.discount_type == "percentage"
          @discount = @subtotal * (coupon.discount_value.to_f / 100.0)
        elsif coupon.discount_type == "fixed"
          @discount = coupon.discount_value.to_f
        end
      end
    end
  end

  @cart_total = [@subtotal - @discount, 0].max
end

  private

  def load_cart
    session[:cart] ||= {}
    @cart = session[:cart]
  end

  # Devise: după login, atașează snapshot-ul la user
  def after_sign_in_path_for(resource)
    CartSnapshot.where(session_id: session.id.to_s, user_id: nil).update_all(user_id: resource.id)
    super
  end
end

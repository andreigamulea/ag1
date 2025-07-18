class ApplicationController < ActionController::Base
  helper CdnHelper
  before_action :load_cart
  before_action :set_cart_totals

  

def set_cart_totals
  Rails.logger.debug "=== set_cart_totals a fost apelat ==="

  @cart ||= session[:cart] || {}
  @cart_items_count = @cart.values.sum { |data| data["quantity"].to_i }

  # Caută toate produsele din coș
  product_ids = @cart.keys.map(&:to_i)
  @cart_products = Product.includes(:categories).where(id: product_ids).index_by(&:id)

  @subtotal = 0

  @cart.each do |product_id_str, data|
    product = @cart_products[product_id_str.to_i]
    next unless product
    @subtotal += product.price * data["quantity"].to_i
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
      valid &&= product_ids.include?(coupon.product_id) if coupon.product_id.present?

      if valid
        if coupon.discount_type == "percentage"
          @discount = @subtotal * (coupon.discount_value.to_f / 100.0)
        elsif coupon.discount_type == "fixed"
          @discount = coupon.discount_value.to_f
        end
      end
    end
  end

  produse_fizice = @cart_products.values.any? do |product|
    product.categories.any? { |cat| cat.name.downcase == "fizic" }
  end
 #aici modific costul transportului
  @shipping_cost = if produse_fizice && (@subtotal - @discount < 200)
                     20 # valoarea fixă pentru transport
                   else
                     0
                   end

 @cart_total = [@subtotal - @discount + @shipping_cost, 0].max

# adaugă aceste 3 în sesiune pentru acces ulterior
session[:shipping_cost] = @shipping_cost
session[:discount_value] = @discount
session[:cart_subtotal] = @subtotal




end

def reset_cart_session
  session[:cart] = {}
  session[:coupon_code] = nil
  session[:applied_coupon] = nil

  @cart = {}
  @cart_items_count = 0
  @subtotal = 0
  @discount = 0
  @shipping_cost = 0
  @total = 0
end

def calculate_totals_from_order
  items = @order.order_items

  @subtotal = items
                .where.not(product_name: ["Transport", "Discount"])
                .sum(&:total_price)

  @transport = items
                 .where(product_name: "Transport")
                 .sum(&:total_price)

  @discount = items
                .where(product_name: "Discount")
                .sum(&:total_price).abs # facem pozitiv

  @vat = @order.vat_amount || 0
  @total = @order.total || 0
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

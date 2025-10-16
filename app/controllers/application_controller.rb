class ApplicationController < ActionController::Base
  before_action :store_user_location!, if: :storable_location?
  protect_from_forgery with: :exception, prepend: true
  
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

        # Calculăm subtotal și quantity în funcție de dacă e produs specific
        if coupon.product_id.present?
          product_key = coupon.product_id.to_s
          found = @cart.key?(product_key)
          if found
            product = @cart_products[coupon.product_id]
            quantity = @cart[product_key]["quantity"].to_i
            target_subtotal = product ? product.price * quantity : 0
            target_quantity = quantity
          else
            target_subtotal = 0
            target_quantity = 0
          end
        else
          target_subtotal = @subtotal
          target_quantity = @cart.sum { |_id, data| data["quantity"].to_i }
        end

        valid = true
        valid &&= target_subtotal >= coupon.minimum_cart_value.to_f if coupon.minimum_cart_value.present?
        valid &&= target_quantity >= coupon.minimum_quantity.to_i if coupon.minimum_quantity.present?
        valid &&= product_ids.include?(coupon.product_id) if coupon.product_id.present?

        if valid
          if coupon.discount_type == "percentage"
            @discount = target_subtotal * (coupon.discount_value.to_f / 100.0)
          elsif coupon.discount_type == "fixed"
            @discount = [coupon.discount_value.to_f, target_subtotal].min
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

    if session[:applied_coupon] && valid && coupon.free_shipping
      @shipping_cost = 0
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

  # În ApplicationController, înlocuiește metoda calculate_totals_from_order cu aceasta:

def calculate_totals_from_order
  return unless @order.present?
  
  items = @order.order_items

  # Subtotal - exclude Transport și Discount
  @subtotal = items
                .where.not(product_name: ["Transport", "Discount"])
                .sum(&:total_price).to_f

  # Transport
  @transport = items
                 .where(product_name: "Transport")
                 .sum(&:total_price).to_f

  # Discount - IMPORTANT: suma va fi negativă în DB, deci o facem pozitivă cu .abs
  discount_sum = items
                   .where(product_name: "Discount")
                   .sum(&:total_price).to_f
  
  @discount = discount_sum.abs  # Convertim în pozitiv pentru afișare
  
  # Debugging
  Rails.logger.debug "=== calculate_totals_from_order DEBUG ==="
  Rails.logger.debug "Discount items: #{items.where(product_name: 'Discount').pluck(:product_name, :total_price).inspect}"
  Rails.logger.debug "Discount sum (raw): #{discount_sum}"
  Rails.logger.debug "@discount (abs): #{@discount}"

  @vat = @order.vat_amount || 0
  @total = @order.total || 0
  
  # Verificare finală
  Rails.logger.debug "Subtotal: #{@subtotal}, Transport: #{@transport}, Discount: #{@discount}, Total: #{@total}"
end

  private

  def load_cart
    session[:cart] ||= {}
    # Normalizăm toate cheile ca string-uri
    @cart = session[:cart].transform_keys(&:to_s)
    # Salvăm înapoi versiunea normalizată
    session[:cart] = @cart
  end

  # Devise: după login, atașează snapshot-ul la user
  def after_sign_in_path_for(resource)
    CartSnapshot.where(session_id: session.id.to_s, user_id: nil).update_all(user_id: resource.id)
    super
  end


  # ✅ Memorăm URL-ul doar pentru cererile GET non-AJAX și non-Devise
  def storable_location?
    request.get? && is_navigational_format? && !devise_controller? && !request.xhr?
  end

  # ✅ Salvăm ultima locație accesată
  def store_user_location!
    store_location_for(:user, request.fullpath)
  end

  # ✅ După login, redirecționează către ultima locație memorată
  def after_sign_in_path_for(resource_or_scope)
    stored_location_for(resource_or_scope) || super
  end
  def after_sign_out_path_for(_resource_or_scope)
    request.referer || root_path
  end
  
end
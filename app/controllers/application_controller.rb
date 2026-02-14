class ApplicationController < ActionController::Base
  before_action :store_user_location!, if: :storable_location?
  protect_from_forgery with: :exception, prepend: true

  helper CdnHelper
  before_action :load_cart
  before_action :set_cart_totals
  layout :choose_layout

  helper_method :parse_cart_key, :build_cart_key

  # Metoda pentru a alege layout-ul corespunzător
  def choose_layout
    if is_admin_page?
      'admin'
    elsif is_shop_page?
      'shop'
    else
      'application'
    end
  end

  # Identifică dacă pagina e de tip admin/CMS
  def is_admin_page?
    # Override în controllere specifice de admin
    false
  end

  # Identifică dacă pagina e de tip magazin (front-end)
  def is_shop_page?
    # Devise pages (login, forgot password, etc.) use shop layout
    return true if devise_controller?
    # Override în controllere specifice de shop
    false
  end

  def set_cart_totals
    Rails.logger.debug "=== set_cart_totals a fost apelat ==="

    @cart ||= session[:cart] || {}
    @cart_items_count = @cart.values.sum { |data| data["quantity"].to_i }

    ## Caută toate produsele și variantele din coș
    parsed_keys = @cart.keys.map { |k| parse_cart_key(k) }
    product_ids = parsed_keys.map { |pk| pk[:product_id].to_i }.uniq
    variant_ids = parsed_keys.map { |pk| pk[:variant_id]&.to_i }.compact.uniq

    @cart_products = Product.includes(:categories).where(id: product_ids).index_by(&:id)
    @cart_variants = variant_ids.any? ? Variant.where(id: variant_ids).index_by(&:id) : {}

    @subtotal = 0

    @cart.each do |key, data|
      parsed = parse_cart_key(key)
      product = @cart_products[parsed[:product_id].to_i]
      next unless product
      quantity = data["quantity"].to_i

      if parsed[:variant_id]
        variant = @cart_variants[parsed[:variant_id].to_i]
        @subtotal += (variant&.effective_price || product.effective_price) * quantity
      else
        @subtotal += product.effective_price * quantity
      end
    end

    @discount = 0
    if session[:applied_coupon]
      coupon = Coupon.find_by(code: session[:applied_coupon]["code"])
      if coupon.present? && coupon.active &&
         (coupon.starts_at.nil? || coupon.starts_at <= Time.current) &&
         (coupon.expires_at.nil? || coupon.expires_at >= Time.current)

        # Calculăm subtotal și quantity în funcție de dacă e produs specific
        if coupon.product_id.present?
          # Cauta toate cart entries pentru acest product (cu sau fara variante)
          matching_entries = @cart.select { |k, _| parse_cart_key(k)[:product_id].to_i == coupon.product_id }
          if matching_entries.any?
            product = @cart_products[coupon.product_id]
            target_quantity = matching_entries.sum { |_, d| d["quantity"].to_i }
            target_subtotal = 0
            matching_entries.each do |k, d|
              parsed = parse_cart_key(k)
              v = parsed[:variant_id] ? @cart_variants[parsed[:variant_id].to_i] : nil
              price = v&.effective_price || product&.effective_price || 0
              target_subtotal += price * d["quantity"].to_i
            end
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

  def parse_cart_key(key)
    key = key.to_s
    if key.include?("_v")
      parts = key.split("_v", 2)
      { product_id: parts[0], variant_id: parts[1] }
    else
      { product_id: key, variant_id: nil }
    end
  end

  def build_cart_key(product_id, variant_id = nil)
    variant_id.present? ? "#{product_id}_v#{variant_id}" : product_id.to_s
  end

  private

  def load_cart
    session[:cart] ||= {}
    # Normalizăm toate cheile ca string-uri
    @cart = session[:cart].transform_keys(&:to_s)

    # Cleanup: elimina entries cu variante invalide/inactive
    variant_keys = @cart.keys.select { |k| k.include?("_v") }
    if variant_keys.any?
      vids = variant_keys.map { |k| parse_cart_key(k)[:variant_id].to_i }
      valid_variants = Variant.where(id: vids, status: :active).pluck(:id, :product_id)
      valid_map = valid_variants.to_h  # { variant_id => product_id }

      variant_keys.each do |key|
        parsed = parse_cart_key(key)
        vid = parsed[:variant_id].to_i
        pid = parsed[:product_id].to_i
        # Elimina daca varianta nu exista, e inactiva, sau nu apartine produsului
        unless valid_map[vid] == pid
          @cart.delete(key)
        end
      end
    end

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
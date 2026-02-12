class CartController < ApplicationController
  # Cart is a shop page
  def is_shop_page?
    true
  end

  def index
    prepare_cart_variables
  end

  def add
    product_id = params[:product_id].to_s
    variant_id = params[:variant_id].presence
    quantity   = params[:quantity].to_i
    product    = Product.find(product_id)

    # Daca produsul are variante active, variant_id e obligatoriu
    if product.variants.active.exists?
      if variant_id.blank?
        redirect_back fallback_location: carti_path(product), alert: "Selecteaza o varianta."
        return
      end

      variant = product.variants.active.find_by(id: variant_id)
      unless variant
        redirect_back fallback_location: carti_path(product), alert: "Varianta selectata nu este disponibila."
        return
      end

      # Stoc verificat pe varianta
      available_stock = variant.stock
      cart_key = build_cart_key(product_id, variant_id)
    else
      variant = nil
      available_stock = product.stock
      cart_key = build_cart_key(product_id)
    end

    if product.track_inventory
      current_quantity = @cart[cart_key] ? @cart[cart_key]["quantity"] : 0
      new_quantity     = current_quantity + quantity
    else
      if available_stock <= 0
        redirect_back fallback_location: carti_path(product), alert: "Produsul nu mai este disponibil."
        return
      end

      current_quantity = @cart[cart_key] ? @cart[cart_key]["quantity"] : 0
      new_quantity     = current_quantity + quantity

      if new_quantity > available_stock
        new_quantity = available_stock
      end
    end

    @cart[cart_key] ||= { "quantity" => 0 }
    @cart[cart_key]["quantity"] = new_quantity
    save_cart
    save_snapshot

    redirect_to cart_index_path, notice: "Produs adaugat in cos."
  end

  def update
    product_id = params[:product_id].to_s
    quantity = params[:quantity].to_i
    if @cart[product_id]
      @cart[product_id]["quantity"] = quantity
      save_cart
      save_snapshot
    end
    redirect_to cart_index_path
  end

  # Nouă metodă pentru actualizare multiplă
  def update_all
    quantities = params[:quantities] || {}

    quantities.each do |cart_key, quantity|
      cart_key = cart_key.to_s
      quantity = quantity.to_i

      if @cart[cart_key] && quantity > 0
        parsed = parse_cart_key(cart_key)
        product = Product.find_by(id: parsed[:product_id])

        if product
          if parsed[:variant_id]
            variant = Variant.find_by(id: parsed[:variant_id])
            available_stock = variant&.stock || 0
          else
            available_stock = product.stock
          end

          if product.track_inventory
            @cart[cart_key]["quantity"] = quantity
          else
            @cart[cart_key]["quantity"] = [quantity, available_stock].min
          end
        end
      elsif quantity <= 0
        @cart.delete(cart_key)
      end
    end

    save_cart
    save_snapshot

    respond_to do |format|
      format.html { redirect_to cart_index_path, notice: "Cosul a fost actualizat." }
      format.json { render json: { success: true, message: "Cosul a fost actualizat." } }
    end
  end

  def remove
    # Accepts either cart_key (composite "42_v7") or product_id (legacy)
    cart_key = (params[:cart_key] || params[:product_id]).to_s

    @cart.delete(cart_key)
    # Legacy fallback: try integer key too
    @cart.delete(cart_key.to_i) if cart_key.match?(/\A\d+\z/)

    save_cart
    save_snapshot

    respond_to do |format|
      format.html { redirect_to cart_index_path, notice: "Produs eliminat din cos." }
      format.json { render json: { success: true, message: "Produs eliminat din cos." } }
    end
  end

  def clear
    @cart = {}
    save_cart
    CartSnapshot.where(session_id: session.id.to_s).destroy_all
  
    respond_to do |format|
      format.html { redirect_to cart_index_path, notice: "Coș golit." }
      format.json { render json: { success: true, message: "Coș golit." }, status: :ok }
    end
  end

  def apply_coupon
    code = params[:code].strip.upcase
    puts ">> aplicare cupon: #{code}"

    @coupon_errors = []

    coupon = Coupon.find_by("UPPER(code) = ?", code)

    if coupon.nil?
      @coupon_errors << "Cuponul nu există."
    end

    if coupon && !coupon.active
      @coupon_errors << "Cuponul este inactiv."
    end

    if coupon && !((coupon.starts_at.nil? || coupon.starts_at <= Time.current) &&
           (coupon.expires_at.nil? || coupon.expires_at >= Time.current))
      @coupon_errors << "Cuponul este expirat sau nu a început încă."
    end

    if coupon && coupon.usage_limit.present? && coupon.usage_count.to_i >= coupon.usage_limit
      @coupon_errors << "Cuponul a fost deja utilizat de prea multe ori."
    end

    if coupon
      # Calcul subtotal si quantity in functie de product_id
      if coupon.product_id.present?
        matching = @cart.select { |k, _| parse_cart_key(k)[:product_id].to_i == coupon.product_id }
        found = matching.any?
        if found
          product = Product.find_by(id: coupon.product_id)
          total_quantity = matching.sum { |_, d| d["quantity"].to_i }
          subtotal = product ? product.price * total_quantity : 0
        else
          subtotal = 0
          total_quantity = 0
        end
      else
        found = true
        subtotal = @cart.sum do |key, data|
          parsed = parse_cart_key(key)
          product = Product.find_by(id: parsed[:product_id])
          product ? product.price * data["quantity"].to_i : 0
        end
        total_quantity = @cart.sum { |_id, data| data["quantity"].to_i }
      end

      if coupon.minimum_cart_value.present? && subtotal < coupon.minimum_cart_value
        @coupon_errors << "Valoarea minimă a coșului (sau a produsului) nu este atinsă."
      end

      if coupon.minimum_quantity.present? && total_quantity < coupon.minimum_quantity
        @coupon_errors << "Numărul minim de produse (sau cantitatea produsului) nu este atins."
      end

      if coupon.product_id.present? && !found
        @coupon_errors << "Produsul specificat nu este în coș."
      end
    end

    if @coupon_errors.empty?
      # Salvare în sesiune
      session[:applied_coupon] = {
        "code" => coupon.code,
        "discount_type" => coupon.discount_type,
        "discount_value" => coupon.discount_value.to_f,
        "free_shipping" => coupon.free_shipping
      }

      session[:coupon_code] = coupon.code

      redirect_to cart_index_path, notice: "Cupon aplicat cu succes!"
    else
      prepare_cart_variables
      render :index
    end
  end

  def remove_coupon
    session.delete(:applied_coupon)
    session.delete(:coupon_code)
    redirect_to cart_index_path, notice: "Cuponul a fost eliminat."
  end

  private

  def prepare_cart_variables
    set_cart_totals
    @coupon_errors ||= []

    # Preload variants for cart entries
    variant_ids = @cart.keys.filter_map { |k| parse_cart_key(k)[:variant_id]&.to_i }
    variants_map = variant_ids.any? ? Variant.includes(:option_values).where(id: variant_ids).index_by(&:id) : {}

    # Build cart items with variant info
    parsed_keys = @cart.keys.map { |k| parse_cart_key(k) }
    product_ids = parsed_keys.map { |pk| pk[:product_id].to_i }.uniq
    products_map = Product.includes(:categories).where(id: product_ids).index_by(&:id)

    @cart_items = @cart.filter_map do |key, data|
      parsed = parse_cart_key(key)
      product = products_map[parsed[:product_id].to_i]
      next unless product

      variant = parsed[:variant_id] ? variants_map[parsed[:variant_id].to_i] : nil
      quantity = data["quantity"].to_i
      unit_price = variant&.price || product.price

      {
        cart_key: key,
        product: product,
        variant: variant,
        quantity: quantity,
        unit_price: unit_price,
        subtotal: unit_price * quantity
      }
    end

    @subtotal = @cart_items.sum { |item| item[:subtotal] }
    @discount = 0

    @has_physical = @cart_items.any? do |item|
      item[:product].categories.any? { |cat| cat.name.downcase == "fizic" }
    end

    @shipping_cost = (@has_physical && @subtotal < 200) ? 20 : 0

    if session[:applied_coupon]
      coupon_data = session[:applied_coupon]
      coupon = Coupon.find_by(code: coupon_data["code"])

      if coupon.present? &&
         coupon.active &&
         (coupon.starts_at.nil? || coupon.starts_at <= Time.current) &&
         (coupon.expires_at.nil? || coupon.expires_at >= Time.current)

        if coupon.product_id.present?
          target_items = @cart_items.select { |i| i[:product].id == coupon.product_id }
          target_subtotal = target_items.sum { |i| i[:subtotal] }
          target_quantity = target_items.sum { |i| i[:quantity] }
        else
          target_subtotal = @subtotal
          target_quantity = @cart_items.sum { |i| i[:quantity] }
        end

        valid = true

        if coupon.usage_limit.present? && coupon.usage_count.to_i >= coupon.usage_limit
          @coupon_errors << "Cuponul a fost deja utilizat de prea multe ori."
          valid = false
        end

        if coupon.minimum_cart_value.present? && target_subtotal < coupon.minimum_cart_value.to_f
          @coupon_errors << "Valoarea minima a cosului nu este atinsa."
          valid = false
        end

        if coupon.minimum_quantity.present? && target_quantity < coupon.minimum_quantity.to_i
          @coupon_errors << "Numarul minim de produse nu este atins."
          valid = false
        end

        if coupon.product_id.present? && target_quantity == 0
          @coupon_errors << "Produsul specificat nu este in cos."
          valid = false
        end

        if valid
          if coupon.discount_type == "percentage"
            @discount = target_subtotal * (coupon.discount_value.to_f / 100.0)
          elsif coupon.discount_type == "fixed"
            @discount = [coupon.discount_value.to_f, target_subtotal].min
          end
          @shipping_cost = 0 if coupon.free_shipping
        else
          session.delete(:applied_coupon)
          session.delete(:coupon_code)
        end
      else
        @coupon_errors << "Cuponul este inactiv sau expirat."
        session.delete(:applied_coupon)
        session.delete(:coupon_code)
      end
    end

    @total = [@subtotal - @discount + @shipping_cost, 0].max
  end

  def save_cart
    session[:cart] = @cart
  end

  def save_snapshot
    CartSnapshot.find_or_initialize_by(session_id: session.id.to_s).tap do |snap|
      snap.user = current_user if user_signed_in?
      snap.cart_data = @cart
      snap.email ||= current_user&.email
      snap.status = "active"
      snap.save
    end
  end
end
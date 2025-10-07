class CartController < ApplicationController
  
  def index
    set_cart_totals
  # Filtrează ID-urile valide
  @valid_product_ids = Product.where(id: @cart.keys).pluck(:id).map(&:to_s)
  @cart_items = Product.where(id: @valid_product_ids).map do |product|
    quantity = @cart[product.id.to_s]["quantity"]
    {
      product: product,
      quantity: quantity,
      subtotal: product.price * quantity
    }
  end

  @subtotal = @cart_items.sum { |item| item[:subtotal] }
  @discount = 0

  # Verificăm dacă există produse fizice în coș
  @has_physical = @cart_items.any? do |item|
    item[:product].categories.any? { |cat| cat.name.downcase == "fizic" }
  end

    # Cost transport: 20 lei dacă sunt produse fizice și total < 200
    #@shipping_cost = (@has_physical && @subtotal < 200) ? 30 : 0

    if session[:applied_coupon]
      coupon_data = session[:applied_coupon]
      coupon = Coupon.find_by(code: coupon_data["code"])

      if coupon.present? &&
         coupon.active &&
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
        else
          session.delete(:applied_coupon)
          session.delete(:coupon_code)
        end
      else
        session.delete(:applied_coupon)
        session.delete(:coupon_code)
      end
    end

    @total = [@subtotal - @discount + @shipping_cost, 0].max
  end

  def add
    product_id = params[:product_id].to_s
    quantity   = params[:quantity].to_i
    product    = Product.find(product_id)

    if product.track_inventory
      # ✅ Permitem oricât, chiar dacă stock <= 0
      current_quantity = @cart[product_id] ? @cart[product_id]["quantity"] : 0
      new_quantity     = current_quantity + quantity
      # aici nu limităm nimic
    else
      # ✅ Dacă nu se urmărește inventarul, respectăm strict stocul
      if product.stock <= 0
        redirect_to carti_path, alert: "Produsul nu mai este disponibil."
        return
      end

      current_quantity = @cart[product_id] ? @cart[product_id]["quantity"] : 0
      new_quantity     = current_quantity + quantity

      if new_quantity > product.stock
        new_quantity = product.stock
      end
    end

    @cart[product_id] ||= { "quantity" => 0 }
    @cart[product_id]["quantity"] = new_quantity
    save_cart
    save_snapshot

    redirect_to cart_index_path, notice: "Produs adăugat în coș."
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
    
    quantities.each do |product_id, quantity|
      product_id = product_id.to_s
      quantity = quantity.to_i
      
      if @cart[product_id] && quantity > 0
        product = Product.find_by(id: product_id)
        
        if product
          # Verificăm limitele de stoc dacă e cazul
          if product.track_inventory
            # Permitem orice cantitate
            @cart[product_id]["quantity"] = quantity
          else
            # Respectăm stocul disponibil
            if quantity > product.stock
              @cart[product_id]["quantity"] = product.stock
            else
              @cart[product_id]["quantity"] = quantity
            end
          end
        end
      elsif quantity <= 0
        # Dacă cantitatea e 0, eliminăm produsul
        @cart.delete(product_id)
      end
    end
    
    save_cart
    save_snapshot
    
    respond_to do |format|
      format.html { redirect_to cart_index_path, notice: "Coșul a fost actualizat." }
      format.json { render json: { success: true, message: "Coșul a fost actualizat." } }
    end
  end

  def remove
    product_id = params[:product_id].to_s
    Rails.logger.debug "=== REMOVE DEBUG ==="
    Rails.logger.debug "Product ID primit: #{product_id}"
    Rails.logger.debug "Product ID class: #{product_id.class}"
    Rails.logger.debug "Cart keys: #{@cart.keys.inspect}"
    Rails.logger.debug "Cart keys classes: #{@cart.keys.map(&:class).inspect}"
    Rails.logger.debug "Cart înainte: #{@cart.inspect}"
    
    # Încearcă să ștergi atât varianta string cât și integer
    deleted_string = @cart.delete(product_id)
    deleted_int = @cart.delete(product_id.to_i)
    
    Rails.logger.debug "Deleted as string (#{product_id}): #{deleted_string.inspect}"
    Rails.logger.debug "Deleted as int (#{product_id.to_i}): #{deleted_int.inspect}"
    Rails.logger.debug "Cart după: #{@cart.inspect}"
    
    save_cart
    save_snapshot
    
    respond_to do |format|
      format.html { redirect_to cart_index_path, notice: "Produs eliminat din coș." }
      format.json { render json: { success: true, message: "Produs eliminat din coș." } }
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

    coupon = Coupon.find_by("UPPER(code) = ?", code)

    if coupon.nil?
      redirect_to cart_index_path, alert: "Cuponul nu există."
      return
    end

    unless coupon.active && 
          (coupon.starts_at.nil? || coupon.starts_at <= Time.current) && 
          (coupon.expires_at.nil? || coupon.expires_at >= Time.current)
      puts ">> cupon inactiv sau expirat"
      redirect_to cart_index_path, alert: "Cuponul nu este valabil în această perioadă."
      return
    end

    if coupon.usage_limit.present? && coupon.usage_count.to_i >= coupon.usage_limit
      redirect_to cart_index_path, alert: "Cuponul a fost deja utilizat de prea multe ori."
      return
    end

    # Calcul subtotal actual
    subtotal = @cart.sum do |product_id, data|
      product = Product.find_by(id: product_id)
      product ? product.price * data["quantity"].to_i : 0
    end

    puts ">> subtotal: #{subtotal}"

    total_quantity = @cart.sum { |_id, data| data["quantity"].to_i }
    puts ">> total cantitate: #{total_quantity}"

    if coupon.minimum_cart_value.present? && subtotal < coupon.minimum_cart_value
      puts ">> valoare minimă nu este atinsă"
      redirect_to cart_index_path, alert: "Valoarea minimă a coșului nu este atinsă."
      return
    end

    if coupon.minimum_quantity.present? && total_quantity < coupon.minimum_quantity
      puts ">> cantitate minimă nu este atinsă"
      redirect_to cart_index_path, alert: "Numărul minim de produse nu este atins."
      return
    end

    if coupon.product_id.present?
      found = @cart.keys.map(&:to_i).include?(coupon.product_id)
      unless found
        redirect_to cart_index_path, alert: "Cuponul este valabil doar pentru un anumit produs."
        return
      end
    end

    # Salvare în sesiune
    session[:applied_coupon] = {
      "code" => coupon.code,
      "discount_type" => coupon.discount_type,
      "discount_value" => coupon.discount_value.to_f,
      "free_shipping" => coupon.free_shipping
    }

    session[:coupon_code] = coupon.code

    redirect_to cart_index_path, notice: "Cupon aplicat cu succes!"
  end

  def remove_coupon
    session.delete(:applied_coupon)
    session.delete(:coupon_code)
    redirect_to cart_index_path, notice: "Cuponul a fost eliminat."
  end

  private

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
class CartController < ApplicationController
  
def index
  @cart_items = Product.find(@cart.keys).map do |product|
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
  @shipping_cost = (@has_physical && @subtotal < 200) ? 20 : 0

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
    quantity = params[:quantity].to_i
    @cart[product_id] ||= { "quantity" => 0 }
    @cart[product_id]["quantity"] += quantity
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

  def remove
    product_id = params[:product_id].to_s
    @cart.delete(product_id)
    save_cart
    save_snapshot
    redirect_to cart_index_path
  end

  def clear
    @cart = {}
    save_cart
    CartSnapshot.where(session_id: session.id.to_s).destroy_all
    redirect_to cart_index_path, notice: "Coș golit."
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
  session.delete(:coupon_code) # <- adaugă asta
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

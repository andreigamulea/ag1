class OrdersController < ApplicationController
  

def new
  @order = Order.new

  if user_signed_in? && current_user.orders.exists?
    last_order = current_user.orders.order(placed_at: :desc).first
    @order.assign_attributes(last_order.slice(
      :first_name, :last_name, :company_name, :cui, :cnp,
      :email, :phone, :country, :county, :city, :postal_code,
      :street, :street_number, :block_details,
      :use_different_shipping,
      :shipping_first_name, :shipping_last_name, :shipping_company_name,
      :shipping_country, :shipping_county, :shipping_city,
      :shipping_postal_code, :shipping_street, :shipping_street_number,
      :shipping_block_details, :shipping_phone
    ))

    # Dacă ultima comandă NU avea livrare diferită, copiază câmpurile shipping din facturare (pentru consistență)
    unless @order.use_different_shipping
      @order.shipping_first_name = @order.first_name
      @order.shipping_last_name = @order.last_name
      @order.shipping_company_name = @order.company_name
      @order.shipping_country = @order.country
      @order.shipping_county = @order.county
      @order.shipping_city = @order.city
      @order.shipping_postal_code = @order.postal_code
      @order.shipping_street = @order.street
      @order.shipping_street_number = @order.street_number
      @order.shipping_block_details = @order.block_details
      @order.shipping_phone = @order.phone
    end
  else
    # Pentru user nou, populăm doar emailul din modelul User
    @order.email = current_user.email if user_signed_in?
  end

  # Păstrează params dacă vine din alt flow (ex: back button), dar prioritate la last_order
  @order.use_different_shipping = params[:use_different_shipping] if params[:use_different_shipping].present?

  @subtotal = calculate_subtotal
  @discount = calculate_discount
  @shipping_cost = calculate_shipping_cost # Presupun că ai o metodă pentru asta, bazată pe total etc.
  @total = [@subtotal - @discount + @shipping_cost, 0].max
end









def create
  @order = Order.new(order_params)
  @order.user = current_user if user_signed_in?
  @order.status = "pending"
  @order.placed_at = Time.current
  @order.use_different_shipping = params[:order][:use_different_shipping]

  apply_coupon_if_present

  # Copiem adresa de facturare în adresa de livrare dacă nu e bifată opțiunea
  unless @order.use_different_shipping == "1"
    @order.shipping_first_name    = @order.first_name
    @order.shipping_last_name     = @order.last_name
    @order.shipping_street        = @order.street
    @order.shipping_street_number = @order.street_number
    @order.shipping_block_details = @order.block_details
    @order.shipping_city          = @order.city
    @order.shipping_county        = @order.county
    @order.shipping_country       = @order.country
    @order.shipping_postal_code   = @order.postal_code
    @order.shipping_phone         = @order.phone
  end

  # Adaugă produsele comandate
  items_added = false
  @cart.each do |product_id, data|
    product = Product.find_by(id: product_id)
    unless product
      flash.now[:alert] = "Produs invalid în coș (ID: #{product_id})."
      render :new, status: :unprocessable_entity and return
    end

    quantity = data["quantity"].to_i

    @order.order_items.build(
      product: product,
      product_name: product.name,
      quantity: quantity,
      price: product.price,
      vat: product.vat || 0,
      total_price: product.price * quantity
    )
    items_added = true
  end

  if !items_added
    flash.now[:alert] = "Nu s-au putut adăuga produsele din coș. Verifică coșul."
    render :new, status: :unprocessable_entity and return
  end

  # === Adaugă linia de discount dacă există cupon
  if @order.coupon.present?
    subtotal = @order.order_items.sum(&:total_price)

    discount_value =
      if @order.coupon.discount_type == "percentage"
        (subtotal * (@order.coupon.discount_value.to_f / 100.0)).round(2)
      elsif @order.coupon.discount_type == "fixed"
        @order.coupon.discount_value.to_f
      else
        0
      end

    if discount_value > 0
      @order.order_items.build(
        product: nil,
        product_name: "Discount",
        quantity: 1,
        price: -discount_value,
        vat: 0,
        total_price: -discount_value
      )
    end
  end

  # === Adaugă linia de transport dacă e cazul
  transport_cost = session[:shipping_cost].to_f

  if transport_cost > 0
    @order.order_items.build(
      product: nil,
      product_name: "Transport",
      quantity: 1,
      price: transport_cost,
      vat: 0,
      total_price: transport_cost
    )
  end

  # Recalculare total final (inclusiv transport și discount)
  @order.total = @order.order_items.sum(&:total_price)
  @order.vat_amount = calculate_vat_total

  puts "Order valid? #{@order.valid?}"
  puts "Errors: #{@order.errors.full_messages.join(', ')}"

  if @order.save
    # Actualizează stocul dacă e cazul
    @order.order_items.each do |item|
      #if item.product && item.product.track_inventory
        #item.product.update(stock: item.product.stock - item.quantity)
      #end
    end

    # Marcăm cuponul ca utilizat
    @order.coupon.increment!(:usage_count) if @order.coupon.present?

    # Marcare snapshot ca „converted”
    CartSnapshot.where(session_id: session.id.to_s).update_all(status: "converted")

    # Lasă sesiunile active pt redirect spre plată, NU le ștergem încă
    # session[:cart] = {}
    # session[:coupon_code] = nil

    redirect_to thank_you_orders_path(id: @order.id)
  else
    flash.now[:alert] = "Comanda nu a putut fi plasată. Verifică datele și încearcă din nou."
    render :new, status: :unprocessable_entity
  end
end

 def thank_you
  @order = Order.find(params[:id])

  unless session[:cart].blank?
    reset_cart_session
    redirect_to thank_you_orders_path(id: @order.id) and return
  end

  calculate_totals_from_order
end






def set_order_totals
  return unless @order.present?

  @subtotal = @order.order_items.where.not(product_name: ["Transport", "Discount"]).sum(:total_price)
  @transport = @order.order_items.find_by(product_name: "Transport")&.total_price || 0
  @discount  = @order.order_items.find_by(product_name: "Discount")&.total_price || 0
  @total     = @order.order_items.sum(:total_price)

  puts "=== set_order_totals a fost apelat ==="
  puts "Subtotal: #{@subtotal}, Transport: #{@transport}, Discount: #{@discount}, Total: #{@total}"
end









def autocomplete_tara
  query = params[:q].to_s.strip
  if query.present?
    results = Tari.where("nume ILIKE ?", "%#{query}%").pluck(:nume)
    logger.info "Autocomplete_tara - Query: '#{query}', Total taris: #{Tari.count}, Sample nume: #{Tari.pluck(:nume).first(5).inspect}, Results: #{results.inspect}"
    render json: results, status: :ok
  else
    render json: [], status :ok
  end
end

def autocomplete_judet
  query = params[:q].to_s.strip
  if query.present?
    results = Judet.where("denjud ILIKE ?", "%#{query}%").pluck(:denjud)
    logger.info "Autocomplete_judet - Query: '#{query}', Total judets: #{Judet.count}, Sample denjud: #{Judet.pluck(:denjud).first(5).inspect}, Results: #{results.inspect}"
    render json: results, status: :ok
  else
    render json: [], status: :ok
  end
end

def autocomplete_localitate
  query = params[:q].to_s.strip
  filter = params[:filter].to_s.strip # Județul selectat
  if query.present? && filter.present?
    results = Localitati.where("denumire ILIKE ? AND denj ILIKE ?", "%#{query}%", "%#{filter}%").pluck(:denumire) # Added % for filter to make it case-insensitive
    logger.info "Autocomplete_localitate - Query: '#{query}', Filter: '#{filter}', Total localitatis: #{Localitati.count}, Sample denumire: #{Localitati.pluck(:denumire).first(5).inspect}, Results: #{results.inspect}"
    render json: results, status: :ok
  else
    render json: [], status: :ok
  end
end








  private

 

  def apply_coupon_if_present
    return unless session[:coupon_code].present?

    coupon = Coupon.find_by(code: session[:coupon_code].strip.downcase)
    return unless coupon&.active

    now = Time.current

    if (coupon.starts_at.nil? || now >= coupon.starts_at) &&
       (coupon.expires_at.nil? || now <= coupon.expires_at) &&
       (coupon.usage_limit.nil? || coupon.usage_count.to_i < coupon.usage_limit)

      @order.coupon = coupon
    end
  end

  def calculate_total
    @cart.sum do |product_id, data|
      product = Product.find_by(id: product_id)
      product ? product.price * data["quantity"].to_i : 0
    end
  end


  def calculate_subtotal
  @cart.sum do |product_id, data|
    product = Product.find_by(id: product_id)
    product ? product.price * data["quantity"].to_i : 0
  end
end

def calculate_total_after_discount
  subtotal = calculate_subtotal
  return subtotal unless @order.coupon

  coupon = @order.coupon
  discount = 0

  if coupon.discount_type == "percentage"
    discount = subtotal * coupon.discount_value.to_f / 100.0
  elsif coupon.discount_type == "fixed"
    discount = coupon.discount_value.to_f
  end

  discounted_total = subtotal - discount
  discounted_total < 0 ? 0 : discounted_total
end


  def calculate_vat_total
    @cart.sum do |product_id, data|
      product = Product.find_by(id: product_id)
      next 0 unless product
      quantity = data["quantity"].to_i
      subtotal = product.price * quantity
      vat_rate = product.vat.to_f
      subtotal * vat_rate / (100 + vat_rate)
    end
  end



def calculate_discount
  return 0 unless session[:applied_coupon]

  coupon_data = session[:applied_coupon]
  coupon = Coupon.find_by(code: coupon_data["code"])
  return 0 unless coupon && coupon.active &&
                  (coupon.starts_at.nil? || coupon.starts_at <= Time.current) &&
                  (coupon.expires_at.nil? || coupon.expires_at >= Time.current)

  subtotal = calculate_subtotal
  total_quantity = @cart.sum { |_id, data| data["quantity"].to_i }

  valid = true
  valid &&= subtotal >= coupon.minimum_cart_value.to_f if coupon.minimum_cart_value.present?
  valid &&= total_quantity >= coupon.minimum_quantity.to_i if coupon.minimum_quantity.present?
  valid &&= @cart.keys.map(&:to_i).include?(coupon.product_id) if coupon.product_id.present?

  if valid
    if coupon.discount_type == "percentage"
      return subtotal * (coupon.discount_value.to_f / 100.0)
    elsif coupon.discount_type == "fixed"
      return coupon.discount_value.to_f
    end
  end

  0
end

def calculate_shipping_cost
  produse_fizice = @cart.keys.any? do |product_id|
    product = Product.find_by(id: product_id)
    product&.categories&.any? { |cat| cat.name.downcase == "fizic" }
  end

  return 0 unless produse_fizice

  subtotal = calculate_subtotal
  subtotal >= 200 ? 0 : 20
end




  

  def order_params
  params.require(:order).permit(
    :first_name, :last_name, :company_name, :cui, :cnp,
    :address, :city, :county, :postal_code, :country,
    :street, :street_number, :block_details,
    :phone, :email, :use_different_shipping,
    :shipping_first_name, :shipping_last_name, :shipping_company_name,
    :shipping_country, :shipping_county, :shipping_city,
    :shipping_street, :shipping_street_number, :shipping_block_details,
    :shipping_postal_code, :shipping_phone,
    :notes
  )
end



 



end

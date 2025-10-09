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









# În OrdersController, înlocuiește metoda create cu aceasta (cu debugging îmbunătățit):

def create
  @order = Order.new(order_params)
  @order.user = current_user if user_signed_in?
  @order.status = "pending"
  @order.placed_at = Time.current
  @order.use_different_shipping = params[:order][:use_different_shipping]

  apply_coupon_if_present

  Rails.logger.debug "=== CREATE ORDER DEBUG ==="
  Rails.logger.debug "Coupon aplicat: #{@order.coupon.present? ? @order.coupon.code : 'NONE'}"

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

  # === Calculează subtotalul produselor (înainte de discount și transport)
  subtotal = @order.order_items.sum(&:total_price)
  Rails.logger.debug "Subtotal produse: #{subtotal}"

  # === Adaugă linia de discount dacă există cupon
  if @order.coupon.present?
    coupon = @order.coupon
    Rails.logger.debug "Procesare cupon: #{coupon.code}"

    target_subtotal = subtotal
    target_quantity = @order.order_items.sum(&:quantity)

    # Dacă cuponul e pentru un produs specific
    # Dacă cuponul e pentru un produs specific
if coupon.product_id.present?
  target_item = @order.order_items.find { |item| item.product_id == coupon.product_id }
  if target_item
    target_subtotal = target_item.total_price
    target_quantity = target_item.quantity
    Rails.logger.debug "Cupon specific produs ID #{coupon.product_id}: subtotal=#{target_subtotal}, qty=#{target_quantity}"
  else
    target_subtotal = 0
    target_quantity = 0
    Rails.logger.debug "Produs #{coupon.product_id} nu găsit în comandă"
  end
end

    # Calculează discount_value
    discount_value = 0
    if coupon.discount_type == "percentage"
      discount_value = (target_subtotal * (coupon.discount_value.to_f / 100.0)).round(2)
    elsif coupon.discount_type == "fixed"
      discount_value = [coupon.discount_value.to_f, target_subtotal].min
    end

    Rails.logger.debug "Discount calculat: #{discount_value} (tip: #{coupon.discount_type}, valoare: #{coupon.discount_value})"

    # Adaugă discount ca order_item DACĂ discount_value > 0
    if discount_value > 0
      @order.order_items.build(
        product: nil,
        product_name: "Discount",
        quantity: 1,
        price: -discount_value,
        vat: 0,
        total_price: -discount_value
      )
      Rails.logger.debug "✅ Discount item adăugat: -#{discount_value}"
    else
      Rails.logger.debug "⚠️ Discount value = 0, nu se adaugă item"
    end
  else
    Rails.logger.debug "❌ Nu există cupon aplicat"
  end

  # === Adaugă linia de transport dacă e cazul
  transport_cost = session[:shipping_cost].to_f
  Rails.logger.debug "Transport cost din sesiune: #{transport_cost}"

  if transport_cost > 0
    @order.order_items.build(
      product: nil,
      product_name: "Transport",
      quantity: 1,
      price: transport_cost,
      vat: 0,
      total_price: transport_cost
    )
    Rails.logger.debug "✅ Transport item adăugat: #{transport_cost}"
  else
    # Chiar dacă e 0, adăugăm pentru consistență
    @order.order_items.build(
      product: nil,
      product_name: "Transport",
      quantity: 1,
      price: 0,
      vat: 0,
      total_price: 0
    )
    Rails.logger.debug "✅ Transport gratuit adăugat"
  end

  # Recalculare total final (inclusiv transport și discount)
  @order.total = @order.order_items.sum(&:total_price)
  @order.vat_amount = calculate_vat_total

  Rails.logger.debug "Order items înainte de save:"
  @order.order_items.each do |item|
    Rails.logger.debug "  - #{item.product_name}: qty=#{item.quantity}, price=#{item.price}, total=#{item.total_price}"
  end
  Rails.logger.debug "Total final: #{@order.total}"

  if @order.save
    Rails.logger.debug "✅ Comanda salvată cu succes! ID: #{@order.id}"
    
    # Marcăm cuponul ca utilizat
    @order.coupon.increment!(:usage_count) if @order.coupon.present?

    # Marcare snapshot ca „converted"
    CartSnapshot.where(session_id: session.id.to_s).update_all(status: "converted")

    redirect_to thank_you_orders_path(id: @order.id)
  else
    Rails.logger.debug "❌ Eroare la salvare: #{@order.errors.full_messages.join(', ')}"
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
    render json: [], status: :ok
  end
end

def autocomplete_judet
  query = params[:q].to_s.strip
  if query.present? && query != '*'
    results = Judet.where("denjud ILIKE ?", "#{query}%").pluck(:denjud)
  else
    # Returnează toate județele când query e gol sau '*'
    results = Judet.order(:denjud).pluck(:denjud)
  end
  logger.info "Autocomplete_judet - Query: '#{query}', Total judets: #{Judet.count}, Results count: #{results.count}"
  render json: results, status: :ok
end

def autocomplete_localitate
  query = params[:q].to_s.strip
  filter = params[:filter].to_s.strip # Județul selectat
  
  if filter.present?
    if query.present? && query != '*'
      results = Localitati.where("denumire ILIKE ? AND denj ILIKE ?", "#{query}%", "%#{filter}%").pluck(:denumire)
    else
      # Returnează toate localitățile din județul respectiv
      results = Localitati.where("denj ILIKE ?", "%#{filter}%").order(:denumire).pluck(:denumire)
    end
    logger.info "Autocomplete_localitate - Query: '#{query}', Filter: '#{filter}', Results count: #{results.count}"
    render json: results, status: :ok
  else
    render json: [], status: :ok
  end
end






  private

 

  def apply_coupon_if_present
  return unless session[:coupon_code].present?

  coupon = Coupon.find_by("UPPER(code) = ?", session[:coupon_code].strip.upcase)
  return unless coupon&.active

  now = Time.current

  if (coupon.starts_at.nil? || now >= coupon.starts_at) &&
     (coupon.expires_at.nil? || now <= coupon.expires_at) &&
     (coupon.usage_limit.nil? || coupon.usage_count.to_i < coupon.usage_limit)

    @order.coupon = coupon
    Rails.logger.debug "✅ Cupon atașat la order: #{coupon.code}"
  else
    Rails.logger.debug "⚠️ Cupon invalid sau expirat"
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

  target_subtotal = subtotal
  if coupon.product_id.present?
    product = Product.find_by(id: coupon.product_id)
    quantity = @cart[coupon.product_id.to_s] ? @cart[coupon.product_id.to_s]["quantity"].to_i : 0
    target_subtotal = product ? product.price * quantity : 0
  end

  valid = true
  valid &&= target_subtotal >= coupon.minimum_cart_value.to_f if coupon.minimum_cart_value.present?
  valid &&= total_quantity >= coupon.minimum_quantity.to_i if coupon.minimum_quantity.present?
  valid &&= @cart.keys.map(&:to_i).include?(coupon.product_id) if coupon.product_id.present?

  if valid
    if coupon.discount_type == "percentage"
      return target_subtotal * (coupon.discount_value.to_f / 100.0)
    elsif coupon.discount_type == "fixed"
      return [coupon.discount_value.to_f, target_subtotal].min
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
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :authenticate_user!, only: [:index, :show_items, :invoice]
  before_action :set_order, only: [:show_items, :invoice]
  before_action :check_order_access, only: [:show_items, :invoice]
  def index
  if current_user.role == 1
    # Admin vede toate comenzile cu paginare
    @orders = Order.order(created_at: :desc).page(params[:page]).per(25)
  else
    # Utilizatorii normali văd doar comenzile lor cu paginare
    @orders = Order.where(user_id: current_user.id)
                   .order(created_at: :desc)
                   .page(params[:page]).per(25)
  end
end

  def show_items
    @order = Order.find(params[:id])
    @order_items = @order.order_items
    render partial: 'order_items', locals: { order_items: @order_items, order: @order }
  end

  def new
    @order = Order.new

    if user_signed_in? && current_user.orders.exists?
      last_order = current_user.orders.order(placed_at: :desc).first
      @order.assign_attributes(last_order.slice(
        :first_name, :last_name, :company_name, :cui, :cnp,
        :email, :phone, :country, :county, :city, :postal_code,
        :street, :street_number, :block_details,
        :shipping_first_name, :shipping_last_name, :shipping_company_name,
        :shipping_country, :shipping_county, :shipping_city,
        :shipping_postal_code, :shipping_street, :shipping_street_number,
        :shipping_block_details, :shipping_phone
      ))

      # Dacă ultima comandă NU avea livrare diferită, copiază câmpurile shipping din facturare
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

    # Păstrează params dacă vine din alt flow
    @order.use_different_shipping = params[:use_different_shipping] if params[:use_different_shipping].present?

    @subtotal = calculate_subtotal
    @discount = calculate_discount
    @shipping_cost = calculate_shipping_cost
    @total = [@subtotal - @discount + @shipping_cost, 0].max
  end

def create
  @order = Order.new(order_params)
  @order.user = current_user if user_signed_in?
  @order.status = "pending"
  @order.placed_at = Time.current
  @order.use_different_shipping = params[:order][:use_different_shipping] == "1"

  apply_coupon_if_present

  Rails.logger.debug "=== CREATE ORDER DEBUG ==="
  Rails.logger.debug "Coupon aplicat: #{@order.coupon.present? ? @order.coupon.code : 'NONE'}"

  # Copiem adresa de facturare în adresa de livrare dacă nu e bifată opțiunea
  unless @order.use_different_shipping
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

  # === Calculează subtotalul produselor (din items în memorie)
  subtotal = @order.order_items.sum(&:total_price)
  Rails.logger.debug "Subtotal produse: #{subtotal}"

  # === Adaugă linia de discount dacă există cupon
  if @order.coupon.present?
    coupon = @order.coupon
    Rails.logger.debug "Procesare cupon: #{coupon.code}"

    target_subtotal = subtotal
    target_quantity = @order.order_items.sum(&:quantity)

    if coupon.product_id.present?
      target_item = @order.order_items.find { |item| item.product_id == coupon.product_id }
      if target_item
        target_subtotal = target_item.total_price
        target_quantity = target_item.quantity
      else
        target_subtotal = 0
        target_quantity = 0
      end
    end

    discount_value = 0
    if coupon.discount_type == "percentage"
      discount_value = (target_subtotal * (coupon.discount_value.to_f / 100.0)).round(2)
    elsif coupon.discount_type == "fixed"
      discount_value = [coupon.discount_value.to_f, target_subtotal].min
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

  # === Adaugă linia de transport
  transport_cost = session[:shipping_cost].to_f
  @order.order_items.build(
    product: nil,
    product_name: "Transport",
    quantity: 1,
    price: transport_cost,
    vat: 0,
    total_price: transport_cost
  )

  # ✅ IMPORTANT: Calculează și SETEAZĂ valorile ÎNAINTE de primul save
  calculated_total = @order.order_items.sum(&:total_price)
  calculated_vat = calculate_vat_total
  
  @order.total = calculated_total
  @order.vat_amount = calculated_vat
  
  Rails.logger.debug "=== BEFORE SAVE: Total calculat: #{calculated_total}, VAT: #{calculated_vat} ==="

  # Primul save - salvează comanda cu valorile calculate
  if @order.save
    # ✅ DUPĂ save, recalculează din baza de date pentru a fi sigur
    @order.reload
    actual_total = @order.order_items.sum(&:total_price)
    actual_vat = calculate_vat_total
    
    # Actualizează comanda cu valorile reale din DB
    @order.update_columns(
      total: actual_total,
      vat_amount: actual_vat
    )
    
    Rails.logger.debug "=== AFTER SAVE: Total actualizat: #{actual_total}, VAT: #{actual_vat} ==="

    # Calculează discount_value pentru Stripe (absolut, pozitiv)
    discount_item = @order.order_items.find_by(product_name: "Discount")
    discount_amount = discount_item ? (discount_item.total_price.abs * 100).to_i : 0

    # Creează coupon temporar în Stripe dacă există discount
    stripe_coupon_id = nil
    if discount_amount > 0
      stripe_coupon = Stripe::Coupon.create(
        amount_off: discount_amount,
        currency: 'ron',
        duration: 'once',
        id: "discount_#{@order.id}"
      )
      stripe_coupon_id = stripe_coupon.id
    end

    # Construiește line_items doar pentru item-uri non-negative (exclude discount)
    line_items = @order.order_items.map do |item|
      next if item.price < 0  # Skip discount negativ

      Rails.logger.debug "=== DEBUG: Generare item pentru Stripe - Name: #{item.product_name}, Price: #{item.price}, Quantity: #{item.quantity}, Unit amount: #{(item.price.to_f * 100).to_i} ==="
      {
        price_data: {
          currency: 'ron',
          product_data: { name: item.product_name || 'Produs' },
          unit_amount: (item.price.to_f * 100).to_i
        },
        quantity: item.quantity
      }
    end.compact

    Rails.logger.debug "=== DEBUG: Line items final: #{line_items.inspect} ==="

    if line_items.blank?
      Rails.logger.error "=== DEBUG: Line items gol - nu se creează sesiune Stripe ==="
      flash.now[:alert] = "Coș gol sau eroare la items - nu se poate iniția plata."
      render :new, status: :unprocessable_entity and return
    end

    # Pregătește discounts array
    discounts = stripe_coupon_id ? [{ coupon: stripe_coupon_id }] : []

    stripe_session = Stripe::Checkout::Session.create(
      payment_method_types: ['card'],
      line_items: line_items,
      discounts: discounts,
      mode: 'payment',
      customer_email: @order.email,
      metadata: { order_id: @order.id },
      success_url: "#{request.base_url}/orders/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{request.base_url}/orders/new"
    )

    Rails.logger.debug "=== DEBUG: Session Stripe creată cu ID #{stripe_session.id}, Success URL: #{stripe_session.success_url} ==="

    @order.update(stripe_session_id: stripe_session.id)

    redirect_to stripe_session.url, allow_other_host: true
  else
    Rails.logger.error "=== DEBUG: Order nu s-a salvat - erori: #{@order.errors.full_messages} ==="
    flash.now[:alert] = "Comanda nu a putut fi plasată. Verifică datele."
    render :new, status: :unprocessable_entity
  end
end

  def success
    Rails.logger.debug "=== DEBUG success: Primit session_id: #{params[:session_id]} ==="

    stripe_session = Stripe::Checkout::Session.retrieve(params[:session_id])
    Rails.logger.debug "=== DEBUG success: Session retrieved: payment_status #{stripe_session.payment_status} ==="

    @order = Order.find_by(stripe_session_id: params[:session_id])
    Rails.logger.debug "=== DEBUG success: Order găsit ID #{@order&.id}, status #{@order&.status} ==="

    if stripe_session.payment_status == 'paid'
      reset_cart_session
      Rails.logger.debug "=== DEBUG success: Coș golit (session[:cart] = #{@cart.inspect}) ==="

      # Update opțional la 'paid' dacă webhook nu a făcut-o încă (fallback)
      if @order.pending?
        @order.update(status: 'paid')
        Rails.logger.debug "=== DEBUG success: Update fallback la paid ==="
      end

      redirect_to thank_you_orders_path(id: @order.id)
    else
      flash[:alert] = "Plata nu a fost confirmată."
      Rails.logger.warn "=== DEBUG success: Condiție eșuată - payment_status: #{stripe_session.payment_status} ==="
      redirect_to new_order_path and return
    end
  rescue Stripe::StripeError => e
    Rails.logger.error "=== DEBUG success error: #{e.message} ==="
    flash[:alert] = "Eroare la verificarea plății: #{e.message}."
    redirect_to new_order_path
  end

  def thank_you
    @order = Order.find(params[:id])

    Rails.logger.debug "=== DEBUG thank_you: Order ID #{@order.id}, status #{@order.status} ==="

    if @order.status != 'paid'
      flash[:alert] = "Comanda nu este confirmată încă."
      Rails.logger.warn "=== DEBUG thank_you: Status nu paid, redirect root ==="
      redirect_to root_path and return
    end

    if session[:cart].present?
      Rails.logger.warn "=== DEBUG thank_you: Coșul nu era gol, resetez acum ==="
      reset_cart_session
    else
      Rails.logger.debug "=== DEBUG thank_you: Coș deja gol ==="
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

  def invoice
  # Nu mai trebuie @order = Order.find(params[:id])
  # pentru că before_action :set_order face asta automat
  
  @invoice = @order.invoice  # Presupunând că ai has_one :invoice în model Order

  if @invoice.nil?
    flash[:alert] = "Factură disponibilă doar pentru ordine plătite."
    redirect_to orders_path and return
  end

  respond_to do |format|
    format.pdf do
      html = render_to_string(
        template: 'orders/invoice',
        layout: 'pdf',
        formats: [:pdf],
        locals: { order: @order, invoice: @invoice }  # Pasează invoice pentru numărul facturii
      )
      pdf = WickedPdf.new.pdf_from_string(html, encoding: 'UTF8')

      # Numele fișierului în formatul: Factura_240962_din_30.09.2025.pdf
      filename = "Factura_#{@invoice.invoice_number}_din_#{@invoice.emitted_at.strftime('%d.%m.%Y')}.pdf"

      send_data pdf,
                filename: filename,
                type: 'application/pdf',
                disposition: 'attachment'
    end
    format.xml do
      xml = render_to_string(
        template: 'orders/invoice',
        formats: [:xml],
        handlers: [:builder],
        locals: { order: @order, invoice: @invoice }
      )

      # Numele fișierului XML în formatul similar
      filename = "Factura_#{@invoice.invoice_number}_din_#{@invoice.emitted_at.strftime('%d.%m.%Y')}.xml"

      send_data xml,
                filename: filename,
                type: 'application/xml',
                disposition: 'attachment'
    end
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

  def set_order
    @order = Order.find(params[:id])
  end

def check_order_access
  # Admin poate vedea toate comenzile
  return if current_user.role == 1
  
  # Utilizatorii normali pot vedea doar comenzile lor
  unless @order.user_id == current_user.id
    redirect_to orders_path, alert: "Nu ai permisiunea să accesezi această comandă."
  end
end

end
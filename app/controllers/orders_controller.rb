class OrdersController < ApplicationController
  

  def new
  @order = Order.new

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

    apply_coupon_if_present

    @order.total = calculate_total_after_discount
    @order.vat_amount = calculate_vat_total

    if @order.save
      @cart.each do |product_id, data|
        product = Product.find_by(id: product_id)
        next unless product

        quantity = data["quantity"].to_i

        if product.track_inventory && product.stock.to_i < quantity
          next
        end

        @order.order_items.create!(
          product: product,
          product_name: product.name,
          quantity: quantity,
          unit_price: product.price,
          vat: product.vat,
          total_price: product.price * quantity
        )

        if product.track_inventory
          product.update(stock: product.stock - quantity)
        end
      end

      if @order.coupon.present?
        @order.coupon.increment!(:usage_count)
      end

      CartSnapshot.where(session_id: session.id.to_s).update_all(status: "converted")
      session[:cart] = {}
      session[:coupon_code] = nil

      redirect_to thank_you_orders_path(id: @order.id)
    else
      flash.now[:alert] = "Comanda nu a putut fi plasată. Verifică datele și încearcă din nou."
      render :new
    end
  end

  def thank_you
    @order = Order.find(params[:id])
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
      :email, :name, :phone, :address, :city, :postal_code, :country, :notes
    )
  end
end

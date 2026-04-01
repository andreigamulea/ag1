# app/services/payment_processor.rb
# Integreaza Stripe: creează sesiuni checkout, procesează webhook-uri, verific plăți

class PaymentProcessor
  def initialize(order)
    @order = order
  end

  # Creează o sesiune Stripe checkout
  def create_checkout_session
    line_items = build_line_items
    discounts = build_discounts

    if line_items.blank?
      raise "Nu putem crea o sesiune Stripe cu itemuri goale"
    end

    begin
      session = Stripe::Checkout::Session.create(
        payment_method_types: ['card'],
        line_items: line_items,
        discounts: discounts,
        mode: 'payment',
        customer_email: @order.email,
        metadata: { order_id: @order.id },
        success_url: "#{success_url}?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: cancel_url
      )

      Rails.logger.info "✅ Sesiune Stripe creată: #{session.id} pentru Order ##{@order.id}"
      session
    rescue Stripe::StripeError => e
      Rails.logger.error "❌ Eroare Stripe: #{e.message}"
      raise e
    end
  end

  # Verifică statutul plății dintr-o sesiune Stripe
  def verify_payment(session_id)
    begin
      stripe_session = Stripe::Checkout::Session.retrieve(session_id)

      if stripe_session.payment_status == 'paid'
        { success: true, order: @order }
      else
        { success: false, error: "Plata nu a fost confirmată. Status: #{stripe_session.payment_status}" }
      end
    rescue Stripe::StripeError => e
      Rails.logger.error "❌ Eroare verificare plată: #{e.message}"
      { success: false, error: "Eroare la verificarea plății: #{e.message}" }
    end
  end

  # Procesează webhook din Stripe (charge.succeeded, etc)
  def self.process_webhook(payload, signature)
    begin
      event = Stripe::Webhook.construct_event(payload, signature, ENV['STRIPE_WEBHOOK_SECRET'])

      case event.type
      when 'checkout.session.completed'
        handle_checkout_completed(event.data.object)
      when 'charge.refunded'
        handle_charge_refunded(event.data.object)
      end

      { success: true }
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "⚠️ Signatură webhook nevalidă: #{e.message}"
      { success: false, error: "Signatură webhook nevalidă" }
    rescue Stripe::StripeError => e
      Rails.logger.error "❌ Eroare Stripe webhook: #{e.message}"
      { success: false, error: e.message }
    end
  end

  private

  # Construiește line items pentru Stripe (doar produse pozitive)
  def build_line_items
    @order.order_items
      .reject { |item| item.price < 0 } # Exclude discount-uri
      .map do |item|
        {
          price_data: {
            currency: 'ron',
            product_data: { name: item.product_name || 'Produs' },
            unit_amount: (item.price.to_f * 100).to_i
          },
          quantity: item.quantity
        }
      end
  end

  # Construiește discounts array pentru Stripe
  def build_discounts
    discount_item = @order.order_items.find_by(product_name: 'Discount')
    return [] unless discount_item&.total_price&.negative?

    discount_amount = (discount_item.total_price.abs * 100).to_i

    begin
      stripe_coupon = Stripe::Coupon.create(
        amount_off: discount_amount,
        currency: 'ron',
        duration: 'once',
        id: "discount_order_#{@order.id}"
      )

      [{ coupon: stripe_coupon.id }]
    rescue Stripe::InvalidRequestError => e
      # Dacă coupon-ul deja există (de la tentative anterioare), îl refolosim
      if e.message.include?("already exists")
        [{ coupon: "discount_order_#{@order.id}" }]
      else
        Rails.logger.error "Eroare creare Stripe coupon: #{e.message}"
        []
      end
    end
  end

  # Callback pentru webhook checkout.session.completed
  def self.handle_checkout_completed(session)
    order = Order.find_by(stripe_session_id: session.id)
    return unless order

    order.update(status: 'paid')
    order.finalize_order!

    Rails.logger.info "✅ Comanda ##{order.id} marcată ca plătită (Stripe webhook)"
  end

  # Callback pentru webhook charge.refunded
  def self.handle_charge_refunded(charge)
    order = Order.find_by(stripe_session_id: charge.metadata&.dig('order_id'))
    return unless order

    order.update(status: 'refunded')
    Rails.logger.info "✅ Comanda ##{order.id} marcată ca rambursată (Stripe webhook)"
  end

  # URL-uri de redirect
  def success_url
    Rails.application.routes.url_helpers.success_orders_url
  end

  def cancel_url
    Rails.application.routes.url_helpers.new_order_url
  end
end

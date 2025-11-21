# app/controllers/stripe_webhooks_controller.rb
class StripeWebhooksController < ActionController::Base
  skip_before_action :verify_authenticity_token

  def create
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    event = nil

    begin
      webhook_secret = Rails.application.credentials.dig(:stripe, Rails.env.to_sym, :webhook_secret)
      event = Stripe::Webhook.construct_event(
        payload, sig_header, webhook_secret
      )

      Rails.logger.debug "Webhook event primit: #{event.type}"

      case event.type
      when 'checkout.session.completed'
        session = event.data.object
        order = Order.find_by(stripe_session_id: session.id)
        if order && session.payment_status == 'paid' && order.pending?
          order.update(status: 'paid')
          create_invoice_for_order(order)
          order.finalize_order! if order.respond_to?(:finalize_order!)

          # AICI TRIMITEM EMAIL-URILE – 100% ca la tine
          user = order.user

          # 1. Email către client + BCC către tine
          if user
            begin
              OrderMailer.payment_success(order).deliver_now
              Rails.logger.info "Email confirmare trimis clientului pentru comanda #{order.id}"
            rescue => e
              Rails.logger.error "Eroare email client comanda #{order.id}: #{e.message}"
              puts "Eroare trimitere email client: #{e.message}"
            end
          end

          # 2. Email doar către tine (opțional, dar util)
          begin
            OrderMailer.admin_new_order(order).deliver_now
            Rails.logger.info "Email admin trimis pentru comanda #{order.id}"
          rescue => e
            Rails.logger.error "Eroare email admin comanda #{order.id}: #{e.message}"
          end

          Rails.logger.debug "=== Webhook: Finalizat order #{order.id} cu factură și notificări ==="
        end
      when 'payment_intent.payment_failed'
        payment_intent = event.data.object
        order_id = payment_intent.metadata['order_id']
        order = Order.find_by(id: order_id)
        if order
          order.update(status: 'failed')
          # Opțional: trimite email
          OrderMailer.payment_failed(order).deliver_later if defined?(OrderMailer)
          Rails.logger.error "Plată eșuată pentru order #{order.id}: #{payment_intent.last_payment_error&.message}"
        end
      when 'charge.failed'
        Rails.logger.error "Plată eșuată pentru session: #{event.data.object.id}"
      end

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error "Webhook payload invalid: #{e.message}"
      head :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Webhook semnătură invalidă: #{e.message}"
      head :bad_request
      return
    rescue => e  # Eroare internă – return 500 pentru retry Stripe
      Rails.logger.error "Eroare generală în webhook: #{e.message}"
      head :internal_server_error
    end
  end

  private

  def create_invoice_for_order(order)
    last_invoice = Invoice.order(:invoice_number).last
    next_number = last_invoice ? last_invoice.invoice_number + 1 : 10001

    emitted_time = Time.current

    Invoice.create!(
      order: order,
      invoice_number: next_number,
      emitted_at: emitted_time,
      due_date: emitted_time,
      status: 'emitted',
      series: 'AYG',
      payment_method: 'card-Stripe',
      currency: 'RON',
      total: order.total,
      vat_amount: order.vat_amount,
      notes: order.notes
    )
  end
end
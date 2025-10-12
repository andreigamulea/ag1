# app/controllers/stripe_webhooks_controller.rb
class StripeWebhooksController < ActionController::Base
  skip_before_action :verify_authenticity_token

  def create
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    event = nil

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, Rails.application.credentials.dig(:stripe, Rails.env.to_sym, :webhook_secret)
      )
    rescue JSON::ParserError => e
      Rails.logger.error "Webhook payload invalid: #{e.message}"
      head :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Webhook semnătură invalidă: #{e.message}"
      head :bad_request
      return
    end

    Rails.logger.debug "Webhook event primit: #{event.type}"

    case event.type
    when 'checkout.session.completed'
      session = event.data.object
      order = Order.find_by(stripe_session_id: session.id)
      if order && session.payment_status == 'paid' && order.pending?
        order.update(status: 'paid')
        create_invoice_for_order(order)  # Creează factura
        order.finalize_order!  # Dacă există această metodă; altfel, șterge sau ajustează
        Rails.logger.debug "=== Webhook: Finalizat order #{order.id} cu factură generată ==="
      end
    when 'charge.failed'
      Rails.logger.error "Plată eșuată pentru session: #{event.data.object.id}"
    end

    head :ok
  rescue Stripe::StripeError => e
    Rails.logger.error "Eroare Stripe în webhook: #{e.message}"
    head :bad_request
  end

  private
def create_invoice_for_order(order)
  last_invoice = Invoice.order(:invoice_number).last
  next_number = last_invoice ? last_invoice.invoice_number + 1 : 10001

  emitted_time = Time.current  # Folosit pentru emitted_at și due_date

  Invoice.create!(
    order: order,
    invoice_number: next_number,
    emitted_at: emitted_time,
    due_date: emitted_time,  # Setat la aceeași valoare ca emitted_at
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
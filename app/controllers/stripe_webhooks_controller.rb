# app/controllers/stripe_webhooks_controller.rb
class StripeWebhooksController < ApplicationController
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

      Rails.logger.info "Webhook primit: #{event.type} (#{event.id})"

      case event.type
      
      when 'checkout.session.completed'
        session = event.data.object
        order = Order.find_by(stripe_session_id: session.id)
        
        if order && session.payment_status == 'paid' && order.pending?
          ActiveRecord::Base.transaction do
            order.update!(status: 'paid')
            create_invoice_for_order(order)
            order.finalize_order! if order.respond_to?(:finalize_order!)

            # Email către client
            begin
              OrderMailer.payment_success(order).deliver_now
              Rails.logger.info "✅ Email client trimis pentru comanda #{order.id}"
            rescue => e
              Rails.logger.error "❌ Eroare email client #{order.id}: #{e.message}"
            end

            # Email către admin
            begin
              OrderMailer.admin_new_order(order).deliver_now
              Rails.logger.info "✅ Email admin trimis pentru comanda #{order.id}"
            rescue => e
              Rails.logger.error "❌ Eroare email admin #{order.id}: #{e.message}"
            end

            Rails.logger.info "=== ✅ Order #{order.id} finalizat cu succes ==="
          end
        elsif order && !order.pending?
          Rails.logger.info "⚠️ Order #{order.id} deja procesat (status: #{order.status})"
        end

      when 'checkout.session.expired'
        session = event.data.object
        order = Order.find_by(stripe_session_id: session.id)
        
        if order && order.pending?
          order.update(status: 'expired')
          Rails.logger.info "⏰ Sesiune expirată pentru comanda #{order.id}"
        end

      when 'charge.failed'
        charge = event.data.object
        Rails.logger.error "❌ Plată eșuată: #{charge.id} - #{charge.failure_message}"

      when 'charge.refunded'
        charge = event.data.object
        Rails.logger.info "💰 Refund procesat: #{charge.id}"

      else
        Rails.logger.debug "⚠️ Webhook netratat: #{event.type}"
      end

      head :ok

    rescue JSON::ParserError => e
      Rails.logger.error "❌ Webhook payload invalid: #{e.message}"
      head :bad_request
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "❌ Webhook semnătură invalidă: #{e.message}"
      head :bad_request
    rescue => e
      Rails.logger.error "❌ Eroare generală în webhook: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      head :internal_server_error
    end
  end

  private

  def create_invoice_for_order(order)
    return if order.invoice.present? # Protecție împotriva duplicatelor

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
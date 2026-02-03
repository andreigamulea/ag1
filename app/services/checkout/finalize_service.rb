# frozen_string_literal: true

# app/services/checkout/finalize_service.rb
#
# Finalizare comandă: snapshot variant → order_item, decrement stock.
#
# LOCK ORDER: O → I → V (ORDER BY id) pentru deadlock safety
# FIX 8.6: ATOMIC - totul într-o singură tranzacție. Fie finalizezi complet, fie deloc.
#
# INVARIANTE:
# - Snapshot imutabil: variant_sku, variant_options_text, vat_rate_snapshot, line_total_gross, tax_amount
# - Decrement stock doar dacă variant activ + stock suficient
# - Fail-fast pe variant nil/inactive/stock insuficient

module Checkout
  class FinalizeService
    Result = Struct.new(:success, :order, :error, keyword_init: true) do
      def success? = success
    end

    class InsufficientStockError < StandardError; end
    class InactiveVariantError < StandardError; end
    class MissingVariantError < StandardError; end

    # @param order [Order] comanda de finalizat
    # @return [Result]
    def call(order:)
      # FIX 8.6: ATOMIC transaction - fie totul, fie nimic
      ActiveRecord::Base.transaction do
        # Lock order
        order.lock!

        # Lock order_items ORDER BY id
        items = order.order_items.order(:id).lock

        items.each do |item|
          next unless item.variant_id  # Skip items fără variant (ex: Transport, Discount)

          variant = Variant.lock.find_by(id: item.variant_id)

          # Fail-fast guards
          raise MissingVariantError, "Variant #{item.variant_id} not found for order_item #{item.id}" unless variant
          raise InactiveVariantError, "Variant #{variant.id} (#{variant.sku}) is inactive" unless variant.active?
          raise InsufficientStockError, "Variant #{variant.id} (#{variant.sku}) has stock #{variant.stock}, need #{item.quantity}" if variant.stock < item.quantity

          # Snapshot imutabil
          snapshot_attrs = {
            variant_sku: variant.sku,
            variant_options_text: variant.options_text,
            vat_rate_snapshot: variant.vat_rate,
            line_total_gross: (item.price * item.quantity).round(2),
            tax_amount: calculate_tax(item.price, item.quantity, variant.vat_rate)
          }
          item.update_columns(snapshot_attrs)

          # Decrement stock (update_column bypass callbacks)
          variant.update_column(:stock, variant.stock - item.quantity)
        end

        # Mark order as paid
        order.update_column(:status, 'paid')
      end

      Result.new(success: true, order: order.reload, error: nil)
    rescue MissingVariantError, InactiveVariantError, InsufficientStockError => e
      Result.new(success: false, order: order, error: e.message)
    end

    private

    def calculate_tax(unit_price, quantity, vat_rate)
      return 0.0 if vat_rate.to_f <= 0
      gross = (unit_price * quantity).to_f
      net = gross / (1 + vat_rate.to_f / 100)
      (gross - net).round(2)
    end
  end
end

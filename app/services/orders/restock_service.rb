# frozen_string_literal: true

# app/services/orders/restock_service.rb
#
# Reîncărcare stoc după cancel/refund comandă.
#
# LOCK ORDER: O → I → V (ORDER BY id) pentru deadlock safety
# FIX 8.7: IDEMPOTENCY GUARD - doar pentru order în status permis
#
# INVARIANTE:
# - Restock doar dacă order.cancelled? || order.refunded?
# - Doar order_items cu variant_id nenull

module Orders
  class RestockService
    Result = Struct.new(:success, :order, :restocked_count, :error, keyword_init: true) do
      def success? = success
    end

    # @param order [Order] comanda de anulat/restituit
    # @return [Result]
    def call(order:)
      # FIX 8.7: IDEMPOTENCY GUARD
      unless order.cancelled? || order.refunded?
        return Result.new(
          success: false,
          order: order,
          restocked_count: 0,
          error: "Order must be cancelled or refunded to restock (current status: #{order.status})"
        )
      end

      restocked_count = 0

      ActiveRecord::Base.transaction do
        # Lock order
        order.lock!

        # Lock order_items ORDER BY id
        items = order.order_items.order(:id).lock

        # Colectează variant_ids (COMPACT pentru a exclude nil)
        variant_ids = items.filter_map(&:variant_id).uniq

        # Lock variants ORDER BY id (prevent deadlock)
        variants_by_id = Variant.where(id: variant_ids).order(:id).lock.index_by(&:id)

        items.each do |item|
          next unless item.variant_id
          variant = variants_by_id[item.variant_id]
          next unless variant  # Skip dacă variant a fost șters

          # Increment stock
          variant.update_column(:stock, variant.stock + item.quantity)
          restocked_count += 1
        end
      end

      Result.new(success: true, order: order.reload, restocked_count: restocked_count, error: nil)
    end
  end
end

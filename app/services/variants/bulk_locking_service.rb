# frozen_string_literal: true

# app/services/variants/bulk_locking_service.rb
#
# Deadlock-safe bulk operations pe variante.
# LOCK ORDER: V* (ORDER BY id) - compatibil cu P->V* si O->I->V*.
# FAIL-FAST: Input invalid => ArgumentError, nu silent drop.

module Variants
  class BulkLockingService
    extend IdSanitizer::ClassMethods  # Shared helper pentru sanitize_ids

    # DB-PORTABLE: Verifică dacă suntem pe Postgres (pentru CHECK constraints)
    def self.postgres?
      Variant.connection.adapter_name =~ /postgres/i
    end

    # DEADLOCK-SAFE: Lock variante in ORDER BY id
    # @param ids [Array] Array de variant IDs (se sanitizeaza intern)
    # @param sanitized [Boolean] Daca true, skip sanitizare
    def self.with_locked_variants(ids, sanitized: false)
      if sanitized
        unless ids.is_a?(Array) && ids.all? { |x| x.is_a?(Integer) && x > 0 }
          preview = ids.is_a?(Array) ? ids.first(10) : ids
          suffix  = ids.is_a?(Array) && ids.size > 10 ? "... (#{ids.size} total)" : ""
          raise ArgumentError, "sanitized: true requires Array of positive Integers, got: #{preview.inspect}#{suffix}"
        end
      else
        ids = sanitize_ids(ids)
      end
      return yield([]) if ids.empty?

      Variant.transaction do
        locked = Variant.where(id: ids).order(:id).lock.to_a
        yield(locked)
      end
    end

    # Bulk update stock: { variant_id => new_stock }
    # FAIL-FAST: Integer() pe values, nil keys = ArgumentError
    def self.bulk_update_stock(stock_by_variant_id)
      return { success: true, updated: [] } if stock_by_variant_id.empty?

      if stock_by_variant_id.keys.any? { |k| k.nil? || k.to_s.strip.empty? }
        raise ArgumentError, "variant_id keys must be present (nil/blank not allowed)"
      end

      ids = sanitize_ids(stock_by_variant_id.keys)
      updated = []

      with_locked_variants(ids, sanitized: true) do |variants|
        variants.each do |v|
          new_stock = stock_by_variant_id[v.id] || stock_by_variant_id[v.id.to_s]
          next if new_stock.nil?

          new_stock = Integer(new_stock)  # FAIL-FAST

          if !postgres? && new_stock < 0
            raise ActiveRecord::StatementInvalid, "CHECK constraint violated: stock must be >= 0"
          end

          old_stock = v.stock
          if old_stock != new_stock
            v.update_columns(stock: new_stock)
            updated << { variant_id: v.id, old_stock: old_stock, new_stock: new_stock }
          end
        end
      end

      { success: true, updated: updated }
    end

    # Bulk update price: { variant_id => new_price }
    def self.bulk_update_price(price_by_variant_id)
      return { success: true, updated: [] } if price_by_variant_id.empty?

      if price_by_variant_id.keys.any? { |k| k.nil? || k.to_s.strip.empty? }
        raise ArgumentError, "variant_id keys must be present (nil/blank not allowed)"
      end

      ids = sanitize_ids(price_by_variant_id.keys)
      updated = []

      with_locked_variants(ids, sanitized: true) do |variants|
        variants.each do |v|
          new_price = price_by_variant_id[v.id] || price_by_variant_id[v.id.to_s]
          next if new_price.nil?

          new_price = BigDecimal(new_price.to_s)  # FAIL-FAST

          if !postgres? && new_price < 0
            raise ActiveRecord::StatementInvalid, "CHECK constraint violated: price must be >= 0"
          end

          old_price = v.price
          if old_price != new_price
            v.update_columns(price: new_price)
            updated << { variant_id: v.id, old_price: old_price, new_price: new_price }
          end
        end
      end

      { success: true, updated: updated }
    end

    private_class_method :sanitize_ids
  end
end

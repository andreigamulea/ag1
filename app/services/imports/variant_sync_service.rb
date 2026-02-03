# frozen_string_literal: true

require 'zlib'
require 'digest'

# app/services/imports/variant_sync_service.rb
#
# Sincronizare feed-uri externe (ERP, marketplace, furnizori).
# Găsește/creează variantă după external_id, link external_id la variantă.
#
# LOCK ORDER (FIX 8.1):
# 1. Advisory locks (legacy apoi new) - serializare la nivel external_id
# 2. Row locks (P→V) - via CreateOrReactivateService
#
# DUAL-LOCK: Rolling deploy safety (legacy + new format advisory lock)
# Controlat via VariantSyncConfig.dual_lock_enabled?

module Imports
  class VariantSyncService
    include AdvisoryLockKey

    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true) do
      def success? = success
    end

    # @param source [String] sursa externă (ex: "erp", "emag")
    # @param source_account [String] cont (default: "default")
    def initialize(source:, source_account: 'default')
      @source = source.to_s.strip.downcase
      @source_account = source_account.to_s.strip.downcase
    end

    # @param product [Product] produsul
    # @param external_id [String] ID extern (normalizat)
    # @param option_value_ids [Array<Integer>] IDs de OptionValue
    # @param attributes [Hash] atribute (sku, price, stock, vat_rate, status)
    # @return [Result]
    def call(product:, external_id:, option_value_ids: [], attributes: {})
      normalized_eid = external_id.to_s.strip.presence
      return Result.new(success: false, action: :invalid, error: "external_id is blank") unless normalized_eid

      VariantExternalId.transaction(requires_new: true) do
        # FIX 8.1: ÎNTÂI advisory locks (aceeași ordine fixă pentru dual-lock)
        # APOI row locks (via CreateOrReactivateService care face product.lock!)
        acquire_advisory_locks(normalized_eid)

        # Găsește mapping existent
        mapping = find_mapping(normalized_eid)

        if mapping
          handle_existing_mapping(mapping, product, option_value_ids, attributes)
        else
          handle_new_mapping(product, normalized_eid, option_value_ids, attributes)
        end
      end
    rescue ActiveRecord::RecordNotUnique => e
      handle_unique_violation(e)
    rescue ActiveRecord::RecordInvalid => e
      # Rails validation (uniqueness) fires before DB constraint
      if e.message =~ /external.*taken/i
        Result.new(success: false, variant: nil, action: :conflict, error: "External ID mapping conflict: #{e.message}")
      else
        Result.new(success: false, variant: nil, action: :invalid, error: "Validation failed: #{e.message}")
      end
    end

    private

    # FIX 8.1: Advisory locks într-o ordine fixă globală
    # ORDINE: legacy_key → new_key (MEREU în aceeași ordine pentru a preveni deadlock)
    def acquire_advisory_locks(external_id)
      return unless supports_pg_advisory_locks?

      assert_transaction_open_on_lock_connection!

      conn = advisory_lock_connection

      if VariantSyncConfig.dual_lock_enabled?
        VariantSyncConfig.increment_dual_lock_counter

        # Legacy key (format vechi - pentru backward compatibility cu deploy în curs)
        legacy_key = compute_legacy_lock_key(external_id)
        conn.execute("SELECT pg_advisory_xact_lock(#{legacy_key[0]}, #{legacy_key[1]})")

        # New key (format nou - va deveni singurul după deprecation)
        new_key = compute_new_lock_key(external_id)
        conn.execute("SELECT pg_advisory_xact_lock(#{new_key[0]}, #{new_key[1]})")
      else
        # Doar new key (dual-lock dezactivat)
        new_key = compute_new_lock_key(external_id)
        conn.execute("SELECT pg_advisory_xact_lock(#{new_key[0]}, #{new_key[1]})")
      end
    end

    # Legacy lock key: bazat doar pe external_id
    def compute_legacy_lock_key(external_id)
      crc = Zlib.crc32("variant_sync:#{external_id}")
      [int32(crc), 0]
    end

    # New lock key: bazat pe source + source_account + external_id (mai specific)
    def compute_new_lock_key(external_id)
      full_key = "variant_sync:#{@source}:#{@source_account}:#{external_id}"
      crc = Zlib.crc32(full_key)
      [int32(crc), 1]  # Al doilea int = 1 pentru a diferenția de legacy
    end

    def find_mapping(external_id)
      VariantExternalId.find_by(
        source: @source,
        source_account: @source_account,
        external_id: external_id
      )
    end

    def handle_existing_mapping(mapping, product, option_value_ids, attributes)
      variant = mapping.variant

      # Verifică product mismatch
      if variant.product_id != product.id
        return Result.new(
          success: false,
          action: :invalid,
          error: "External ID already mapped to variant #{variant.id} on product #{variant.product_id}, not product #{product.id}"
        )
      end

      # Update attributes (skip empty)
      update_attrs = attributes.reject { |_, v| v.nil? }
      if update_attrs.any?
        variant.update_columns(update_attrs)
      end

      Result.new(success: true, variant: variant.reload, action: :updated, error: nil)
    end

    def handle_new_mapping(product, external_id, option_value_ids, attributes)
      # Delegă la CreateOrReactivateService (care face product.lock! → row locks)
      create_service = Variants::CreateOrReactivateService.new
      create_result = create_service.call(
        product: product,
        option_value_ids: option_value_ids,
        attributes: attributes
      )

      unless create_result.success?
        return Result.new(
          success: false,
          variant: nil,
          action: create_result.action,
          error: create_result.error
        )
      end

      # Creează mapping VariantExternalId
      VariantExternalId.create!(
        variant: create_result.variant,
        source: @source,
        source_account: @source_account,
        external_id: external_id,
        external_sku: attributes[:external_sku]
      )

      Result.new(
        success: true,
        variant: create_result.variant,
        action: create_result.action,
        error: nil
      )
    end

    def handle_unique_violation(exception)
      Result.new(
        success: false,
        variant: nil,
        action: :conflict,
        error: "External ID mapping conflict: #{exception.message}"
      )
    end
  end
end

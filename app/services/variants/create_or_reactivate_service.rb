# frozen_string_literal: true

require 'digest'

# app/services/variants/create_or_reactivate_service.rb
#
# Creează variantă nouă SAU reactivează variantă inactivă.
# Logică de reactivare soft (fără destroy) pentru a păstra istoric order_items.
#
# LOCK ORDER: P → V (product lock pentru serializare cu UpdateOptionTypesService)
# TRANSACTION: requires_new: true pentru savepoint (când apelat din tranzacție externă)
#
# INVARIANTE:
# - Exact 0 sau 1 variantă default activă per produs
# - Exact 0 sau 1 variantă cu aceeași combinație opțiuni (options_digest) activă per produs
# - SKU unic per produs (index unic)
#
# FIX 8.3: Parsing RecordNotUnique folosește constraint_name (nu message parsing)

module Variants
  class CreateOrReactivateService
    include IdSanitizer
    include Variants::OptionValueValidator

    # Result struct pentru a întoarce informații detaliate
    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true) do
      def success? = success
    end

    # @param product [Product] produsul pentru care creăm varianta
    # @param option_value_ids [Array<Integer>] IDs de OptionValue (vor fi sanitizate)
    # @param attributes [Hash] atribute pentru variantă (sku, price, stock, vat_rate, status)
    # @return [Result] success, variant, action (:created/:reactivated/:updated/:invalid/:conflict/:linked), error
    def call(product:, option_value_ids:, attributes: {})
      # Sanitize input IDs (FAIL-FAST pe input invalid)
      clean_ids = sanitize_ids(option_value_ids)

      # Calculează digest (nil pentru default, "id1-id2-id3" pentru opțiuni)
      desired_digest = calculate_digest(clean_ids)

      # Extract desired_status pentru logica de cautare
      desired_status = attributes[:status]&.to_sym || :active

      # Tranzacție cu requires_new pentru a funcționa din tranzacții externe (ex: VariantSyncService)
      Variant.transaction(requires_new: true) do
        # Lock product pentru serializare cu UpdateOptionTypesService
        product.lock!

        # Validare: option_values aparțin produsului
        if clean_ids.any? && !valid_option_values_for_product?(product, clean_ids)
          return Result.new(
            success: false,
            variant: nil,
            action: :invalid,
            error: "Invalid option_value_ids: not all belong to product or duplicate option_types"
          )
        end

        # Găsește variantă existentă (active SAU inactive cu același digest)
        # Dacă desired_status = inactive → creează mereu nouă variantă (nu reactivare)
        existing = if desired_status == :inactive
          nil  # Nu căutăm variante existente pentru inactive (creăm mereu nouă)
        else
          find_existing_variant(product, desired_digest)
        end

        if existing
          # Reactivare sau update variantă existentă
          handle_existing_variant(existing, clean_ids, attributes)
        else
          # Creează variantă nouă
          create_new_variant(product, clean_ids, desired_digest, attributes)
        end
      end
    rescue ActiveRecord::RecordNotUnique => e
      # FIX 8.3: Folosește constraint_name când e disponibil (Postgres >= 9.3)
      handle_unique_violation(e, desired_digest)
    rescue ActiveRecord::RecordInvalid => e
      # Rails validation (ex: validates :sku, uniqueness) aruncă RecordInvalid
      # Convertim la Result struct pentru a păstra contractul uniform
      handle_record_invalid(e)
    end

    private

    # Calculează options_digest (nil pentru default, SHA256 hash pentru opțiuni)
    # IMPORTANT: Trebuie să fie consistent cu Variant#compute_options_digest callback
    def calculate_digest(option_value_ids)
      return nil if option_value_ids.empty?
      Digest::SHA256.hexdigest(option_value_ids.sort.join('-'))
    end

    # Găsește variantă existentă (active SAU inactive) cu același digest
    def find_existing_variant(product, digest)
      product.variants.where(options_digest: digest).first
    end

    # Reactivare sau update variantă existentă
    def handle_existing_variant(variant, option_value_ids, attributes)
      was_inactive = variant.inactive?

      # Build update hash, converting enum symbols to integers for update_columns
      update_attrs = attributes.dup
      update_attrs[:status] = Variant.statuses[:active] if was_inactive

      action = if was_inactive
        :reactivated
      elsif update_attrs.any?
        :updated
      else
        :linked  # Găsit existentă, fără modificări
      end

      # update_columns skip-ează validări + callbacks (nu re-trigger compute_options_digest)
      # Convertim enum symbols la valori integer dacă e cazul
      if update_attrs[:status].is_a?(Symbol)
        update_attrs[:status] = Variant.statuses[update_attrs[:status]]
      end

      variant.update_columns(update_attrs) if update_attrs.any?

      # Sync option_value_variants (replace existing)
      sync_option_values(variant, option_value_ids) if option_value_ids.any?

      Result.new(success: true, variant: variant.reload, action: action, error: nil)
    end

    # Creează variantă nouă
    def create_new_variant(product, option_value_ids, digest, attributes)
      variant = product.variants.build(
        sku: attributes[:sku],
        price: attributes[:price],
        stock: attributes[:stock] || 0,
        vat_rate: attributes[:vat_rate],  # Explicit from attributes (can be nil)
        status: attributes[:status] || :active
      )

      # Link option_values ÎNAINTE de save pentru ca before_save callback să calculeze digest corect
      option_value_ids.each do |option_value_id|
        variant.option_value_variants.build(option_value_id: option_value_id)
      end

      # Save variant (va trigger compute_options_digest callback + validări + unique constraints)
      variant.save!

      Result.new(success: true, variant: variant, action: :created, error: nil)
    end

    # Sync option_value_variants (replace existing)
    def sync_option_values(variant, option_value_ids)
      # Delete existing associations
      variant.option_value_variants.delete_all

      # Create new associations
      option_value_ids.each do |option_value_id|
        variant.option_value_variants.create!(option_value_id: option_value_id)
      end
    end

    # Handle RecordInvalid (Rails validation errors)
    # Ex: validates :sku, uniqueness fires BEFORE DB constraint
    def handle_record_invalid(exception)
      errors = exception.record&.errors

      if errors&.any? { |e| e.attribute == :sku && e.type == :taken }
        Result.new(
          success: false,
          variant: nil,
          action: :conflict,
          error: "SKU already exists for this product"
        )
      else
        Result.new(
          success: false,
          variant: nil,
          action: :invalid,
          error: "Validation failed: #{exception.message}"
        )
      end
    end

    # FIX 8.3: Handle RecordNotUnique folosind constraint_name (nu message parsing)
    # Parsing message-based e fragil la versiuni DB/locales diferite
    def handle_unique_violation(exception, digest)
      # Încercăm să obținem constraint_name din excepția Postgres
      constraint_name = if exception.cause.respond_to?(:constraint_name)
        exception.cause.constraint_name
      else
        # Fallback la message parsing pentru DB-uri fără constraint_name
        exception.message
      end

      # Determină tipul de conflict pe baza numelui constraint-ului
      case constraint_name
      when /idx_unique_sku_per_product/
        Result.new(
          success: false,
          variant: nil,
          action: :conflict,
          error: "SKU already exists for this product"
        )
      when /idx_unique_active_default_variant/
        Result.new(
          success: false,
          variant: nil,
          action: :conflict,
          error: "Active default variant already exists for this product"
        )
      when /idx_unique_active_options_per_product/
        Result.new(
          success: false,
          variant: nil,
          action: :conflict,
          error: "Variant with options_digest '#{digest}' already exists for this product"
        )
      else
        # Fallback generic pentru constraint-uri necunoscute
        Result.new(
          success: false,
          variant: nil,
          action: :conflict,
          error: "Database constraint violation: #{constraint_name}"
        )
      end
    end
  end
end

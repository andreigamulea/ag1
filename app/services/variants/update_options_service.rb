# frozen_string_literal: true

require 'digest'

# app/services/variants/update_options_service.rb
#
# Schimbă combinația de opțiuni pentru o variantă existentă.
# Verifică conflict digest ÎNAINTE de DB (early return).
#
# LOCK ORDER: P → V (product lock pentru serializare cu UpdateOptionTypesService)
# TRANSACTION: requires_new: true pentru savepoint
#
# FIX 8.2: Exclude self din conflict check (prevent false positive când noul digest == curent)

module Variants
  class UpdateOptionsService
    include IdSanitizer
    include Variants::OptionValueValidator

    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true) do
      def success? = success
    end

    # @param variant [Variant] varianta de modificat
    # @param option_value_ids [Array<Integer>] noul array de IDs
    # @return [Result] success, variant, action (:updated/:invalid/:conflict), error
    def call(variant:, option_value_ids:)
      clean_ids = sanitize_ids(option_value_ids)
      product = variant.product

      Variant.transaction(requires_new: true) do
        product.lock!

        # Validare: option_values aparțin produsului
        if clean_ids.any? && !valid_option_values_for_product?(product, clean_ids)
          return Result.new(
            success: false,
            variant: variant,
            action: :invalid,
            error: "Invalid option_value_ids: not all belong to product or duplicate option_types"
          )
        end

        # Calculează noul digest
        new_digest = calculate_digest(clean_ids)

        # FIX 8.2: Verifică conflict ÎNAINTE de DB, EXCLUDE propria variantă
        # Fără .where.not(id: variant.id), dacă noul digest == digest curent,
        # query-ul găsește aceeași variantă → :conflict greșit (false positive)
        if digest_conflict?(product, variant, new_digest)
          return Result.new(
            success: false,
            variant: variant,
            action: :conflict,
            error: "Another active variant with options_digest '#{new_digest}' already exists"
          )
        end

        # Replace option_value_variants
        variant.option_value_variants.delete_all
        clean_ids.each do |ov_id|
          variant.option_value_variants.create!(option_value_id: ov_id)
        end

        # Recalculează digest (via save callback)
        variant.save!

        Result.new(success: true, variant: variant.reload, action: :updated, error: nil)
      end
    rescue ActiveRecord::RecordNotUnique => e
      handle_unique_violation(e, variant)
    end

    private

    def calculate_digest(option_value_ids)
      return nil if option_value_ids.empty?
      Digest::SHA256.hexdigest(option_value_ids.sort.join('-'))
    end

    # FIX 8.2: Exclude self din conflict check
    def digest_conflict?(product, variant, new_digest)
      scope = product.variants.where(status: :active, options_digest: new_digest)
      scope = scope.where.not(id: variant.id)  # ← EXCLUDE propria variantă
      scope.exists?
    end

    # Race condition fallback: handle RecordNotUnique
    def handle_unique_violation(exception, variant)
      Result.new(
        success: false,
        variant: variant,
        action: :conflict,
        error: "Database constraint violation (race condition): #{exception.message}"
      )
    end
  end
end

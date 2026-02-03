# frozen_string_literal: true

# app/services/products/update_option_types_service.rb
#
# Adaugă/șterge option_types la/din produs.
# Dezactivează variante active care devin incomplete (când ștergi option_type).
# Recalculează options_digest pentru variante afectate.
#
# LOCK ORDER: P → V (ORDER BY id) pentru deadlock safety

module Products
  class UpdateOptionTypesService
    Result = Struct.new(:success, :product, :action, :added, :removed, :deactivated_count, :error, keyword_init: true) do
      def success? = success
    end

    # @param product [Product] produsul de modificat
    # @param option_type_ids [Array<Integer>] noul array complet de option_type IDs
    # @return [Result]
    def call(product:, option_type_ids:)
      new_ids = option_type_ids.map(&:to_i).uniq

      Product.transaction(requires_new: true) do
        product.lock!

        current_ids = product.product_option_types.pluck(:option_type_id)

        added_ids = new_ids - current_ids
        removed_ids = current_ids - new_ids

        deactivated_count = 0

        # Dezactivează variante care folosesc option_types care vor fi șterse
        if removed_ids.any?
          deactivated_count = deactivate_affected_variants(product, removed_ids)
        end

        # Sync product_option_types
        sync_option_types(product, new_ids, added_ids, removed_ids)

        # Recalculează digest pentru variantele rămase active
        recalculate_digests(product) if removed_ids.any?

        action = if added_ids.any? && removed_ids.any?
          :replaced
        elsif added_ids.any?
          :added
        elsif removed_ids.any?
          :removed
        else
          :unchanged
        end

        Result.new(
          success: true,
          product: product.reload,
          action: action,
          added: added_ids,
          removed: removed_ids,
          deactivated_count: deactivated_count,
          error: nil
        )
      end
    end

    private

    # Dezactivează variante active care au opțiuni din tipurile care vor fi șterse
    # LOCK ORDER: variante ORDER BY id
    def deactivate_affected_variants(product, removed_type_ids)
      # Găsește option_value_ids care aparțin tipurilor șterse
      affected_ov_ids = OptionValue.where(option_type_id: removed_type_ids).pluck(:id)
      return 0 if affected_ov_ids.empty?

      # Găsește variante active care au vreun option_value din tipurile șterse
      affected_variant_ids = OptionValueVariant
        .where(option_value_id: affected_ov_ids)
        .joins(:variant)
        .where(variants: { product_id: product.id, status: :active })
        .pluck(:variant_id)
        .uniq

      return 0 if affected_variant_ids.empty?

      # Lock variante ORDER BY id (prevent deadlock)
      affected_variants = Variant.where(id: affected_variant_ids).order(:id).lock

      count = 0
      affected_variants.each do |variant|
        variant.update_column(:status, Variant.statuses[:inactive])
        count += 1
      end

      count
    end

    # Sync product_option_types
    def sync_option_types(product, new_ids, added_ids, removed_ids)
      # Șterge removed
      product.product_option_types.where(option_type_id: removed_ids).delete_all if removed_ids.any?

      # Adaugă added (cu position)
      max_position = product.product_option_types.maximum(:position) || 0
      added_ids.each_with_index do |type_id, idx|
        product.product_option_types.create!(
          option_type_id: type_id,
          position: max_position + idx + 1
        )
      end
    end

    # Recalculează digest pentru toate variantele active rămase
    def recalculate_digests(product)
      product.variants.where(status: :active).find_each do |variant|
        variant.save!  # Trigger before_save :compute_options_digest
      end
    end
  end
end

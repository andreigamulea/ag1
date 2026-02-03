# frozen_string_literal: true

# app/services/variants/option_value_validator.rb
#
# DRY: Validare opțiuni extrasă din CreateOrReactivateService și UpdateOptionsService
# pentru a elimina duplicarea și riscul de drift.
#
# IMPORTANT: Acest modul e un concern (module), nu un serviciu PORO.
# Poate fi inclus în orice clasă care are nevoie de validare option_values.

module Variants
  module OptionValueValidator
    # Verifică că toate option_value_ids:
    # 1. Există în DB
    # 2. Au option_type-uri distincte (nu 2 valori din același tip)
    # 3. Aparțin unor option_types asociate produsului
    #
    # @param product [Product] produsul pentru care validăm
    # @param ids [Array<Integer>] IDs de OptionValue
    # @return [Boolean] true dacă toate validările trec
    def valid_option_values_for_product?(product, ids)
      return true if ids.empty?

      # Fetch toate option_values și option_type_ids lor
      rows = OptionValue.where(id: ids).pluck(:id, :option_type_id)

      # Validare 1: Toate IDs există în DB
      return false if rows.size != ids.size  # unele IDs nu există

      # Validare 2: Nu există 2 valori din același option_type
      type_ids = rows.map(&:last)
      return false if type_ids.size != type_ids.uniq.size  # duplicate pe același tip

      # Validare 3: Toate option_types sunt asociate produsului
      allowed = ProductOptionType.where(product_id: product.id).pluck(:option_type_id)
      (type_ids - allowed).empty?  # toate tipurile sunt asociate produsului
    end
  end
end

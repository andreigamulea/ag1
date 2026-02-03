# frozen_string_literal: true

class M3AddVariantsConstraints < ActiveRecord::Migration[7.1]
  def change
    # ═══════════════════════════════════════════════════════════════════════════
    # UNIVERSAL INDEXES - deja create în M1, skip dacă există
    # ═══════════════════════════════════════════════════════════════════════════

    # Performance index pentru product_option_types
    unless index_exists?(:product_option_types, :product_id, name: 'idx_pot_product')
      add_index :product_option_types, :product_id, name: 'idx_pot_product'
    end

    # Performance index pentru option_values
    unless index_exists?(:option_values, :option_type_id, name: 'idx_ov_type')
      add_index :option_values, :option_type_id, name: 'idx_ov_type'
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # POSTGRES-ONLY: Partial indexes + CHECK constraints
    # SQLite/MySQL nu suportă partial indexes sau CHECK constraints în același mod
    # ═══════════════════════════════════════════════════════════════════════════
    return unless postgres?

    # PARTIAL UNIQUE INDEXES (Postgres-only)
    # O singură variantă activă per combinație de opțiuni
    unless index_exists?(:variants, [:product_id, :options_digest], name: 'idx_unique_active_options_per_product')
      add_index :variants, [:product_id, :options_digest], unique: true,
                where: "options_digest IS NOT NULL AND status = 0",
                name: 'idx_unique_active_options_per_product'
    end

    # O singură variantă default activă per produs
    unless index_exists?(:variants, [:product_id], name: 'idx_unique_active_default_variant')
      add_index :variants, [:product_id], unique: true,
                where: "options_digest IS NULL AND status = 0",
                name: 'idx_unique_active_default_variant'
    end

    # External SKU unic global (dacă este setat)
    unless index_exists?(:variants, :external_sku, name: 'idx_unique_external_sku')
      add_index :variants, :external_sku, unique: true,
                where: "external_sku IS NOT NULL",
                name: 'idx_unique_external_sku'
    end

    # CHECK CONSTRAINTS (Postgres-only)
    unless constraint_exists?(:variants, 'chk_variants_price_positive')
      add_check_constraint :variants, 'price IS NOT NULL AND price >= 0',
                           name: 'chk_variants_price_positive'
    end
    unless constraint_exists?(:variants, 'chk_variants_stock_positive')
      add_check_constraint :variants, 'stock IS NOT NULL AND stock >= 0',
                           name: 'chk_variants_stock_positive'
    end
    unless constraint_exists?(:variants, 'chk_variants_status_enum')
      add_check_constraint :variants, 'status IN (0, 1)',
                           name: 'chk_variants_status_enum'
    end
  end

  private

  def postgres?
    connection.adapter_name =~ /postgres/i
  end

  def constraint_exists?(table, name)
    return false unless postgres?

    query = <<~SQL
      SELECT 1
      FROM pg_constraint
      WHERE conname = #{connection.quote(name)}
        AND conrelid = #{connection.quote(table.to_s)}::regclass
      LIMIT 1
    SQL
    connection.select_value(query).present?
  end
end

class M1CreateVariantSystem < ActiveRecord::Migration[7.1]
  def change
    # ═══════════════════════════════════════════════════════════════════════════
    # OPTION TYPES (ex: "Culoare", "Mărime", "Material")
    # ═══════════════════════════════════════════════════════════════════════════
    create_table :option_types do |t|
      t.string :name, null: false
      t.string :presentation  # Display name (poate fi diferit de name)
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :option_types, :name, unique: true

    # ═══════════════════════════════════════════════════════════════════════════
    # OPTION VALUES (ex: "Roșu", "Albastru", "M", "L", "XL")
    # ═══════════════════════════════════════════════════════════════════════════
    create_table :option_values do |t|
      t.references :option_type, null: false, foreign_key: true
      t.string :name, null: false
      t.string :presentation  # Display name
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :option_values, [:option_type_id, :name], unique: true

    # ═══════════════════════════════════════════════════════════════════════════
    # PRODUCT_OPTION_TYPES (join table: ce option types are un produs)
    # ═══════════════════════════════════════════════════════════════════════════
    create_table :product_option_types do |t|
      t.references :product, null: false, foreign_key: true
      t.references :option_type, null: false, foreign_key: true
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :product_option_types, [:product_id, :option_type_id],
              unique: true, name: 'idx_unique_product_option_type'

    # ═══════════════════════════════════════════════════════════════════════════
    # VARIANTS (variantele produsului)
    # ═══════════════════════════════════════════════════════════════════════════
    create_table :variants do |t|
      t.references :product, null: false, foreign_key: { on_delete: :restrict }
      t.string :sku, null: false
      t.decimal :price, precision: 10, scale: 2, null: false, default: 0
      t.integer :stock, null: false, default: 0
      t.integer :status, null: false, default: 0  # enum: 0=active, 1=inactive
      t.text :options_digest  # pentru unicitate combinație opțiuni
      t.string :external_sku  # SKU extern (legacy/manual)
      t.decimal :vat_rate, precision: 5, scale: 2

      t.timestamps
    end

    add_index :variants, :status
    add_index :variants, [:product_id, :sku], unique: true, name: 'idx_unique_sku_per_product'

    # ═══════════════════════════════════════════════════════════════════════════
    # OPTION_VALUE_VARIANTS (join table: ce opțiuni are o variantă)
    # ═══════════════════════════════════════════════════════════════════════════
    create_table :option_value_variants do |t|
      t.references :variant, null: false, foreign_key: { on_delete: :cascade }
      t.references :option_value, null: false, foreign_key: { on_delete: :restrict }

      t.timestamps
    end

    add_index :option_value_variants, [:variant_id, :option_value_id],
              unique: true, name: 'idx_unique_ovv'
    add_index :option_value_variants, :variant_id, name: 'idx_ovv_variant'
    add_index :option_value_variants, :option_value_id, name: 'idx_ovv_option_value'

    # ═══════════════════════════════════════════════════════════════════════════
    # ORDER_ITEMS - adaugă coloanele pentru snapshot variante
    # ═══════════════════════════════════════════════════════════════════════════
    add_reference :order_items, :variant, foreign_key: { on_delete: :nullify }, null: true

    unless column_exists?(:order_items, :variant_sku)
      add_column :order_items, :variant_sku, :string
    end
    unless column_exists?(:order_items, :variant_options_text)
      add_column :order_items, :variant_options_text, :text
    end
    unless column_exists?(:order_items, :vat_rate_snapshot)
      add_column :order_items, :vat_rate_snapshot, :decimal, precision: 5, scale: 2
    end
    unless column_exists?(:order_items, :currency)
      add_column :order_items, :currency, :string, default: 'RON'
    end
    unless column_exists?(:order_items, :line_total_gross)
      add_column :order_items, :line_total_gross, :decimal, precision: 10, scale: 2
    end
    unless column_exists?(:order_items, :tax_amount)
      add_column :order_items, :tax_amount, :decimal, precision: 10, scale: 2
    end
  end
end

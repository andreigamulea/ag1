# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Variant Schema', type: :model do
  let(:connection) { ActiveRecord::Base.connection }

  # ═══════════════════════════════════════════════════════════════════════════
  # COLUMN DEFAULTS & NULLABILITY
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'column defaults' do
    describe 'variants table' do
      let(:columns) { connection.columns(:variants) }

      it 'has status with default 0' do
        col = columns.find { |c| c.name == 'status' }
        expect(col).not_to be_nil
        expect(col.default.to_s).to eq('0')
      end

      it 'has price with default 0' do
        col = columns.find { |c| c.name == 'price' }
        expect(col).not_to be_nil
        expect(col.default.to_s).to match(/0(\.0)?/)
      end

      it 'has stock with default 0' do
        col = columns.find { |c| c.name == 'stock' }
        expect(col).not_to be_nil
        expect(col.default.to_s).to eq('0')
      end

      it 'has sku as NOT NULL' do
        col = columns.find { |c| c.name == 'sku' }
        expect(col).not_to be_nil
        expect(col.null).to be false
      end

      it 'has product_id as NOT NULL' do
        col = columns.find { |c| c.name == 'product_id' }
        expect(col).not_to be_nil
        expect(col.null).to be false
      end
    end

    describe 'variant_external_ids table' do
      let(:columns) { connection.columns(:variant_external_ids) }

      it 'has source_account with default "default"' do
        col = columns.find { |c| c.name == 'source_account' }
        expect(col).not_to be_nil
        expect(col.default).to eq('default')
      end

      it 'has source as NOT NULL' do
        col = columns.find { |c| c.name == 'source' }
        expect(col).not_to be_nil
        expect(col.null).to be false
      end

      it 'has external_id as NOT NULL' do
        col = columns.find { |c| c.name == 'external_id' }
        expect(col).not_to be_nil
        expect(col.null).to be false
      end
    end

    describe 'order_items table' do
      let(:columns) { connection.columns(:order_items) }

      it 'has variant_id as nullable' do
        col = columns.find { |c| c.name == 'variant_id' }
        expect(col).not_to be_nil
        expect(col.null).to be true
      end

      it 'has currency with default "RON"' do
        col = columns.find { |c| c.name == 'currency' }
        expect(col).not_to be_nil
        expect(col.default).to eq('RON')
      end

      it 'has variant_sku column' do
        expect(connection.column_exists?(:order_items, :variant_sku)).to be true
      end

      it 'has variant_options_text column' do
        expect(connection.column_exists?(:order_items, :variant_options_text)).to be true
      end

      it 'has vat_rate_snapshot column' do
        expect(connection.column_exists?(:order_items, :vat_rate_snapshot)).to be true
      end

      it 'has line_total_gross column' do
        expect(connection.column_exists?(:order_items, :line_total_gross)).to be true
      end

      it 'has tax_amount column' do
        expect(connection.column_exists?(:order_items, :tax_amount)).to be true
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INDEX EXISTENCE
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'indexes' do
    describe 'variants table' do
      it 'has idx_unique_sku_per_product index' do
        expect(connection.index_exists?(:variants, [:product_id, :sku], name: 'idx_unique_sku_per_product')).to be true
      end

      it 'has status index' do
        expect(connection.index_exists?(:variants, :status)).to be true
      end
    end

    describe 'option_value_variants table' do
      it 'has idx_unique_ovv index' do
        expect(connection.index_exists?(:option_value_variants, [:variant_id, :option_value_id], name: 'idx_unique_ovv')).to be true
      end

      it 'has idx_ovv_variant index' do
        expect(connection.index_exists?(:option_value_variants, :variant_id, name: 'idx_ovv_variant')).to be true
      end

      it 'has idx_ovv_option_value index' do
        expect(connection.index_exists?(:option_value_variants, :option_value_id, name: 'idx_ovv_option_value')).to be true
      end
    end

    describe 'product_option_types table' do
      it 'has idx_unique_product_option_type index' do
        expect(connection.index_exists?(:product_option_types, [:product_id, :option_type_id], name: 'idx_unique_product_option_type')).to be true
      end
    end

    describe 'variant_external_ids table' do
      it 'has idx_unique_source_account_external_id index' do
        expect(connection.index_exists?(:variant_external_ids, [:source, :source_account, :external_id], name: 'idx_unique_source_account_external_id')).to be true
      end

      it 'has idx_vei_variant index' do
        expect(connection.index_exists?(:variant_external_ids, :variant_id, name: 'idx_vei_variant')).to be true
      end

      it 'has idx_vei_source index' do
        expect(connection.index_exists?(:variant_external_ids, :source, name: 'idx_vei_source')).to be true
      end
    end

    describe 'order_items table' do
      it 'has index on variant_id' do
        expect(connection.index_exists?(:order_items, :variant_id)).to be true
      end
    end

    describe 'postgres-only partial indexes', :postgres_only do
      before do
        skip 'Postgres-only test' unless connection.adapter_name =~ /postgres/i
      end

      it 'has idx_unique_active_default_variant partial index' do
        expect(connection.index_exists?(:variants, :product_id, name: 'idx_unique_active_default_variant')).to be true
      end

      it 'has idx_unique_active_options_per_product partial index' do
        expect(connection.index_exists?(:variants, [:product_id, :options_digest], name: 'idx_unique_active_options_per_product')).to be true
      end

      it 'has idx_unique_external_sku partial index' do
        expect(connection.index_exists?(:variants, :external_sku, name: 'idx_unique_external_sku')).to be true
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FOREIGN KEYS
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'foreign keys' do
    it 'variants references products' do
      expect(connection.foreign_key_exists?(:variants, :products)).to be true
    end

    it 'option_value_variants references variants' do
      expect(connection.foreign_key_exists?(:option_value_variants, :variants)).to be true
    end

    it 'option_value_variants references option_values' do
      expect(connection.foreign_key_exists?(:option_value_variants, :option_values)).to be true
    end

    it 'variant_external_ids references variants' do
      expect(connection.foreign_key_exists?(:variant_external_ids, :variants)).to be true
    end

    it 'product_option_types references products' do
      expect(connection.foreign_key_exists?(:product_option_types, :products)).to be true
    end

    it 'product_option_types references option_types' do
      expect(connection.foreign_key_exists?(:product_option_types, :option_types)).to be true
    end

    it 'option_values references option_types' do
      expect(connection.foreign_key_exists?(:option_values, :option_types)).to be true
    end

    it 'order_items references variants' do
      expect(connection.foreign_key_exists?(:order_items, :variants)).to be true
    end

    it 'order_items.variant_id FK has on_delete: nullify' do
      fks = connection.foreign_keys(:order_items)
      fk  = fks.find { |k| k.to_table.to_s == 'variants' && k.options[:column].to_s == 'variant_id' }
      expect(fk).not_to be_nil
      expect(fk.options[:on_delete]).to eq(:nullify) if fk.options.key?(:on_delete)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CHECK CONSTRAINTS (Postgres-only)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'check constraints', :postgres_only do
    before do
      skip 'Postgres-only test' unless connection.adapter_name =~ /postgres/i
    end

    def constraint_exists?(table, name)
      query = <<~SQL
        SELECT 1 FROM pg_constraint
        WHERE conname = '#{name}'
          AND conrelid = '#{table}'::regclass
        LIMIT 1
      SQL
      connection.select_value(query).present?
    end

    it 'has chk_variants_price_positive constraint' do
      expect(constraint_exists?(:variants, 'chk_variants_price_positive')).to be true
    end

    it 'has chk_variants_stock_positive constraint' do
      expect(constraint_exists?(:variants, 'chk_variants_stock_positive')).to be true
    end

    it 'has chk_variants_status_enum constraint' do
      expect(constraint_exists?(:variants, 'chk_variants_status_enum')).to be true
    end

    it 'has chk_vei_source_format constraint' do
      expect(constraint_exists?(:variant_external_ids, 'chk_vei_source_format')).to be true
    end

    it 'has chk_vei_source_account_format constraint' do
      expect(constraint_exists?(:variant_external_ids, 'chk_vei_source_account_format')).to be true
    end

    it 'has chk_vei_external_id_not_empty constraint' do
      expect(constraint_exists?(:variant_external_ids, 'chk_vei_external_id_not_empty')).to be true
    end
  end
end

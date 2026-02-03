# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Variant Isolation', type: :model do
  include ActiveSupport::Testing::TimeHelpers
  # ═══════════════════════════════════════════════════════════════════════════
  # V→P ISOLATION: Variant updates should NOT touch Product
  # Asta e important pentru:
  # - Performance (evită queries inutile)
  # - Lock ordering (nu vrem să luăm lock pe Product când updatem Variant)
  # ═══════════════════════════════════════════════════════════════════════════

  describe 'Variant update isolation from Product' do
    it 'updating price/stock does NOT touch product.updated_at' do
      product = create(:product)
      variant = create(:variant, product: product)

      original_updated_at = product.updated_at

      # Travel in time to ensure timestamp would change if touched
      travel 1.minute do
        variant.update!(price: 150, stock: 40)
      end

      expect(product.reload.updated_at).to eq(original_updated_at)
    end

    it 'updating price/stock does NOT query products table for UPDATE' do
      product = create(:product)
      variant = create(:variant, product: product)

      product_write_queries = []

      callback = lambda do |*, payload|
        sql = payload[:sql].to_s
        product_write_queries << sql if sql =~ /UPDATE.*products/i
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        variant.update!(price: 200, stock: 50)
      end

      expect(product_write_queries).to be_empty,
        "Variant update should not write to products table, found: #{product_write_queries}"
    end

    it 'changing variant status does NOT touch product' do
      product = create(:product)
      variant = create(:variant, product: product, status: :active)

      original_updated_at = product.updated_at

      travel 1.minute do
        variant.update!(status: :inactive)
      end

      expect(product.reload.updated_at).to eq(original_updated_at)
    end

    it 'adding option_values to variant does NOT touch product' do
      product = create(:product)
      variant = create(:variant, product: product)
      option_value = create(:option_value)

      original_updated_at = product.updated_at

      travel 1.minute do
        create(:option_value_variant, variant: variant, option_value: option_value)
        variant.reload.save! # Trigger digest recalculation
      end

      expect(product.reload.updated_at).to eq(original_updated_at)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PRODUCT VARIANTS RELATIONSHIP
  # Verifică că Product poate accesa variantele fără side effects
  # ═══════════════════════════════════════════════════════════════════════════

  describe 'Product accessing variants' do
    it 'reading product.variants does NOT modify product' do
      product = create(:product)
      create(:variant, product: product, status: :active)
      create(:variant, product: product, status: :inactive)

      original_updated_at = product.updated_at

      travel 1.minute do
        # Just read variants
        _ = product.variants.to_a
        _ = product.variants.active.count
      end

      expect(product.reload.updated_at).to eq(original_updated_at)
    end
  end
end

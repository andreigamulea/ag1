# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Checkout::FinalizeService do
  let(:service) { described_class.new }
  let(:product) { create(:product) }

  # Helper: creează variantă cu digest unic (evită idx_unique_active_default_variant)
  def create_variant_with_digest(product:, **attrs)
    variant = create(:variant, product: product, **attrs)
    # Setăm un digest unic bazat pe SKU pentru a evita constraint-ul default variant
    variant.update_column(:options_digest, Digest::SHA256.hexdigest(variant.sku))
    variant
  end

  describe '#call' do
    context 'successful finalization' do
      it 'snapshots variant data and decrements stock' do
        variant = create(:variant, product: product, sku: 'TEST-SKU', price: 100.0, stock: 10, vat_rate: 19.0)
        order = create(:order, status: 'pending')
        item = create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 2, price: 100.0)

        result = service.call(order: order)

        expect(result.success?).to be true
        expect(order.reload.status).to eq('paid')

        item.reload
        expect(item.variant_sku).to eq('TEST-SKU')
        expect(item.vat_rate_snapshot).to eq(19.0)
        expect(item.line_total_gross).to eq(200.0)
        expect(item.tax_amount).to be_present

        expect(variant.reload.stock).to eq(8)  # 10 - 2
      end

      it 'handles multiple order_items' do
        v1 = create(:variant, product: product, sku: 'V1', price: 50.0, stock: 5)
        v1.update_column(:options_digest, Digest::SHA256.hexdigest('v1'))
        v2 = create(:variant, product: product, sku: 'V2', price: 80.0, stock: 3)
        v2.update_column(:options_digest, Digest::SHA256.hexdigest('v2'))

        order = create(:order, status: 'pending')
        create(:order_item, order: order, product: product, variant_id: v1.id, quantity: 2, price: 50.0)
        create(:order_item, order: order, product: product, variant_id: v2.id, quantity: 1, price: 80.0)

        result = service.call(order: order)

        expect(result.success?).to be true
        expect(v1.reload.stock).to eq(3)
        expect(v2.reload.stock).to eq(2)
      end

      it 'skips items without variant_id (Transport, Discount)' do
        variant = create(:variant, product: product, sku: 'V1', stock: 10)
        order = create(:order, status: 'pending')
        create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 1, price: 100.0)
        create(:order_item, order: order, product: product, variant_id: nil, quantity: 1, price: 15.0, product_name: 'Transport')

        result = service.call(order: order)

        expect(result.success?).to be true
        expect(variant.reload.stock).to eq(9)
      end
    end

    context 'fail-fast guards' do
      it 'returns error when variant was deleted' do
        # Creăm variant, creăm order_item, apoi ștergem variant-ul
        variant = create(:variant, product: product, sku: 'TO-DELETE', stock: 10)
        order = create(:order, status: 'pending')
        item = create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 1, price: 100.0)

        # Ștergem variant-ul și actualizăm FK cu raw SQL (disable triggers temporar)
        variant.order_items.update_all(variant_id: nil)
        variant.option_value_variants.delete_all
        variant.external_ids.delete_all
        deleted_id = variant.id
        variant.delete

        # Bypass FK constraint via disable triggers (PostgreSQL)
        ActiveRecord::Base.connection.execute("ALTER TABLE order_items DISABLE TRIGGER ALL")
        ActiveRecord::Base.connection.execute("UPDATE order_items SET variant_id = #{deleted_id} WHERE id = #{item.id}")
        ActiveRecord::Base.connection.execute("ALTER TABLE order_items ENABLE TRIGGER ALL")

        result = service.call(order: order)

        expect(result.success?).to be false
        expect(result.error).to match(/not found/i)
      end

      it 'returns error when variant is inactive' do
        variant = create(:variant, product: product, sku: 'INACTIVE', stock: 10, status: :inactive)
        order = create(:order, status: 'pending')
        create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 1, price: 100.0)

        result = service.call(order: order)

        expect(result.success?).to be false
        expect(result.error).to match(/inactive/i)
      end

      it 'returns error when stock is insufficient' do
        variant = create(:variant, product: product, sku: 'LOW-STOCK', stock: 1)
        order = create(:order, status: 'pending')
        create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 5, price: 100.0)

        result = service.call(order: order)

        expect(result.success?).to be false
        expect(result.error).to match(/stock/i)
      end
    end

    context 'FIX 8.6: atomic rollback' do
      it 'rolls back all changes when second item fails' do
        v1 = create(:variant, product: product, sku: 'V1', stock: 10)
        v1.update_column(:options_digest, Digest::SHA256.hexdigest('v1'))
        v2 = create(:variant, product: product, sku: 'V2', stock: 1)
        v2.update_column(:options_digest, Digest::SHA256.hexdigest('v2'))

        order = create(:order, status: 'pending')
        item1 = create(:order_item, order: order, product: product, variant_id: v1.id, quantity: 2, price: 50.0)
        create(:order_item, order: order, product: product, variant_id: v2.id, quantity: 5, price: 80.0)  # Needs 5, has 1

        result = service.call(order: order)

        expect(result.success?).to be false

        # ATOMIC: niciun snapshot/decrement nu persistă
        expect(v1.reload.stock).to eq(10)  # NOT decremented
        expect(v2.reload.stock).to eq(1)   # NOT decremented
        expect(item1.reload.variant_sku).to be_nil  # NOT snapshotted
        expect(order.reload.status).to eq('pending')  # NOT marked as paid
      end
    end
  end
end

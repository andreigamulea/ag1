# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::RestockService do
  let(:service) { described_class.new }
  let(:product) { create(:product) }

  describe '#call' do
    context 'successful restock' do
      it 'increments stock for cancelled order' do
        variant = create(:variant, product: product, sku: 'V1', stock: 5)
        order = create(:order, status: 'cancelled')
        create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 3, price: 100.0)

        result = service.call(order: order)

        expect(result.success?).to be true
        expect(result.restocked_count).to eq(1)
        expect(variant.reload.stock).to eq(8)  # 5 + 3
      end

      it 'increments stock for refunded order' do
        variant = create(:variant, product: product, sku: 'V1', stock: 0)
        order = create(:order, status: 'refunded')
        create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 2, price: 100.0)

        result = service.call(order: order)

        expect(result.success?).to be true
        expect(variant.reload.stock).to eq(2)  # 0 + 2
      end

      it 'handles multiple items with different variants' do
        v1 = create(:variant, product: product, sku: 'V1', stock: 3)
        v1.update_column(:options_digest, Digest::SHA256.hexdigest('v1'))
        v2 = create(:variant, product: product, sku: 'V2', stock: 7)
        v2.update_column(:options_digest, Digest::SHA256.hexdigest('v2'))
        order = create(:order, status: 'cancelled')
        create(:order_item, order: order, product: product, variant_id: v1.id, quantity: 1, price: 50.0)
        create(:order_item, order: order, product: product, variant_id: v2.id, quantity: 2, price: 80.0)

        result = service.call(order: order)

        expect(result.success?).to be true
        expect(result.restocked_count).to eq(2)
        expect(v1.reload.stock).to eq(4)
        expect(v2.reload.stock).to eq(9)
      end

      it 'skips items without variant_id' do
        variant = create(:variant, product: product, sku: 'V1', stock: 5)
        order = create(:order, status: 'cancelled')
        create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 1, price: 100.0)
        create(:order_item, order: order, product: product, variant_id: nil, quantity: 1, price: 15.0, product_name: 'Transport')

        result = service.call(order: order)

        expect(result.success?).to be true
        expect(result.restocked_count).to eq(1)
      end
    end

    context 'FIX 8.7: idempotency guard' do
      it 'returns error when order is pending' do
        order = create(:order, status: 'pending')

        result = service.call(order: order)

        expect(result.success?).to be false
        expect(result.error).to match(/must be cancelled or refunded/i)
      end

      it 'returns error when order is paid' do
        order = create(:order, status: 'paid')

        result = service.call(order: order)

        expect(result.success?).to be false
        expect(result.error).to match(/must be cancelled or refunded/i)
      end

      it 'returns error when order is shipped' do
        order = create(:order, status: 'shipped')

        result = service.call(order: order)

        expect(result.success?).to be false
        expect(result.error).to match(/must be cancelled or refunded/i)
      end
    end
  end
end

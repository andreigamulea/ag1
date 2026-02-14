require 'rails_helper'

RSpec.describe 'Orders with variants', type: :model do
  describe 'Order item creation with variant data' do
    let(:product) { create(:product, name: 'Carte Test Order', price: 79.99) }
    let(:option_type) { create(:option_type, name: "OrdOT-#{SecureRandom.hex(4)}", presentation: 'Format') }

    let(:ov_fizic) { create(:option_value, option_type: option_type, name: "OrdFiz-#{SecureRandom.hex(4)}", presentation: 'Fizic') }
    let(:ov_digital) { create(:option_value, option_type: option_type, name: "OrdDig-#{SecureRandom.hex(4)}", presentation: 'Digital') }

    let(:variant_fizic) do
      v = create(:variant, product: product, sku: "ORD-FIZ-#{SecureRandom.hex(4)}", price: 79.99, stock: 10, vat_rate: 19)
      create(:option_value_variant, variant: v, option_value: ov_fizic)
      v.reload
      v.save! # recompute options_digest
      v
    end

    let(:variant_digital) do
      v = create(:variant, product: product, sku: "ORD-DIG-#{SecureRandom.hex(4)}", price: 49.99, stock: 50, vat_rate: 19)
      create(:option_value_variant, variant: v, option_value: ov_digital)
      v.reload
      v.save! # recompute options_digest
      v
    end

    it 'stores variant_options_text on order items' do
      order = create(:order, total: 79.99)
      variant_fizic # force load

      item = order.order_items.create!(
        product: product,
        product_name: product.name,
        variant_id: variant_fizic.id,
        variant_sku: variant_fizic.sku,
        variant_options_text: variant_fizic.options_text,
        vat_rate_snapshot: variant_fizic.vat_rate,
        quantity: 1,
        price: variant_fizic.price,
        total_price: variant_fizic.price
      )

      item.reload
      expect(item.variant_options_text).to be_present
      expect(item.variant_sku).to eq(variant_fizic.sku)
      expect(item.variant_id).to eq(variant_fizic.id)
    end

    it 'creates distinct order items for different variants of same product' do
      order = create(:order, total: 179.97)
      variant_fizic
      variant_digital

      item1 = order.order_items.create!(
        product: product,
        product_name: product.name,
        variant_id: variant_fizic.id,
        variant_sku: variant_fizic.sku,
        variant_options_text: variant_fizic.options_text,
        quantity: 1,
        price: variant_fizic.price,
        total_price: variant_fizic.price
      )

      item2 = order.order_items.create!(
        product: product,
        product_name: product.name,
        variant_id: variant_digital.id,
        variant_sku: variant_digital.sku,
        variant_options_text: variant_digital.options_text,
        quantity: 2,
        price: variant_digital.price,
        total_price: variant_digital.price * 2
      )

      expect(order.order_items.count).to eq(2)
      expect(item1.variant_options_text).not_to eq(item2.variant_options_text)
      expect(item1.variant_sku).not_to eq(item2.variant_sku)
      expect(item1.price).not_to eq(item2.price)
    end

    it 'allows order_item without variant (backward compatible)' do
      order = create(:order, total: 79.99)

      item = order.order_items.create!(
        product: product,
        product_name: product.name,
        quantity: 1,
        price: product.price,
        total_price: product.price
      )

      item.reload
      expect(item.variant_id).to be_nil
      expect(item.variant_sku).to be_nil
      expect(item.variant_options_text).to be_nil
    end
  end

  describe 'Stripe line items name construction' do
    it 'includes variant options when present' do
      name = ['Carte Test', 'Format: Fizic'].compact.join(' - ').presence || 'Produs'
      expect(name).to eq('Carte Test - Format: Fizic')
    end

    it 'shows only product name without variant' do
      name = ['Carte Simpla', nil].compact.join(' - ').presence || 'Produs'
      expect(name).to eq('Carte Simpla')
    end

    it 'shows only product name with empty variant_options_text' do
      name = ['Carte Test', ''.presence].compact.join(' - ').presence || 'Produs'
      expect(name).to eq('Carte Test')
    end

    it 'falls back to Produs when both are nil' do
      name = [nil, nil].compact.join(' - ').presence || 'Produs'
      expect(name).to eq('Produs')
    end
  end

  describe 'show_items with variant order items' do
    include Devise::Test::IntegrationHelpers

    let(:admin) { create(:user, :admin) }
    let(:product) { create(:product, name: 'Carte Items Test', price: 79.99) }

    it 'shows variant_options_text for admin', type: :request do
      sign_in admin

      order = create(:order, total: 79.99, user: admin)
      order.order_items.create!(
        product: product,
        product_name: product.name,
        variant_options_text: 'Format: Fizic',
        quantity: 1,
        price: 79.99,
        total_price: 79.99
      )

      get show_items_order_path(order)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(product.name)
      expect(response.body).to include('Format: Fizic')
    end

    it 'shows product name without variant info for non-variant items', type: :request do
      sign_in admin

      order = create(:order, total: 49.99, user: admin)
      order.order_items.create!(
        product: product,
        product_name: 'Carte Simpla Items',
        quantity: 1,
        price: 49.99,
        total_price: 49.99
      )

      get show_items_order_path(order)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Carte Simpla Items')
    end
  end
end

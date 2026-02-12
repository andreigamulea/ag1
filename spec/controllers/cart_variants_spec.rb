require 'rails_helper'

RSpec.describe 'Cart with variants', type: :model do
  # Tests for parse_cart_key and build_cart_key helpers
  # These are public methods on ApplicationController

  let(:controller) { ApplicationController.new }

  describe '#parse_cart_key' do
    it 'parses simple product key' do
      result = controller.parse_cart_key("42")
      expect(result).to eq({ product_id: "42", variant_id: nil })
    end

    it 'parses composite product+variant key' do
      result = controller.parse_cart_key("42_v7")
      expect(result).to eq({ product_id: "42", variant_id: "7" })
    end

    it 'handles string input' do
      result = controller.parse_cart_key("123_v456")
      expect(result[:product_id]).to eq("123")
      expect(result[:variant_id]).to eq("456")
    end
  end

  describe '#build_cart_key' do
    it 'builds simple key without variant' do
      expect(controller.build_cart_key(42)).to eq("42")
    end

    it 'builds composite key with variant' do
      expect(controller.build_cart_key(42, 7)).to eq("42_v7")
    end

    it 'builds simple key when variant_id is nil' do
      expect(controller.build_cart_key(42, nil)).to eq("42")
    end

    it 'builds simple key when variant_id is blank' do
      expect(controller.build_cart_key(42, '')).to eq("42")
    end

    it 'roundtrips with parse_cart_key' do
      key = controller.build_cart_key(42, 7)
      parsed = controller.parse_cart_key(key)
      expect(parsed[:product_id]).to eq("42")
      expect(parsed[:variant_id]).to eq("7")
    end
  end
end

RSpec.describe 'Cart variant integration', type: :model do
  describe 'OrderItem with variant snapshot' do
    it 'saves variant snapshot data on order_item' do
      product = create(:product)
      variant = create(:variant, product: product, sku: 'VAR-SNAP-1', price: 49.99, vat_rate: 19)
      order = create(:order, total: 49.99)

      item = order.order_items.create!(
        product: product,
        product_name: product.name,
        variant_id: variant.id,
        variant_sku: variant.sku,
        variant_options_text: 'Red / XL',
        vat_rate_snapshot: variant.vat_rate,
        quantity: 2,
        price: variant.price,
        total_price: variant.price * 2
      )

      item.reload
      expect(item.variant_id).to eq(variant.id)
      expect(item.variant_sku).to eq('VAR-SNAP-1')
      expect(item.variant_options_text).to eq('Red / XL')
      expect(item.vat_rate_snapshot).to eq(19)
    end

    it 'allows order_item without variant (backward compatible)' do
      product = create(:product)
      order = create(:order, total: 29.99)

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
    end
  end

  describe 'load_cart cleanup' do
    it 'removes cart entries for inactive variants' do
      product = create(:product)
      variant = create(:variant, product: product, status: :inactive)

      cart = { "#{product.id}_v#{variant.id}" => { "quantity" => 1 } }

      # Simulate what load_cart does
      variant_keys = cart.keys.select { |k| k.include?("_v") }
      vids = variant_keys.map { |k| k.split("_v", 2)[1].to_i }
      valid_variants = Variant.where(id: vids, status: :active).pluck(:id, :product_id).to_h

      variant_keys.each do |key|
        parts = key.split("_v", 2)
        vid = parts[1].to_i
        pid = parts[0].to_i
        cart.delete(key) unless valid_variants[vid] == pid
      end

      expect(cart).to be_empty
    end

    it 'keeps cart entries for active variants' do
      product = create(:product)
      variant = create(:variant, product: product, status: :active)

      cart = { "#{product.id}_v#{variant.id}" => { "quantity" => 2 } }

      variant_keys = cart.keys.select { |k| k.include?("_v") }
      vids = variant_keys.map { |k| k.split("_v", 2)[1].to_i }
      valid_variants = Variant.where(id: vids, status: :active).pluck(:id, :product_id).to_h

      variant_keys.each do |key|
        parts = key.split("_v", 2)
        vid = parts[1].to_i
        pid = parts[0].to_i
        cart.delete(key) unless valid_variants[vid] == pid
      end

      expect(cart.size).to eq(1)
      expect(cart.values.first["quantity"]).to eq(2)
    end

    it 'removes cart entries for variants belonging to wrong product' do
      product1 = create(:product)
      product2 = create(:product)
      variant = create(:variant, product: product2, status: :active)

      # Wrong product_id in cart key
      cart = { "#{product1.id}_v#{variant.id}" => { "quantity" => 1 } }

      variant_keys = cart.keys.select { |k| k.include?("_v") }
      vids = variant_keys.map { |k| k.split("_v", 2)[1].to_i }
      valid_variants = Variant.where(id: vids, status: :active).pluck(:id, :product_id).to_h

      variant_keys.each do |key|
        parts = key.split("_v", 2)
        vid = parts[1].to_i
        pid = parts[0].to_i
        cart.delete(key) unless valid_variants[vid] == pid
      end

      expect(cart).to be_empty
    end
  end
end

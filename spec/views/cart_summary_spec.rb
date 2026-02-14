require 'rails_helper'

RSpec.describe 'Cart summary variant display', type: :model do
  describe 'parse_cart_key helper' do
    let(:controller) { ApplicationController.new }

    it 'parses variant cart key correctly' do
      result = controller.parse_cart_key("42_v7")
      expect(result[:product_id]).to eq("42")
      expect(result[:variant_id]).to eq("7")
    end

    it 'parses simple product key' do
      result = controller.parse_cart_key("42")
      expect(result[:product_id]).to eq("42")
      expect(result[:variant_id]).to be_nil
    end
  end

  describe 'variant effective price for cart' do
    let(:product) { create(:product, name: 'Carte Cart Test', price: 79.99) }

    it 'returns regular price when no promo' do
      variant = create(:variant, product: product,
        sku: "CART-V1-#{SecureRandom.hex(4)}", price: 59.99, stock: 10)

      expect(variant.effective_price).to eq(59.99)
    end

    it 'returns discount price when promo is active' do
      variant = create(:variant, product: product,
        sku: "CART-V2-#{SecureRandom.hex(4)}", price: 99.99,
        discount_price: 69.99, promo_active: true, stock: 10)

      expect(variant.effective_price).to eq(69.99)
    end

    it 'returns regular price when promo inactive even with discount set' do
      variant = create(:variant, product: product,
        sku: "CART-V3-#{SecureRandom.hex(4)}", price: 99.99,
        discount_price: 69.99, promo_active: false, stock: 10)

      expect(variant.effective_price).to eq(99.99)
    end
  end

  describe 'variant options_text for cart display' do
    let(:product) { create(:product, name: 'Carte Options Test', price: 79.99) }
    let(:option_type) { create(:option_type, name: "CartOT-#{SecureRandom.hex(4)}", presentation: 'Material') }

    it 'generates options text from option values' do
      ov = create(:option_value, option_type: option_type, name: "CartOV-#{SecureRandom.hex(4)}", presentation: 'Bumbac')
      variant = create(:variant, product: product,
        sku: "CART-OT-#{SecureRandom.hex(4)}", price: 59.99, stock: 10)
      create(:option_value_variant, variant: variant, option_value: ov)

      expect(variant.options_text).to include(option_type.name)
      expect(variant.options_text).to include('Bumbac')
    end

    it 'combines multiple option values' do
      ot2 = create(:option_type, name: "CartOT2-#{SecureRandom.hex(4)}", presentation: 'Culoare')
      ov1 = create(:option_value, option_type: option_type, name: "CartMat-#{SecureRandom.hex(4)}", presentation: 'Bumbac')
      ov2 = create(:option_value, option_type: ot2, name: "CartCol-#{SecureRandom.hex(4)}", presentation: 'Rosu')

      variant = create(:variant, product: product,
        sku: "CART-MC-#{SecureRandom.hex(4)}", price: 59.99, stock: 10)
      create(:option_value_variant, variant: variant, option_value: ov1)
      create(:option_value_variant, variant: variant, option_value: ov2)

      text = variant.options_text
      expect(text).to include('Bumbac')
      expect(text).to include('Rosu')
    end
  end

  describe 'cart key building for variants' do
    let(:controller) { ApplicationController.new }

    it 'builds variant key' do
      key = controller.build_cart_key(42, 7)
      expect(key).to eq("42_v7")
    end

    it 'builds simple key without variant' do
      key = controller.build_cart_key(42)
      expect(key).to eq("42")
    end

    it 'roundtrips correctly' do
      key = controller.build_cart_key(100, 25)
      parsed = controller.parse_cart_key(key)
      expect(parsed[:product_id]).to eq("100")
      expect(parsed[:variant_id]).to eq("25")
    end
  end
end

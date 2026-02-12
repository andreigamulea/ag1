require 'rails_helper'

RSpec.describe Product, 'nested variants', type: :model do
  describe 'accepts_nested_attributes_for :variants' do
    describe 'reject_if' do
      it 'rejects completely blank variant rows' do
        product = create(:product)
        product.update(variants_attributes: [
          { sku: '', price: '', stock: '', option_value_ids: [''] }
        ])
        expect(product.variants.count).to eq(0)
      end

      it 'keeps variant with partial data (fails validation)' do
        product = create(:product)
        result = product.update(variants_attributes: [
          { sku: 'TEST-SKU', price: '', stock: '' }
        ])
        # Should not reject (sku present), but validation fails (price required)
        expect(result).to be false
        expect(product.errors).not_to be_empty
      end

      it 'saves valid variant' do
        product = create(:product)
        result = product.update(variants_attributes: [
          { sku: 'VAR-1', price: 29.99, stock: 10 }
        ])
        expect(result).to be true
        expect(product.variants.count).to eq(1)
        expect(product.variants.first.sku).to eq('VAR-1')
      end

      it 'allows destroying existing variants' do
        product = create(:product)
        variant = create(:variant, product: product)
        product.update(variants_attributes: [
          { id: variant.id, _destroy: '1' }
        ])
        expect(product.variants.count).to eq(0)
      end

      it 'keeps variant with only option_value_ids selected (for re-render)' do
        product = create(:product)
        option_type = create(:option_type)
        option_value = create(:option_value, option_type: option_type)

        result = product.update(variants_attributes: [
          { sku: '', price: '', stock: '', option_value_ids: [option_value.id.to_s] }
        ])
        # Should not reject (option_value_ids present), but validation fails
        expect(result).to be false
        expect(product.errors).not_to be_empty
      end
    end
  end

  describe 'conditional price validation' do
    it 'requires price when product has no active variants' do
      product = build(:product, price: nil)
      expect(product).not_to be_valid
      expect(product.errors[:price]).to be_present
    end

    it 'does not require price when product has active variants' do
      product = create(:product, price: 10)
      create(:variant, product: product, status: :active)
      product.price = nil
      expect(product).to be_valid
    end

    it 'requires price when all variants are inactive' do
      product = create(:product, price: 10)
      create(:variant, product: product, status: :inactive)
      product.price = nil
      expect(product).not_to be_valid
    end

    it 'handles variants marked_for_destruction correctly' do
      product = create(:product, price: 10)
      variant = create(:variant, product: product, status: :active)

      # Force load the association so has_active_variants? uses the in-memory path
      product.variants.load_target
      product.variants.first.mark_for_destruction

      product.price = nil
      expect(product).not_to be_valid
    end
  end
end

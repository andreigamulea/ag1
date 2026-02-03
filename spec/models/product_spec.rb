require 'rails_helper'

RSpec.describe Product, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      product = build(:product)
      expect(product).to be_valid
    end

    it 'requires name' do
      product = build(:product, name: nil)
      expect(product).not_to be_valid
      expect(product.errors[:name]).to include("can't be blank")
    end

    it 'requires slug' do
      product = build(:product, slug: nil)
      expect(product).not_to be_valid
    end

    it 'requires price' do
      product = build(:product, price: nil)
      expect(product).not_to be_valid
    end

    it 'requires sku' do
      product = build(:product, sku: nil)
      expect(product).not_to be_valid
    end
  end

  describe '#price_breakdown' do
    it 'calculates VAT correctly for 19%' do
      product = build(:product, price: 119, vat: 19)
      breakdown = product.price_breakdown

      expect(breakdown[:brut]).to eq(119.0)
      expect(breakdown[:net]).to eq(100.0)
      expect(breakdown[:tva]).to eq(19.0)
    end

    it 'returns zero VAT when vat is 0' do
      product = build(:product, price: 100, vat: 0)
      breakdown = product.price_breakdown

      expect(breakdown[:brut]).to eq(100.0)
      expect(breakdown[:net]).to eq(100.0)
      expect(breakdown[:tva]).to eq(0.0)
    end
  end

  describe '#archive!' do
    it 'deactivates all active variants and sets product status to archived' do
      product = create(:product)
      v1 = create(:variant, product: product, status: :active, sku: 'ARC-V1')
      v1.update_column(:options_digest, Digest::SHA256.hexdigest('arc-v1'))
      v2 = create(:variant, product: product, status: :active, sku: 'ARC-V2')
      v2.update_column(:options_digest, Digest::SHA256.hexdigest('arc-v2'))

      product.archive!

      expect(v1.reload.status).to eq('inactive')
      expect(v2.reload.status).to eq('inactive')
      expect(product.reload.status).to eq('archived')
      expect(product).to be_archived
    end

    it 'handles product without variants' do
      product = create(:product)

      expect { product.archive! }.not_to raise_error
      expect(product.reload.status).to eq('archived')
      expect(product).to be_archived
    end

    it 'lock order P -> V* (ORDER BY id) runtime SQL verification', :postgres_only do
      skip_unless_supports_for_update!

      product = create(:product)
      v1 = create(:variant, product: product, sku: 'LO-ARC-V1')
      v1.update_column(:options_digest, Digest::SHA256.hexdigest('lo-arc-v1'))
      v2 = create(:variant, product: product, sku: 'LO-ARC-V2')
      v2.update_column(:options_digest, Digest::SHA256.hexdigest('lo-arc-v2'))

      lock_sequence = []

      products_lock = select_for_update_regex("products")
      vars_lock     = select_for_update_regex("variants")

      callback = ->(*, payload) {
        sql = payload[:sql].to_s
        return if sql.empty?
        return if sql =~ LockOrderHelper::SCHEMA_QUERY

        case sql
        when products_lock then lock_sequence << :product
        when vars_lock     then lock_sequence << :variants
        end
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        product.archive!
      end

      product_idx = lock_sequence.index(:product)
      variants_idx = lock_sequence.index(:variants)

      expect(product_idx).not_to be_nil, "Expected PRODUCT lock, got sequence: #{lock_sequence}"
      expect(variants_idx).not_to be_nil, "Expected VARIANTS lock, got sequence: #{lock_sequence}"
      expect(product_idx).to be < variants_idx,
        "PRODUCT must be locked before VARIANTS. Sequence: #{lock_sequence}"
    end

    it 'does not affect variants of other products' do
      product = create(:product)
      other_product = create(:product)
      v1 = create(:variant, product: product, status: :active, sku: 'ARC-OWN')
      other_v = create(:variant, product: other_product, status: :active, sku: 'ARC-OTHER')

      product.archive!

      expect(v1.reload.status).to eq('inactive')
      expect(other_v.reload.status).to eq('active')  # UNTOUCHED
    end

    it 'handles mixed state: active + inactive variants' do
      product = create(:product)
      active_v = create(:variant, product: product, status: :active, sku: 'ARC-ACT')
      active_v.update_column(:options_digest, Digest::SHA256.hexdigest('arc-act'))
      inactive_v = create(:variant, product: product, status: :inactive, sku: 'ARC-INACT')
      inactive_v.update_column(:options_digest, Digest::SHA256.hexdigest('arc-inact'))

      product.archive!

      expect(active_v.reload.status).to eq('inactive')
      expect(inactive_v.reload.status).to eq('inactive')
      expect(product.reload).to be_archived
    end
  end

  describe 'variant associations' do
    it 'has many variants' do
      product = create(:product)
      # Una activă, una inactivă (pentru a respecta idx_unique_active_default_variant)
      variant1 = create(:variant, product: product, status: :active)
      variant2 = create(:variant, product: product, status: :inactive)

      expect(product.variants).to include(variant1, variant2)
    end

    it 'has many option_types through product_option_types' do
      product = create(:product)
      color = create(:option_type, name: 'Culoare')
      size = create(:option_type, name: 'Mărime')

      create(:product_option_type, product: product, option_type: color)
      create(:product_option_type, product: product, option_type: size)

      expect(product.option_types).to include(color, size)
    end

    it 'restricts deletion when variants exist' do
      product = create(:product)
      create(:variant, product: product)

      expect { product.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end

    it 'destroys product_option_types when destroyed' do
      product = create(:product)
      create(:product_option_type, product: product)

      # No variants, so deletion should work and cascade to product_option_types
      expect { product.destroy }.to change(ProductOptionType, :count).by(-1)
    end
  end
end

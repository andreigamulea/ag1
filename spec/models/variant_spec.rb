require 'rails_helper'

RSpec.describe Variant, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      variant = build(:variant)
      expect(variant).to be_valid
    end

    it 'requires sku' do
      variant = build(:variant, sku: nil)
      expect(variant).not_to be_valid
      expect(variant.errors[:sku]).to include("can't be blank")
    end

    it 'requires unique sku within product' do
      product = create(:product)
      create(:variant, product: product, sku: 'SKU-001')
      duplicate = build(:variant, product: product, sku: 'SKU-001')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:sku]).to include('has already been taken')
    end

    it 'allows same sku in different products' do
      product1 = create(:product)
      product2 = create(:product)

      create(:variant, product: product1, sku: 'SHARED-SKU')
      variant2 = build(:variant, product: product2, sku: 'SHARED-SKU')

      expect(variant2).to be_valid
    end

    it 'requires price >= 0' do
      variant = build(:variant, price: -1)
      expect(variant).not_to be_valid
    end

    it 'requires stock >= 0' do
      variant = build(:variant, stock: -1)
      expect(variant).not_to be_valid
    end
  end

  describe 'enum status' do
    it 'defaults to active' do
      variant = create(:variant)
      expect(variant).to be_active
    end

    it 'can be set to inactive' do
      variant = create(:variant, status: :inactive)
      expect(variant).to be_inactive
    end
  end

  describe '#options_text' do
    it 'returns formatted options string' do
      color_type = create(:option_type, name: 'Culoare')
      size_type = create(:option_type, name: 'Mărime')
      red = create(:option_value, option_type: color_type, name: 'Roșu', presentation: nil)
      medium = create(:option_value, option_type: size_type, name: 'M', presentation: nil)

      variant = create(:variant)
      create(:option_value_variant, variant: variant, option_value: red)
      create(:option_value_variant, variant: variant, option_value: medium)

      expect(variant.options_text).to include('Culoare: Roșu')
      expect(variant.options_text).to include('Mărime: M')
    end
  end

  describe '#price_breakdown' do
    it 'calculates VAT correctly for 19%' do
      variant = build(:variant, price: 119, vat_rate: 19)
      breakdown = variant.price_breakdown

      expect(breakdown[:brut]).to eq(119.0)
      expect(breakdown[:net]).to eq(100.0)
      expect(breakdown[:tva]).to eq(19.0)
    end

    it 'returns zero VAT when vat_rate is 0' do
      variant = build(:variant, price: 100, vat_rate: 0)
      breakdown = variant.price_breakdown

      expect(breakdown[:brut]).to eq(100.0)
      expect(breakdown[:net]).to eq(100.0)
      expect(breakdown[:tva]).to eq(0.0)
    end

    it 'returns zero VAT when vat_rate is nil' do
      variant = build(:variant, price: 100, vat_rate: nil)
      breakdown = variant.price_breakdown

      expect(breakdown[:brut]).to eq(100.0)
      expect(breakdown[:net]).to eq(100.0)
      expect(breakdown[:tva]).to eq(0.0)
    end
  end

  describe '#compute_options_digest' do
    it 'generates digest based on option_value_ids' do
      variant = create(:variant)
      ov1 = create(:option_value)
      ov2 = create(:option_value)

      create(:option_value_variant, variant: variant, option_value: ov1)
      create(:option_value_variant, variant: variant, option_value: ov2)

      # Reload pentru a vedea asocierile noi, apoi save pentru a recalcula digest
      variant.reload
      variant.save!
      expect(variant.options_digest).to be_present
    end

    it 'returns nil when no option_values' do
      variant = create(:variant)
      variant.save!
      expect(variant.options_digest).to be_nil
    end

    it 'generates same digest for same option_values regardless of order' do
      ov1 = create(:option_value)
      ov2 = create(:option_value)

      variant1 = create(:variant)
      create(:option_value_variant, variant: variant1, option_value: ov1)
      create(:option_value_variant, variant: variant1, option_value: ov2)
      variant1.reload
      variant1.save!

      # variant2 trebuie să fie inactiv (același produs default ar viola unique constraint)
      variant2 = create(:variant, status: :inactive)
      create(:option_value_variant, variant: variant2, option_value: ov2)
      create(:option_value_variant, variant: variant2, option_value: ov1)
      variant2.reload
      variant2.save!

      expect(variant1.options_digest).to eq(variant2.options_digest)
    end
  end

  describe 'associations' do
    it 'destroys option_value_variants when destroyed' do
      variant = create(:variant)
      create(:option_value_variant, variant: variant)

      expect { variant.destroy }.to change(OptionValueVariant, :count).by(-1)
    end

    it 'destroys external_ids when destroyed' do
      variant = create(:variant)
      create(:variant_external_id, variant: variant)

      expect { variant.destroy }.to change(VariantExternalId, :count).by(-1)
    end
  end
end

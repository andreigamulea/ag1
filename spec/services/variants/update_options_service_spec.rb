# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Variants::UpdateOptionsService do
  let(:service) { described_class.new }
  let(:product) { create(:product) }
  let(:option_type1) { create(:option_type, name: 'Color') }
  let(:option_type2) { create(:option_type, name: 'Size') }
  let(:ov_red) { create(:option_value, option_type: option_type1, name: 'Red') }
  let(:ov_blue) { create(:option_value, option_type: option_type1, name: 'Blue') }
  let(:ov_m) { create(:option_value, option_type: option_type2, name: 'M') }
  let(:ov_l) { create(:option_value, option_type: option_type2, name: 'L') }

  before do
    create(:product_option_type, product: product, option_type: option_type1)
    create(:product_option_type, product: product, option_type: option_type2)
  end

  # Helper: calculează digest exact ca Variant#compute_options_digest
  def digest_for(*option_value_ids)
    ids = option_value_ids.flatten.sort
    ids.any? ? Digest::SHA256.hexdigest(ids.join('-')) : nil
  end

  # Helper: creează variantă cu opțiuni corect linkate și digest setat
  def create_variant_with_options(product:, option_value_ids:, **attrs)
    variant = create(:variant, product: product, **attrs)
    d = digest_for(option_value_ids)
    variant.update_column(:options_digest, d) if d
    option_value_ids.each do |ov_id|
      variant.option_value_variants.create!(option_value_id: ov_id)
    end
    variant.reload
  end

  describe '#call' do
    context 'successful update' do
      it 'updates option_values and recalculates digest' do
        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )

        result = service.call(
          variant: variant,
          option_value_ids: [ov_blue.id, ov_l.id]
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:updated)
        expect(result.variant.option_values).to match_array([ov_blue, ov_l])
        expect(result.variant.options_digest).to eq(digest_for(ov_blue.id, ov_l.id))
      end

      it 'updates to single option_value' do
        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )

        result = service.call(
          variant: variant,
          option_value_ids: [ov_red.id]
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:updated)
        expect(result.variant.option_values).to eq([ov_red])
      end
    end

    context 'FIX 8.2: no false positive conflict with self' do
      it 'succeeds when updating with same option_value_ids (no-op digest)' do
        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )

        # Noul digest == digest curent → NU trebuie să fie conflict
        result = service.call(
          variant: variant,
          option_value_ids: [ov_red.id, ov_m.id]
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:updated)
      end
    end

    context 'conflict with another variant' do
      it 'returns :conflict when another active variant has same digest' do
        # Creează prima variantă cu Red+M
        create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )

        # Creează a doua variantă cu Blue+L
        variant2 = create_variant_with_options(
          product: product,
          option_value_ids: [ov_blue.id, ov_l.id],
          sku: 'BLUE-L'
        )

        # Încercăm să schimbăm a doua variantă la Red+M → conflict
        result = service.call(
          variant: variant2,
          option_value_ids: [ov_red.id, ov_m.id]
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
        expect(result.error).to match(/already exists/i)
      end
    end

    context 'validation errors' do
      it 'returns :invalid when option_value does not exist' do
        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )
        non_existent_id = OptionValue.maximum(:id).to_i + 1

        result = service.call(
          variant: variant,
          option_value_ids: [ov_red.id, non_existent_id]
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:invalid)
        expect(result.error).to match(/Invalid option_value_ids/i)
      end

      it 'returns :invalid when two option_values from same option_type' do
        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )

        result = service.call(
          variant: variant,
          option_value_ids: [ov_red.id, ov_blue.id]  # Both Color
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:invalid)
        expect(result.error).to match(/Invalid option_value_ids/i)
      end

      it 'returns :invalid when option_type not associated with product' do
        unassociated_type = create(:option_type, name: 'Material')
        unassociated_value = create(:option_value, option_type: unassociated_type, name: 'Cotton')

        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )

        result = service.call(
          variant: variant,
          option_value_ids: [ov_red.id, unassociated_value.id]
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:invalid)
        expect(result.error).to match(/Invalid option_value_ids/i)
      end
    end

    context 'update to empty options (become default)' do
      it 'updates to default variant (no options)' do
        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )

        result = service.call(
          variant: variant,
          option_value_ids: []
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:updated)
        expect(result.variant.options_digest).to be_nil
        expect(result.variant.option_values).to be_empty
      end
    end
  end
end

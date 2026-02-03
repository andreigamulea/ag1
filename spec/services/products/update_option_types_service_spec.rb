# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Products::UpdateOptionTypesService do
  let(:service) { described_class.new }
  let(:product) { create(:product) }
  let(:option_type_color) { create(:option_type, name: 'Color') }
  let(:option_type_size) { create(:option_type, name: 'Size') }
  let(:option_type_material) { create(:option_type, name: 'Material') }

  def digest_for(*option_value_ids)
    ids = option_value_ids.flatten.sort
    ids.any? ? Digest::SHA256.hexdigest(ids.join('-')) : nil
  end

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
    context 'adding option_types' do
      it 'adds option_types to product' do
        result = service.call(
          product: product,
          option_type_ids: [option_type_color.id, option_type_size.id]
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:added)
        expect(result.added).to match_array([option_type_color.id, option_type_size.id])
        expect(result.removed).to be_empty
        expect(result.product.option_types).to match_array([option_type_color, option_type_size])
      end

      it 'adds additional option_type to existing ones' do
        create(:product_option_type, product: product, option_type: option_type_color)

        result = service.call(
          product: product,
          option_type_ids: [option_type_color.id, option_type_size.id]
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:added)
        expect(result.added).to eq([option_type_size.id])
        expect(result.product.option_types).to match_array([option_type_color, option_type_size])
      end
    end

    context 'removing option_types' do
      let(:ov_red) { create(:option_value, option_type: option_type_color, name: 'Red') }
      let(:ov_m) { create(:option_value, option_type: option_type_size, name: 'M') }

      before do
        create(:product_option_type, product: product, option_type: option_type_color)
        create(:product_option_type, product: product, option_type: option_type_size)
      end

      it 'removes option_type and deactivates affected variants' do
        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id, ov_m.id],
          sku: 'RED-M'
        )

        # Ștergem Size → varianta cu Red+M devine incompletă → dezactivată
        result = service.call(
          product: product,
          option_type_ids: [option_type_color.id]
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:removed)
        expect(result.removed).to eq([option_type_size.id])
        expect(result.deactivated_count).to eq(1)
        expect(variant.reload.status).to eq('inactive')
      end

      it 'does not deactivate variants without affected option_values' do
        # Variantă doar cu Color (fără Size)
        variant_color_only = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id],
          sku: 'RED-ONLY'
        )

        # Ștergem Size → varianta cu doar Red NU e afectată
        result = service.call(
          product: product,
          option_type_ids: [option_type_color.id]
        )

        expect(result.success?).to be true
        expect(result.deactivated_count).to eq(0)
        expect(variant_color_only.reload.status).to eq('active')
      end
    end

    context 'replacing option_types' do
      before do
        create(:product_option_type, product: product, option_type: option_type_color)
      end

      it 'replaces option_types (remove old, add new)' do
        result = service.call(
          product: product,
          option_type_ids: [option_type_size.id, option_type_material.id]
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:replaced)
        expect(result.added).to match_array([option_type_size.id, option_type_material.id])
        expect(result.removed).to eq([option_type_color.id])
        expect(result.product.option_types).to match_array([option_type_size, option_type_material])
      end
    end

    context 'no changes' do
      before do
        create(:product_option_type, product: product, option_type: option_type_color)
      end

      it 'returns :unchanged when option_types are the same' do
        result = service.call(
          product: product,
          option_type_ids: [option_type_color.id]
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:unchanged)
        expect(result.added).to be_empty
        expect(result.removed).to be_empty
      end
    end

    context 'lock order P → V (ORDER BY id)' do
      let(:ov_red) { create(:option_value, option_type: option_type_color, name: 'Red') }
      let(:ov_blue) { create(:option_value, option_type: option_type_color, name: 'Blue') }

      before do
        create(:product_option_type, product: product, option_type: option_type_color)
        create(:product_option_type, product: product, option_type: option_type_size)
      end

      it 'locks product before variants' do
        # Creăm 2 variante cu IDs diferite
        v1 = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id],
          sku: 'RED'
        )
        v2 = create_variant_with_options(
          product: product,
          option_value_ids: [ov_blue.id],
          sku: 'BLUE'
        )

        # Verificăm că serviciul execută fără deadlock
        result = service.call(
          product: product,
          option_type_ids: []  # Șterge toate → dezactivează ambele
        )

        expect(result.success?).to be true
        expect(result.deactivated_count).to eq(2)
        expect(v1.reload.status).to eq('inactive')
        expect(v2.reload.status).to eq('inactive')
      end
    end

    context 'digest recalculation' do
      let(:ov_red) { create(:option_value, option_type: option_type_color, name: 'Red') }
      let(:ov_m) { create(:option_value, option_type: option_type_size, name: 'M') }

      before do
        create(:product_option_type, product: product, option_type: option_type_color)
        create(:product_option_type, product: product, option_type: option_type_size)
      end

      it 'recalculates digests for remaining active variants after removal' do
        # Variantă doar cu Color (nu e afectată de ștergerea Size)
        variant = create_variant_with_options(
          product: product,
          option_value_ids: [ov_red.id],
          sku: 'RED-ONLY'
        )

        original_digest = variant.options_digest

        result = service.call(
          product: product,
          option_type_ids: [option_type_color.id]  # Ștergem Size
        )

        expect(result.success?).to be true
        # Digest-ul rămâne identic (aceleași option_values)
        expect(variant.reload.options_digest).to eq(original_digest)
      end
    end
  end
end

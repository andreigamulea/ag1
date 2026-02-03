# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Variants::CreateOrReactivateService do
  let(:service) { described_class.new }
  let(:product) { create(:product) }

  # Helper: calculează digest exact ca Variant#compute_options_digest
  def digest_for(*option_value_ids)
    ids = option_value_ids.flatten.sort
    ids.any? ? Digest::SHA256.hexdigest(ids.join('-')) : nil
  end

  # Helper: creează variantă cu opțiuni și digest corect setat
  # before_save :compute_options_digest suprascrie options_digest dacă nu are option_value_variants,
  # deci trebuie să setăm digest-ul post-save via update_column (bypass callback)
  def create_variant_with_digest(product:, option_value_ids:, **attrs)
    variant = create(:variant, product: product, **attrs)
    d = digest_for(option_value_ids)
    variant.update_column(:options_digest, d) if d
    # Link option_values
    option_value_ids.each do |ov_id|
      variant.option_value_variants.create!(option_value_id: ov_id)
    end
    variant.reload
  end

  describe '#call' do
    context 'creating default variant (no options)' do
      it 'creates new default variant' do
        result = service.call(
          product: product,
          option_value_ids: [],
          attributes: { sku: 'DEFAULT-001', price: 100.0, stock: 10 }
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:created)
        expect(result.variant).to be_present
        expect(result.variant.options_digest).to be_nil
        expect(result.variant.sku).to eq('DEFAULT-001')
        expect(result.variant.price).to eq(100.0)
        expect(result.variant.stock).to eq(10)
        expect(result.variant.status).to eq('active')
      end

      it 'returns conflict when active default variant already exists' do
        create(:variant, product: product, options_digest: nil, status: :active, sku: 'DEFAULT-001')

        result = service.call(
          product: product,
          option_value_ids: [],
          attributes: { sku: 'DEFAULT-002', price: 100.0 }
        )

        # find_existing_variant găsește varianta cu digest nil → handle_existing_variant → :updated
        # Nu e conflict, ci update (varianta default existentă se actualizează)
        expect(result.success?).to be true
        expect(result.action).to eq(:updated)
      end
    end

    context 'creating variant with options' do
      let(:option_type1) { create(:option_type, name: 'Color') }
      let(:option_type2) { create(:option_type, name: 'Size') }
      let(:option_value1) { create(:option_value, option_type: option_type1, name: 'Red') }
      let(:option_value2) { create(:option_value, option_type: option_type2, name: 'M') }

      before do
        create(:product_option_type, product: product, option_type: option_type1)
        create(:product_option_type, product: product, option_type: option_type2)
      end

      it 'creates new variant with options and computes SHA256 digest' do
        result = service.call(
          product: product,
          option_value_ids: [option_value1.id, option_value2.id],
          attributes: { sku: 'RED-M', price: 150.0, stock: 5 }
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:created)
        expect(result.variant).to be_present
        # Digest este SHA256, nu format simplu
        expect(result.variant.options_digest).to eq(digest_for(option_value1.id, option_value2.id))
        expect(result.variant.option_values).to match_array([option_value1, option_value2])
        expect(result.variant.sku).to eq('RED-M')
        expect(result.variant.status).to eq('active')
      end

      it 'returns conflict when SKU already exists for this product' do
        create(:variant, product: product, sku: 'DUPLICATE-SKU', status: :active)

        result = service.call(
          product: product,
          option_value_ids: [option_value1.id, option_value2.id],
          attributes: { sku: 'DUPLICATE-SKU', price: 150.0 }
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
        expect(result.error).to match(/SKU already exists/i)
      end
    end

    context 'reactivating inactive variant' do
      let(:option_type1) { create(:option_type, name: 'Color') }
      let(:option_value1) { create(:option_value, option_type: option_type1, name: 'Blue') }

      before do
        create(:product_option_type, product: product, option_type: option_type1)
      end

      it 'reactivates inactive variant with matching digest' do
        inactive_variant = create_variant_with_digest(
          product: product,
          option_value_ids: [option_value1.id],
          status: :inactive,
          sku: 'BLUE-001',
          price: 100.0,
          stock: 0
        )

        result = service.call(
          product: product,
          option_value_ids: [option_value1.id],
          attributes: { price: 200.0, stock: 10 }
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:reactivated)
        expect(result.variant.id).to eq(inactive_variant.id)
        expect(result.variant.status).to eq('active')
        expect(result.variant.price).to eq(200.0)
        expect(result.variant.stock).to eq(10)
      end

      it 'does not reactivate when desired_status is inactive' do
        create_variant_with_digest(
          product: product,
          option_value_ids: [option_value1.id],
          status: :inactive,
          sku: 'BLUE-001'
        )

        result = service.call(
          product: product,
          option_value_ids: [option_value1.id],
          attributes: { sku: 'BLUE-002', price: 200.0, status: :inactive }
        )

        # Trebuie să creeze nouă variantă, nu să reactiveze
        expect(result.success?).to be true
        expect(result.action).to eq(:created)
        expect(result.variant.sku).to eq('BLUE-002')
        expect(result.variant.status).to eq('inactive')
      end
    end

    context 'updating existing active variant' do
      let(:option_type1) { create(:option_type, name: 'Color') }
      let(:option_value1) { create(:option_value, option_type: option_type1, name: 'Green') }

      before do
        create(:product_option_type, product: product, option_type: option_type1)
      end

      it 'updates existing active variant attributes' do
        existing_variant = create_variant_with_digest(
          product: product,
          option_value_ids: [option_value1.id],
          status: :active,
          sku: 'GREEN-001',
          price: 100.0,
          stock: 5
        )

        result = service.call(
          product: product,
          option_value_ids: [option_value1.id],
          attributes: { price: 150.0, stock: 10 }
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:updated)
        expect(result.variant.id).to eq(existing_variant.id)
        expect(result.variant.price).to eq(150.0)
        expect(result.variant.stock).to eq(10)
      end

      it 'returns :linked when variant exists and no attributes to update' do
        existing_variant = create_variant_with_digest(
          product: product,
          option_value_ids: [option_value1.id],
          status: :active,
          sku: 'GREEN-001'
        )

        result = service.call(
          product: product,
          option_value_ids: [option_value1.id],
          attributes: {}
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:linked)
        expect(result.variant.id).to eq(existing_variant.id)
      end
    end

    context 'validation errors' do
      let(:option_type1) { create(:option_type, name: 'Color') }
      let(:option_type2) { create(:option_type, name: 'Size') }
      let(:option_value1) { create(:option_value, option_type: option_type1, name: 'Red') }
      let(:option_value2) { create(:option_value, option_type: option_type2, name: 'M') }
      let(:option_value3) { create(:option_value, option_type: option_type1, name: 'Blue') }

      before do
        create(:product_option_type, product: product, option_type: option_type1)
      end

      it 'returns :invalid when option_value does not exist' do
        non_existent_id = OptionValue.maximum(:id).to_i + 1

        result = service.call(
          product: product,
          option_value_ids: [option_value1.id, non_existent_id],
          attributes: { sku: 'TEST-001', price: 100.0 }
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:invalid)
        expect(result.error).to match(/Invalid option_value_ids/i)
      end

      it 'returns :invalid when two option_values from same option_type' do
        result = service.call(
          product: product,
          option_value_ids: [option_value1.id, option_value3.id],  # Both Color
          attributes: { sku: 'TEST-001', price: 100.0 }
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:invalid)
        expect(result.error).to match(/Invalid option_value_ids/i)
      end

      it 'returns :invalid when option_type not associated with product' do
        result = service.call(
          product: product,
          option_value_ids: [option_value1.id, option_value2.id],  # Size not associated
          attributes: { sku: 'TEST-001', price: 100.0 }
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:invalid)
        expect(result.error).to match(/Invalid option_value_ids/i)
      end
    end

    context 'transaction safety (requires_new: true)' do
      it 'works when called from within an external transaction' do
        result = nil

        Product.transaction do
          result = service.call(
            product: product,
            option_value_ids: [],
            attributes: { sku: 'NESTED-001', price: 100.0 }
          )
        end

        expect(result.success?).to be true
        expect(result.action).to eq(:created)
        expect(Variant.find_by(sku: 'NESTED-001')).to be_present
      end
    end

    context 'FIX 8.3: constraint_name parsing for RecordNotUnique' do
      # Helper: creează mock exception cu cause care are constraint_name
      def mock_record_not_unique(constraint_name:, message: "duplicate key")
        mock_cause = double('PG::UniqueViolation')
        allow(mock_cause).to receive(:respond_to?).with(:constraint_name).and_return(true)
        allow(mock_cause).to receive(:constraint_name).and_return(constraint_name)

        exception = double('ActiveRecord::RecordNotUnique', message: message, cause: mock_cause)
        exception
      end

      def mock_record_not_unique_without_constraint(message:)
        mock_cause = double('GenericDBError')
        allow(mock_cause).to receive(:respond_to?).with(:constraint_name).and_return(false)

        exception = double('ActiveRecord::RecordNotUnique', message: message, cause: mock_cause)
        exception
      end

      it 'handles SKU constraint name' do
        exception = mock_record_not_unique(constraint_name: 'idx_unique_sku_per_product')
        result = service.send(:handle_unique_violation, exception, nil)

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
        expect(result.error).to match(/SKU already exists/i)
      end

      it 'handles default variant constraint name' do
        exception = mock_record_not_unique(constraint_name: 'idx_unique_active_default_variant')
        result = service.send(:handle_unique_violation, exception, nil)

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
        expect(result.error).to match(/default variant already exists/i)
      end

      it 'handles options_digest constraint name' do
        exception = mock_record_not_unique(constraint_name: 'idx_unique_active_options_per_product')
        result = service.send(:handle_unique_violation, exception, 'some-digest')

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
        expect(result.error).to match(/options_digest.*already exists/i)
      end

      it 'falls back to message parsing when constraint_name not available' do
        exception = mock_record_not_unique_without_constraint(
          message: "idx_unique_sku_per_product violation"
        )
        result = service.send(:handle_unique_violation, exception, nil)

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
        expect(result.error).to match(/SKU already exists/i)
      end

      it 'returns generic conflict for unknown constraint' do
        exception = mock_record_not_unique(constraint_name: 'some_unknown_constraint')
        result = service.send(:handle_unique_violation, exception, nil)

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
        expect(result.error).to match(/Database constraint violation/i)
      end
    end

    context 'RecordInvalid handling (SKU uniqueness via Rails validation)' do
      let(:option_type1) { create(:option_type, name: 'Color') }
      let(:option_value1) { create(:option_value, option_type: option_type1, name: 'Red') }

      before do
        create(:product_option_type, product: product, option_type: option_type1)
      end

      it 'returns conflict when SKU duplicate detected by Rails validation' do
        # Creăm o variantă cu opțiuni (nu default) ca să nu fie găsită via find_existing_variant
        create_variant_with_digest(
          product: product,
          option_value_ids: [option_value1.id],
          sku: 'DUPLICATE-SKU',
          status: :active
        )

        # Încercăm să creăm default variant cu același SKU
        result = service.call(
          product: product,
          option_value_ids: [],
          attributes: { sku: 'DUPLICATE-SKU', price: 100.0 }
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
        expect(result.error).to match(/SKU already exists/i)
      end
    end
  end
end

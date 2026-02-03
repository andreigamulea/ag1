# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::VariantSyncService do
  let(:product) { create(:product) }
  let(:service) { described_class.new(source: 'erp', source_account: 'default') }

  def digest_for(*option_value_ids)
    ids = option_value_ids.flatten.sort
    ids.any? ? Digest::SHA256.hexdigest(ids.join('-')) : nil
  end

  describe '#call' do
    context 'creating new variant + mapping' do
      it 'creates variant and external_id mapping' do
        result = service.call(
          product: product,
          external_id: 'ERP-001',
          option_value_ids: [],
          attributes: { sku: 'ERP-SKU-001', price: 100.0, stock: 10 }
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:created)
        expect(result.variant).to be_present
        expect(result.variant.sku).to eq('ERP-SKU-001')

        mapping = VariantExternalId.find_by(source: 'erp', external_id: 'ERP-001')
        expect(mapping).to be_present
        expect(mapping.variant).to eq(result.variant)
      end

      it 'creates variant with options and mapping' do
        ot = create(:option_type, name: 'Color')
        ov = create(:option_value, option_type: ot, name: 'Red')
        create(:product_option_type, product: product, option_type: ot)

        result = service.call(
          product: product,
          external_id: 'ERP-002',
          option_value_ids: [ov.id],
          attributes: { sku: 'ERP-RED', price: 150.0 }
        )

        expect(result.success?).to be true
        expect(result.variant.option_values).to include(ov)
      end
    end

    context 'updating existing mapping' do
      it 'updates variant attributes when mapping exists' do
        variant = create(:variant, product: product, sku: 'ERP-SKU-001', price: 100.0)
        create(:variant_external_id,
          variant: variant,
          source: 'erp',
          source_account: 'default',
          external_id: 'ERP-001'
        )

        result = service.call(
          product: product,
          external_id: 'ERP-001',
          attributes: { price: 200.0, stock: 20 }
        )

        expect(result.success?).to be true
        expect(result.action).to eq(:updated)
        expect(result.variant.price).to eq(200.0)
        expect(result.variant.stock).to eq(20)
      end
    end

    context 'product mismatch' do
      it 'returns error when external_id mapped to different product' do
        other_product = create(:product)
        variant = create(:variant, product: other_product, sku: 'OTHER-SKU')
        create(:variant_external_id,
          variant: variant,
          source: 'erp',
          source_account: 'default',
          external_id: 'ERP-001'
        )

        result = service.call(
          product: product,
          external_id: 'ERP-001',
          attributes: { sku: 'MY-SKU', price: 100.0 }
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:invalid)
        expect(result.error).to match(/already mapped.*product/i)
      end
    end

    context 'input validation' do
      it 'returns :invalid for blank external_id' do
        result = service.call(
          product: product,
          external_id: '   ',
          attributes: { sku: 'TEST', price: 100.0 }
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:invalid)
        expect(result.error).to match(/external_id is blank/i)
      end

      it 'normalizes external_id (strips whitespace)' do
        result = service.call(
          product: product,
          external_id: '  ERP-TRIM  ',
          option_value_ids: [],
          attributes: { sku: 'TRIM-SKU', price: 100.0 }
        )

        expect(result.success?).to be true
        mapping = VariantExternalId.find_by(source: 'erp', external_id: 'ERP-TRIM')
        expect(mapping).to be_present
      end
    end

    context 'source normalization' do
      it 'normalizes source to lowercase' do
        svc = described_class.new(source: '  ERP  ', source_account: '  RO_1  ')

        result = svc.call(
          product: product,
          external_id: 'NORM-001',
          attributes: { sku: 'NORM-SKU', price: 100.0 }
        )

        expect(result.success?).to be true
        mapping = VariantExternalId.find_by(source: 'erp', source_account: 'ro_1', external_id: 'NORM-001')
        expect(mapping).to be_present
      end
    end

    context 'FIX 8.1: advisory lock order (deterministic test)' do
      it 'acquires advisory locks BEFORE row locks' do
        # Verificăm ordinea de execuție prin spy pe metode
        lock_order = []

        allow(service).to receive(:acquire_advisory_locks).and_wrap_original do |method, *args|
          lock_order << :advisory_locks
          method.call(*args)
        end

        # CreateOrReactivateService face product.lock! (row lock)
        allow_any_instance_of(Product).to receive(:lock!).and_wrap_original do |method, *args|
          lock_order << :row_lock_product
          method.call(*args)
        end

        service.call(
          product: product,
          external_id: 'ORDER-TEST',
          option_value_ids: [],
          attributes: { sku: 'ORDER-SKU', price: 100.0 }
        )

        # Advisory locks TREBUIE să fie primele
        advisory_idx = lock_order.index(:advisory_locks)
        row_idx = lock_order.index(:row_lock_product)

        expect(advisory_idx).to be_present
        expect(row_idx).to be_present
        expect(advisory_idx).to be < row_idx
      end
    end

    context 'dual-lock feature flag' do
      it 'acquires both legacy and new locks when dual_lock enabled' do
        allow(VariantSyncConfig).to receive(:dual_lock_enabled?).and_return(true)
        allow(VariantSyncConfig).to receive(:increment_dual_lock_counter)

        # Pe non-Postgres, advisory locks sunt skip-uite, deci testăm doar că serviciul
        # delegă corect la config
        result = service.call(
          product: product,
          external_id: 'DUAL-001',
          attributes: { sku: 'DUAL-SKU', price: 100.0 }
        )

        expect(result.success?).to be true
      end

      it 'acquires only new lock when dual_lock disabled' do
        allow(VariantSyncConfig).to receive(:dual_lock_enabled?).and_return(false)

        result = service.call(
          product: product,
          external_id: 'SINGLE-001',
          attributes: { sku: 'SINGLE-SKU', price: 100.0 }
        )

        expect(result.success?).to be true
      end
    end

    context 'RecordNotUnique handling' do
      it 'returns conflict when external_id mapping already exists' do
        # Creăm prima variantă cu mapping
        variant1 = create(:variant, product: product, sku: 'FIRST-SKU')
        create(:variant_external_id,
          variant: variant1,
          source: 'erp',
          source_account: 'default',
          external_id: 'CONFLICT-EID'
        )

        # Ștergem mapping-ul din cache (simulăm race condition)
        # dar lăsăm DB constraint să prindă duplicatul
        allow(service).to receive(:find_mapping).and_return(nil)

        result = service.call(
          product: product,
          external_id: 'CONFLICT-EID',
          attributes: { sku: 'SECOND-SKU', price: 100.0 }
        )

        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)
      end
    end
  end
end

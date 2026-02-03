# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Variants::AdminExternalIdService do
  let(:product) { create(:product) }
  let(:variant) { create(:variant, product: product) }
  let(:service) { described_class.new(variant) }

  describe '#link' do
    it 'creates new mapping successfully' do
      result = service.link(source: 'erp', external_id: 'EXT-001')

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:linked)
      expect(result[:mapping]).to be_a(VariantExternalId)
      expect(result[:mapping].source).to eq('erp')
      expect(result[:mapping].source_account).to eq('default')
      expect(result[:mapping].external_id).to eq('EXT-001')
      expect(result[:mapping].variant_id).to eq(variant.id)
    end

    it 'returns :already_linked when same variant already mapped' do
      service.link(source: 'erp', external_id: 'EXT-001')
      result = service.link(source: 'erp', external_id: 'EXT-001')

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:already_linked)
      expect(result[:mapping]).to be_a(VariantExternalId)
    end

    it 'returns :conflict when different variant already mapped' do
      other_variant = create(:variant, product: product, status: :inactive)
      other_service = described_class.new(other_variant)
      other_service.link(source: 'erp', external_id: 'EXT-001')

      result = service.link(source: 'erp', external_id: 'EXT-001')

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:conflict)
      expect(result[:error]).to match(/deja folosit/)
    end

    it 'returns error when source is blank' do
      result = service.link(source: '', external_id: 'EXT-001')

      expect(result[:success]).to be false
      expect(result[:error]).to match(/source obligatoriu/)
    end

    it 'returns error when external_id is blank' do
      result = service.link(source: 'erp', external_id: '')

      expect(result[:success]).to be false
      expect(result[:error]).to match(/external_id obligatoriu/)
    end

    it 'normalizes source and source_account' do
      result = service.link(source: '  ERP  ', source_account: '  ACCOUNT1  ', external_id: 'EXT-001')

      expect(result[:success]).to be true
      expect(result[:mapping].source).to eq('erp')
      expect(result[:mapping].source_account).to eq('account1')
    end

    it 'stores external_sku when provided' do
      result = service.link(source: 'erp', external_id: 'EXT-001', external_sku: '  SKU-ABC  ')

      expect(result[:success]).to be true
      expect(result[:mapping].external_sku).to eq('SKU-ABC')
    end

    it 'handles RecordNotUnique (race condition fallback)' do
      # Simulate: first call creates, parallel call hits unique constraint
      service.link(source: 'erp', external_id: 'EXT-RACE')

      # Bypass find_by to simulate race: someone else inserted between find_by and create
      allow(VariantExternalId).to receive(:find_by).and_return(nil)
      allow_any_instance_of(ActiveRecord::Associations::CollectionProxy).to receive(:create!)
        .and_raise(ActiveRecord::RecordNotUnique.new("duplicate key"))

      result = service.link(source: 'erp', external_id: 'EXT-RACE2')

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:conflict)
    end
  end

  describe 'advisory lock transaction guard', :postgres_only do
    it 'works correctly inside VariantExternalId.transaction' do
      skip_unless_supports_for_update!

      # link/unlink already use VariantExternalId.transaction internally,
      # so this should work without error
      result = service.link(source: 'erp', external_id: 'GUARD-OK')
      expect(result[:success]).to be true
    end

    it 'raises RuntimeError when advisory lock called without transaction' do
      skip_unless_supports_for_update!

      # Simulate: mock advisory_lock_connection to report no open transaction
      mock_conn = double('Connection', adapter_name: 'PostgreSQL')
      allow(mock_conn).to receive(:respond_to?).with(:transaction_open?).and_return(true)
      allow(mock_conn).to receive(:transaction_open?).and_return(false)
      allow(mock_conn).to receive_message_chain(:pool, :db_config, :name).and_return('test_db')
      allow(service).to receive(:advisory_lock_connection).and_return(mock_conn)

      # Bypass VariantExternalId.transaction to simulate calling lock outside transaction
      allow(VariantExternalId).to receive(:transaction).and_yield

      expect {
        service.link(source: 'erp', external_id: 'GUARD-FAIL')
      }.to raise_error(RuntimeError, /pg_advisory_xact_lock requires an open transaction/)
    end
  end

  describe '#unlink' do
    it 'destroys existing mapping' do
      service.link(source: 'erp', external_id: 'EXT-001')
      expect(variant.external_ids.count).to eq(1)

      result = service.unlink(source: 'erp', external_id: 'EXT-001')

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:unlinked)
      expect(variant.external_ids.count).to eq(0)
    end

    it 'returns :not_found when mapping does not exist' do
      result = service.unlink(source: 'erp', external_id: 'NONEXISTENT')

      expect(result[:success]).to be false
      expect(result[:action]).to eq(:not_found)
      expect(result[:error]).to match(/nu exista/)
    end
  end
end

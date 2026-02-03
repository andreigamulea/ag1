# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Variants::BulkLockingService do
  let(:product) { create(:product) }

  # Helper: creează variante cu digest unic pt a evita idx_unique_active_default_variant
  def create_variant_with_digest(product:, **attrs)
    v = create(:variant, product: product, **attrs)
    v.update_column(:options_digest, Digest::SHA256.hexdigest("bulk-#{v.id}-#{v.sku}"))
    v
  end

  describe '.with_locked_variants' do
    it 'yields locked variants sorted by id', :postgres_only do
      skip_unless_supports_for_update!

      v2 = create_variant_with_digest(product: product, sku: 'BLK-V2', stock: 5)
      v1 = create_variant_with_digest(product: product, sku: 'BLK-V1', stock: 10)

      result = nil
      described_class.with_locked_variants([v2.id, v1.id]) do |locked|
        result = locked.map(&:id)
      end

      # Sorted by id ascending
      expect(result).to eq([v1.id, v2.id].sort)
    end

    it 'yields empty array for empty ids' do
      result = nil
      described_class.with_locked_variants([]) do |locked|
        result = locked
      end

      expect(result).to eq([])
    end

    it 'sanitized: true raises ArgumentError on invalid input' do
      expect {
        described_class.with_locked_variants(["abc"], sanitized: true) { |_| }
      }.to raise_error(ArgumentError, /requires Array of positive Integers/)

      expect {
        described_class.with_locked_variants([0], sanitized: true) { |_| }
      }.to raise_error(ArgumentError, /requires Array of positive Integers/)

      expect {
        described_class.with_locked_variants([-1], sanitized: true) { |_| }
      }.to raise_error(ArgumentError, /requires Array of positive Integers/)
    end

    it 'locks with FOR UPDATE + ORDER BY id (SQL verification)', :postgres_only do
      skip_unless_supports_for_update!

      v1 = create_variant_with_digest(product: product, sku: 'SQL-V1')
      v2 = create_variant_with_digest(product: product, sku: 'SQL-V2')

      lock_queries = []
      callback = capture_lock_queries("variants", into: lock_queries)

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.with_locked_variants([v2.id, v1.id]) { |_| }
      end

      expect_lock_order!(lock_queries, label: "BulkLockingService variants lock")
    end
  end

  describe '.bulk_update_stock' do
    it 'updates stock for multiple variants' do
      v1 = create_variant_with_digest(product: product, sku: 'STK-V1', stock: 10)
      v2 = create_variant_with_digest(product: product, sku: 'STK-V2', stock: 20)

      result = described_class.bulk_update_stock({ v1.id => 15, v2.id => 25 })

      expect(result[:success]).to be true
      expect(result[:updated].size).to eq(2)
      expect(v1.reload.stock).to eq(15)
      expect(v2.reload.stock).to eq(25)
    end

    it 'returns empty updated when empty hash' do
      result = described_class.bulk_update_stock({})
      expect(result).to eq({ success: true, updated: [] })
    end

    it 'fails fast on invalid stock value ("abc")' do
      v = create_variant_with_digest(product: product, sku: 'STK-BAD')

      expect {
        described_class.bulk_update_stock({ v.id => "abc" })
      }.to raise_error(ArgumentError)
    end

    it 'fails fast on negative stock (DB constraint)', :postgres_only do
      skip_unless_supports_for_update!

      v = create_variant_with_digest(product: product, sku: 'STK-NEG', stock: 10)

      expect {
        described_class.bulk_update_stock({ v.id => -1 })
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'fails fast on nil key' do
      expect {
        described_class.bulk_update_stock({ nil => 10 })
      }.to raise_error(ArgumentError, /nil\/blank not allowed/)
    end

    it 'accepts string keys (sanitized via IdSanitizer)' do
      v = create_variant_with_digest(product: product, sku: 'STK-STR', stock: 5)

      result = described_class.bulk_update_stock({ v.id.to_s => 20 })

      expect(result[:success]).to be true
      expect(v.reload.stock).to eq(20)
    end
  end

  describe '.bulk_update_price' do
    it 'updates price for multiple variants' do
      v1 = create_variant_with_digest(product: product, sku: 'PRC-V1', price: 10.0)
      v2 = create_variant_with_digest(product: product, sku: 'PRC-V2', price: 20.0)

      result = described_class.bulk_update_price({ v1.id => 15.50, v2.id => 25.99 })

      expect(result[:success]).to be true
      expect(result[:updated].size).to eq(2)
      expect(v1.reload.price).to eq(BigDecimal('15.50'))
      expect(v2.reload.price).to eq(BigDecimal('25.99'))
    end

    it 'returns empty updated when empty hash' do
      result = described_class.bulk_update_price({})
      expect(result).to eq({ success: true, updated: [] })
    end

    it 'fails fast on invalid price value ("abc")' do
      v = create_variant_with_digest(product: product, sku: 'PRC-BAD')

      expect {
        described_class.bulk_update_price({ v.id => "abc" })
      }.to raise_error(ArgumentError)
    end

    it 'fails fast on nil key' do
      expect {
        described_class.bulk_update_price({ nil => 10.0 })
      }.to raise_error(ArgumentError, /nil\/blank not allowed/)
    end

    it 'fails fast on negative price (DB constraint)', :postgres_only do
      skip_unless_supports_for_update!

      v = create_variant_with_digest(product: product, sku: 'PRC-NEG', price: 10.0)

      expect {
        described_class.bulk_update_price({ v.id => -1 })
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'accepts string keys (sanitized via IdSanitizer)' do
      v = create_variant_with_digest(product: product, sku: 'PRC-STR', price: 5.0)

      result = described_class.bulk_update_price({ v.id.to_s => 15.99 })

      expect(result[:success]).to be true
      expect(v.reload.price).to eq(BigDecimal('15.99'))
    end
  end
end

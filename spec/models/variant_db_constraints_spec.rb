# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Variant DB Constraints', type: :model do
  # ═══════════════════════════════════════════════════════════════════════════
  # PARTIAL INDEX: idx_unique_active_default_variant
  # O singură variantă activă fără opțiuni (default) per produs
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'idx_unique_active_default_variant' do
    it 'prevents two active default variants for same product' do
      product = create(:product)
      create(:variant, product: product, status: :active, options_digest: nil)

      expect {
        # Bypass Rails validations, go direct to DB
        Variant.create!(
          product: product,
          sku: 'SECOND-DEFAULT',
          price: 10,
          stock: 5,
          status: :active,
          options_digest: nil
        )
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_unique_active_default_variant/)
    end

    it 'allows active + inactive default variants for same product' do
      product = create(:product)
      create(:variant, product: product, status: :active, options_digest: nil)

      # Inactive default should be allowed (partial index only on status=0)
      expect {
        create(:variant, product: product, status: :inactive, options_digest: nil)
      }.not_to raise_error
    end

    it 'allows new active default when existing default is inactive' do
      product = create(:product)
      create(:variant, product: product, status: :inactive, options_digest: nil)

      expect {
        create(:variant, product: product, status: :active, options_digest: nil)
      }.not_to raise_error
    end

    it 'allows active defaults on different products' do
      product1 = create(:product)
      product2 = create(:product)

      create(:variant, product: product1, status: :active, options_digest: nil)

      expect {
        create(:variant, product: product2, status: :active, options_digest: nil)
      }.not_to raise_error
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PARTIAL INDEX: idx_unique_active_options_per_product
  # O singură variantă activă per combinație de opțiuni per produs
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'idx_unique_active_options_per_product' do
    let(:digest) { 'test-digest-123' }

    # Helper: creează variantă și setează digest direct (bypass callback)
    def create_variant_with_digest(product:, status:, digest_value:)
      v = create(:variant, product: product, status: status)
      v.update_column(:options_digest, digest_value)
      v
    end

    it 'prevents two active variants with same options_digest for same product' do
      product = create(:product)
      create_variant_with_digest(product: product, status: :active, digest_value: digest)

      expect {
        v2 = create(:variant, product: product, status: :active)
        v2.update_column(:options_digest, digest)
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_unique_active_options_per_product/)
    end

    it 'allows active + inactive variants with same options_digest' do
      product = create(:product)
      create_variant_with_digest(product: product, status: :active, digest_value: digest)

      expect {
        v2 = create(:variant, product: product, status: :inactive)
        v2.update_column(:options_digest, digest)
      }.not_to raise_error
    end

    it 'allows two inactive variants with same options_digest' do
      product = create(:product)
      create_variant_with_digest(product: product, status: :inactive, digest_value: digest)

      expect {
        v2 = create(:variant, product: product, status: :inactive)
        v2.update_column(:options_digest, digest)
      }.not_to raise_error
    end

    it 'allows same options_digest on different products (both active)' do
      product1 = create(:product)
      product2 = create(:product)

      create_variant_with_digest(product: product1, status: :active, digest_value: digest)

      expect {
        v2 = create(:variant, product: product2, status: :active)
        v2.update_column(:options_digest, digest)
      }.not_to raise_error
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PARTIAL INDEX: idx_unique_external_sku
  # external_sku unic global (doar când e setat)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'idx_unique_external_sku' do
    it 'prevents duplicate external_sku values' do
      create(:variant, external_sku: 'EXT-001')

      expect {
        create(:variant, external_sku: 'EXT-001')
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_unique_external_sku/)
    end

    it 'allows multiple variants with nil external_sku' do
      create(:variant, external_sku: nil)

      expect {
        create(:variant, external_sku: nil)
      }.not_to raise_error
    end

    it 'allows one with external_sku and one without' do
      create(:variant, external_sku: 'EXT-001')

      expect {
        create(:variant, external_sku: nil)
      }.not_to raise_error
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CHECK CONSTRAINTS (Postgres-only)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'CHECK constraints', :postgres_only do
    before do
      skip 'Postgres-only test' unless ActiveRecord::Base.connection.adapter_name =~ /postgres/i
    end

    describe 'chk_variants_price_positive' do
      it 'rejects negative price at DB level' do
        variant = create(:variant, price: 100)

        expect {
          # Bypass Rails validations with update_column
          variant.update_column(:price, -1)
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_variants_price_positive/)
      end

      it 'rejects NULL price at DB level' do
        variant = create(:variant, price: 100)

        expect {
          variant.update_column(:price, nil)
        }.to raise_error(ActiveRecord::NotNullViolation)
      end

      it 'allows zero price' do
        variant = create(:variant, price: 100)

        expect {
          variant.update_column(:price, 0)
        }.not_to raise_error
      end
    end

    describe 'chk_variants_stock_positive' do
      it 'rejects negative stock at DB level' do
        variant = create(:variant, stock: 10)

        expect {
          variant.update_column(:stock, -1)
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_variants_stock_positive/)
      end

      it 'rejects NULL stock at DB level' do
        variant = create(:variant, stock: 10)

        expect {
          variant.update_column(:stock, nil)
        }.to raise_error(ActiveRecord::NotNullViolation)
      end

      it 'allows zero stock' do
        variant = create(:variant, stock: 10)

        expect {
          variant.update_column(:stock, 0)
        }.not_to raise_error
      end
    end

    describe 'chk_variants_status_enum' do
      it 'rejects invalid status values at DB level' do
        variant = create(:variant, status: :active)

        expect {
          variant.update_column(:status, 7)
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_variants_status_enum/)
      end

      it 'allows status 0 (active)' do
        variant = create(:variant, status: :inactive)

        expect {
          variant.update_column(:status, 0)
        }.not_to raise_error
      end

      it 'allows status 1 (inactive)' do
        variant = create(:variant, status: :active)

        expect {
          variant.update_column(:status, 1)
        }.not_to raise_error
      end
    end

    describe 'chk_vei_source_format' do
      it 'rejects invalid source format at DB level' do
        vei = create(:variant_external_id, source: 'erp')

        expect {
          vei.update_column(:source, 'Bad Source')
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_vei_source_format/)
      end

      it 'rejects source with uppercase at DB level' do
        vei = create(:variant_external_id, source: 'erp')

        expect {
          vei.update_column(:source, 'ERP')
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_vei_source_format/)
      end

      it 'allows valid source format (lowercase with underscores)' do
        vei = create(:variant_external_id, source: 'erp')

        expect {
          vei.update_column(:source, 'emag_ro')
        }.not_to raise_error
      end
    end

    describe 'chk_vei_source_account_format' do
      it 'rejects invalid source_account format at DB level' do
        vei = create(:variant_external_id, source: 'erp')

        expect {
          vei.update_column(:source_account, 'RO Store 1')
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_vei_source_account_format/)
      end

      it 'rejects source_account with uppercase at DB level' do
        vei = create(:variant_external_id, source: 'erp')

        expect {
          vei.update_column(:source_account, 'Default')
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_vei_source_account_format/)
      end

      it 'allows valid source_account format (lowercase with underscores)' do
        vei = create(:variant_external_id, source: 'erp', source_account: 'default')

        expect {
          vei.update_column(:source_account, 'emag_ro_1')
        }.not_to raise_error
      end
    end

    describe 'chk_vei_external_id_not_empty' do
      it 'rejects empty external_id at DB level' do
        vei = create(:variant_external_id, external_id: '12345')

        expect {
          vei.update_column(:external_id, '')
        }.to raise_error(ActiveRecord::StatementInvalid, /chk_vei_external_id_not_empty/)
      end

      it 'rejects whitespace-only external_id at DB level' do
        vei = create(:variant_external_id, external_id: '12345')

        expect {
          vei.update_column(:external_id, '   ')
        }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it 'allows valid external_id' do
        vei = create(:variant_external_id, external_id: '12345')

        expect {
          vei.update_column(:external_id, 'NEW-ID-999')
        }.not_to raise_error
      end
    end
  end
end

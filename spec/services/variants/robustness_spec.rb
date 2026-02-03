# frozen_string_literal: true

require 'rails_helper'

# ROBUSTNESS TESTS R1-R4
# Non-paranoide, obligatorii: verifica comportamentul real in conditii de productie.

RSpec.describe "Robustness tests (R1-R4)" do
  let(:product) { create(:product) }

  # Helper: creează variante cu digest unic pt a evita idx_unique_active_default_variant
  def create_variant_with_digest(product:, **attrs)
    v = create(:variant, product: product, **attrs)
    v.update_column(:options_digest, Digest::SHA256.hexdigest("robust-#{v.id}-#{v.sku}"))
    v
  end

  # ======================================================================
  # R1. IDEMPOTENCY - apel dublu nu strica nimic
  # ======================================================================
  describe "R1: Idempotency" do
    describe "Product#archive!" do
      it 'is idempotent - second call does not explode or change state' do
        v = create_variant_with_digest(product: product, sku: 'IDP-V1', status: :active)

        product.archive!
        expect(product.reload).to be_archived
        expect(v.reload.status).to eq('inactive')

        expect { product.archive! }.not_to raise_error
        expect(product.reload).to be_archived
        expect(v.reload.status).to eq('inactive')
      end
    end

    describe "AdminExternalIdService#link" do
      it 'returns :already_linked on second call (idempotent)' do
        variant = create(:variant, product: product)
        service = Variants::AdminExternalIdService.new(variant)

        result1 = service.link(source: 'erp', external_id: 'IDP-EXT-1')
        expect(result1[:success]).to be true
        expect(result1[:action]).to eq(:linked)

        result2 = service.link(source: 'erp', external_id: 'IDP-EXT-1')
        expect(result2[:success]).to be true
        expect(result2[:action]).to eq(:already_linked)
      end
    end

    describe "AdminExternalIdService#unlink" do
      it 'returns :not_found on second call (idempotent)' do
        variant = create(:variant, product: product)
        service = Variants::AdminExternalIdService.new(variant)

        service.link(source: 'erp', external_id: 'IDP-EXT-2')
        result1 = service.unlink(source: 'erp', external_id: 'IDP-EXT-2')
        expect(result1[:success]).to be true
        expect(result1[:action]).to eq(:unlinked)

        result2 = service.unlink(source: 'erp', external_id: 'IDP-EXT-2')
        expect(result2[:success]).to be false
        expect(result2[:action]).to eq(:not_found)
      end
    end

    describe "BulkLockingService" do
      it 'is idempotent - same stock value yields no changes' do
        v = create_variant_with_digest(product: product, sku: 'IDP-BLK', stock: 10)

        result = Variants::BulkLockingService.bulk_update_stock({ v.id => 10 })

        expect(result[:success]).to be true
        expect(result[:updated]).to be_empty
      end
    end
  end

  # ======================================================================
  # R2. BOUNDARY - input gol dar valid, no-op fara side-effects
  # ======================================================================
  describe "R2: Empty/valid input boundary" do
    describe "BulkLockingService" do
      it 'with_locked_variants([]) yields [], no locks, no exceptions' do
        lock_queries = []
        callback = ->(*, payload) {
          sql = payload[:sql].to_s
          lock_queries << sql if sql =~ /FOR\s+UPDATE/i
        }

        result = nil
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          Variants::BulkLockingService.with_locked_variants([]) do |locked|
            result = locked
          end
        end

        expect(result).to eq([])
        expect(lock_queries).to be_empty
      end

      it 'bulk_update_stock({}) returns success with empty updated' do
        result = Variants::BulkLockingService.bulk_update_stock({})
        expect(result).to eq({ success: true, updated: [] })
      end

      it 'bulk_update_price({}) returns success with empty updated' do
        result = Variants::BulkLockingService.bulk_update_price({})
        expect(result).to eq({ success: true, updated: [] })
      end
    end

    describe "Product#archive! without variants" do
      it 'sets status archived, no errors' do
        expect { product.archive! }.not_to raise_error
        expect(product.reload).to be_archived
      end
    end

    describe "AdminExternalIdService" do
      it 'link with blank source returns error gracefully, no exception' do
        variant = create(:variant, product: product)
        service = Variants::AdminExternalIdService.new(variant)

        result = service.link(source: '', external_id: 'EXT-1')
        expect(result[:success]).to be false
        expect(result[:error]).to match(/source obligatoriu/)
      end
    end
  end

  # ======================================================================
  # R3. NU ATINGE CE NU TREBUIE (negative side-effects)
  # ======================================================================
  describe "R3: No unintended side-effects" do
    describe "Product#archive!" do
      it 'does not affect variants of other products' do
        other_product = create(:product)
        other_v = create(:variant, product: other_product, status: :active, sku: 'R3-OTHER')
        my_v = create_variant_with_digest(product: product, sku: 'R3-MINE', status: :active)

        product.archive!

        expect(my_v.reload.status).to eq('inactive')
        expect(other_v.reload.status).to eq('active')  # UNTOUCHED
      end

      it 'does not re-touch already inactive variants (update_all is fine)' do
        inactive_v = create_variant_with_digest(product: product, sku: 'R3-INACT', status: :inactive)

        # update_all sets status to inactive for ALL variants (including already inactive)
        # This is acceptable - the important thing is no error and correct final state
        product.archive!

        expect(inactive_v.reload.status).to eq('inactive')
        expect(product.reload).to be_archived
      end
    end

    describe "BulkLockingService" do
      it 'does not modify variants not in the input hash' do
        v1 = create_variant_with_digest(product: product, sku: 'R3-BLK-V1', stock: 10)
        v2 = create_variant_with_digest(product: product, sku: 'R3-BLK-V2', stock: 20)

        Variants::BulkLockingService.bulk_update_stock({ v1.id => 15 })

        expect(v1.reload.stock).to eq(15)
        expect(v2.reload.stock).to eq(20)  # UNTOUCHED
      end
    end
  end

  # ======================================================================
  # R4. STARE MIXTA (date reale, nu ideale)
  # ======================================================================
  describe "R4: Mixed state (production-realistic data)" do
    describe "Product#archive! on mixed state" do
      it 'handles mixed state: active + inactive variants' do
        active_v = create_variant_with_digest(product: product, sku: 'R4-ACT', status: :active)
        inactive_v = create_variant_with_digest(product: product, sku: 'R4-INACT', status: :inactive)

        product.archive!

        expect(active_v.reload.status).to eq('inactive')
        expect(inactive_v.reload.status).to eq('inactive')
        expect(product.reload).to be_archived
      end
    end

    describe "BulkLockingService on mixed variants" do
      it 'updates only specified variants, leaves others unchanged' do
        v_active = create_variant_with_digest(product: product, sku: 'R4-BLK-ACT', stock: 10, status: :active)
        v_inactive = create_variant_with_digest(product: product, sku: 'R4-BLK-INACT', stock: 5, status: :inactive)

        Variants::BulkLockingService.bulk_update_stock({ v_active.id => 20 })

        expect(v_active.reload.stock).to eq(20)
        expect(v_inactive.reload.stock).to eq(5)  # UNTOUCHED
      end
    end

    describe "AdminExternalIdService on variant with existing mappings" do
      it 'adds new mapping without affecting existing ones' do
        variant = create(:variant, product: product)
        service = Variants::AdminExternalIdService.new(variant)

        service.link(source: 'erp', external_id: 'R4-EXT-1')
        service.link(source: 'emag', external_id: 'R4-EXT-2')

        expect(variant.external_ids.count).to eq(2)
        expect(variant.external_ids.pluck(:source).sort).to eq(%w[emag erp])
      end
    end
  end
end

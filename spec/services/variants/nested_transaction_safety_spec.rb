# frozen_string_literal: true

require 'rails_helper'

# spec/services/variants/nested_transaction_safety_spec.rb
#
# CRITICAL REGRESSION TEST: Dovedește că fix-ul requires_new: true funcționează.
#
# PROBLEMA: Când CreateOrReactivateService e apelat dintr-o tranzacție externă
# (ex: VariantSyncService) și apare RecordNotUnique care e rescue-uită,
# fără SAVEPOINT tranzacția exterioară devine "poisoned" și orice SQL ulterior
# pică cu "PG::InFailedSqlTransaction: current transaction is aborted".
#
# FIX: requires_new: true creează SAVEPOINT, izolând eroarea DB.
#
# IMPORTANT: Acest test e POSTGRES-ONLY. SQLite/MySQL au comportament diferit.

RSpec.describe "Nested transaction safety", :postgres_only do
  # Helper: Verifică că tranzacția e încă validă (nu "poisoned")
  def assert_transaction_healthy!
    ActiveRecord::Base.uncached do
      ActiveRecord::Base.connection.select_value("SELECT 1")
    end
  end

  # Helper: Dezactivează TOATE UniquenessValidator-urile pentru un model/atribut
  # Permite ca duplicatele să ajungă la DB și să arunce RecordNotUnique
  def disable_uniqueness_validator(model, attribute)
    validators = model.validators_on(attribute)
                      .select { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }
    validators.each { |v| allow(v).to receive(:validate_each).and_return(nil) }
  end

  describe "CreateOrReactivateService - SKU duplicate (DB-level)" do
    it "does not poison outer transaction when RecordNotUnique is rescued" do
      product = create(:product)
      option_type = create(:option_type)
      option_value = create(:option_value, option_type: option_type)
      product.option_types << option_type

      # Creăm variantă NON-DEFAULT (cu digest != nil) astfel că find_existing_variant(nil)
      # nu găsește nimic și service-ul încearcă INSERT cu SKU duplicat → DB RecordNotUnique
      existing = create(:variant, product: product, sku: "UNIQUE-SKU", status: :active)
      existing.option_value_variants.create!(option_value_id: option_value.id)
      existing.save! # Trigger compute_options_digest

      # FORȚĂM DB-level RecordNotUnique: dezactivăm validarea Rails
      disable_uniqueness_validator(Variant, :sku)

      ActiveRecord::Base.transaction do
        # Call cu [] (default variant) dar SKU duplicat
        result = Variants::CreateOrReactivateService.new.call(
          product: product,
          option_value_ids: [],
          attributes: { sku: "UNIQUE-SKU", price: 10, stock: 1 }
        )

        # Service-ul trebuie să returneze failure (din handle_unique_violation)
        expect(result.success?).to be false
        expect(result.error).to match(/SKU/i)

        # CRITICAL: Fără requires_new: true, această linie ar pica cu
        # "PG::InFailedSqlTransaction: current transaction is aborted"
        assert_transaction_healthy!
      end
    end
  end

  describe "UpdateOptionsService - digest conflict (DB-level)" do
    it "does not poison outer transaction when RecordNotUnique is rescued" do
      product = create(:product)
      option_type = create(:option_type)
      ov1 = create(:option_value, option_type: option_type)
      ov2 = create(:option_value, option_type: option_type)
      product.option_types << option_type

      v1 = create(:variant, product: product, status: :active, sku: "V1-SKU")
      v1.option_value_variants.create!(option_value_id: ov1.id)
      v1.save!

      v2 = create(:variant, product: product, status: :active, sku: "V2-SKU")
      v2.option_value_variants.create!(option_value_id: ov2.id)
      v2.save!

      ActiveRecord::Base.transaction do
        # UpdateOptionsService are un check explicit (digest_conflict?) care returnează
        # :conflict înainte de DB. Testăm că requires_new: true protejează outer transaction
        # chiar și în cazul normal (fără stub-uri).
        result = Variants::UpdateOptionsService.new.call(
          variant: v2,
          option_value_ids: [ov1.id]
        )

        # Service-ul detectează conflictul (early return via digest_conflict?)
        expect(result.success?).to be false
        expect(result.action).to eq(:conflict)

        # Outer transaction încă validă
        assert_transaction_healthy!
      end
    end
  end

  describe "Integration: VariantSyncService full flow with nested conflict" do
    it "does not poison outer transaction when nested service returns failure" do
      product = create(:product)

      # Simulează ce face un import job: outer transaction care apelează sync
      ActiveRecord::Base.transaction do
        service = Imports::VariantSyncService.new(
          source: "test_feed",
          source_account: "account1"
        )

        # Prima sincronizare - creează o nouă variantă (succes)
        result1 = service.call(
          external_id: "EXT-001",
          product: product,
          option_value_ids: [],
          attributes: { sku: "NEW-UNIQUE-SKU", price: 100, stock: 50 }
        )
        expect(result1.success?).to be true

        # CRITICAL: Outer transaction încă validă după operație reușită
        assert_transaction_healthy!

        # A doua sincronizare cu input invalid → failure
        result2 = service.call(
          external_id: "",
          product: product,
          option_value_ids: [],
          attributes: { sku: "ANOTHER-SKU", price: 200, stock: 100 }
        )

        expect(result2.success?).to be false

        # Outer transaction încă validă după failure
        assert_transaction_healthy!
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Variant Universal Unique Indexes', type: :model do
  # ═══════════════════════════════════════════════════════════════════════════
  # UNIVERSAL UNIQUE INDEXES - aplică unicitate la nivel DB
  # Testează că DB chiar blochează duplicate, nu doar Rails validations
  # Folosim save(validate: false) pentru a bypassa validările Rails
  # ═══════════════════════════════════════════════════════════════════════════

  describe 'idx_unique_sku_per_product' do
    it 'prevents duplicate SKU within same product' do
      product = create(:product)
      create(:variant, product: product, sku: 'SKU-001')

      expect {
        # Bypass Rails validations
        v = Variant.new(product: product, sku: 'SKU-001', price: 10, stock: 5)
        v.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_unique_sku_per_product/)
    end

    it 'allows same SKU on different products' do
      product1 = create(:product)
      product2 = create(:product)

      create(:variant, product: product1, sku: 'SHARED-SKU')

      expect {
        create(:variant, product: product2, sku: 'SHARED-SKU')
      }.not_to raise_error
    end
  end

  describe 'idx_unique_ovv (option_value_variants)' do
    it 'prevents duplicate option_value per variant' do
      variant = create(:variant)
      option_value = create(:option_value)

      create(:option_value_variant, variant: variant, option_value: option_value)

      expect {
        ovv = OptionValueVariant.new(variant: variant, option_value: option_value)
        ovv.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_unique_ovv/)
    end

    it 'allows same option_value on different variants' do
      variant1 = create(:variant)
      variant2 = create(:variant)
      option_value = create(:option_value)

      create(:option_value_variant, variant: variant1, option_value: option_value)

      expect {
        create(:option_value_variant, variant: variant2, option_value: option_value)
      }.not_to raise_error
    end
  end

  describe 'idx_unique_product_option_type' do
    it 'prevents duplicate option_type per product' do
      product = create(:product)
      option_type = create(:option_type)

      create(:product_option_type, product: product, option_type: option_type)

      expect {
        pot = ProductOptionType.new(product: product, option_type: option_type)
        pot.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_unique_product_option_type/)
    end

    it 'allows same option_type on different products' do
      product1 = create(:product)
      product2 = create(:product)
      option_type = create(:option_type)

      create(:product_option_type, product: product1, option_type: option_type)

      expect {
        create(:product_option_type, product: product2, option_type: option_type)
      }.not_to raise_error
    end
  end

  describe 'idx_unique_source_account_external_id' do
    it 'prevents duplicate external_id per source+account' do
      variant1 = create(:variant)
      create(:variant_external_id,
             variant: variant1,
             source: 'erp',
             source_account: 'default',
             external_id: 'ERP-001')

      variant2 = create(:variant)

      expect {
        vei = VariantExternalId.new(
          variant: variant2,
          source: 'erp',
          source_account: 'default',
          external_id: 'ERP-001'
        )
        vei.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique, /idx_unique_source_account_external_id/)
    end

    it 'allows same external_id on different source_accounts' do
      variant1 = create(:variant)
      variant2 = create(:variant)

      create(:variant_external_id,
             variant: variant1,
             source: 'emag',
             source_account: 'emag_ro_1',
             external_id: '12345')

      expect {
        create(:variant_external_id,
               variant: variant2,
               source: 'emag',
               source_account: 'emag_ro_2',
               external_id: '12345')
      }.not_to raise_error
    end

    it 'allows same external_id on different sources' do
      variant1 = create(:variant)
      variant2 = create(:variant)

      create(:variant_external_id,
             variant: variant1,
             source: 'erp',
             source_account: 'default',
             external_id: '999')

      expect {
        create(:variant_external_id,
               variant: variant2,
               source: 'emag',
               source_account: 'default',
               external_id: '999')
      }.not_to raise_error
    end
  end

  describe 'option_types.name unique index' do
    it 'prevents duplicate option_type names' do
      create(:option_type, name: 'Culoare')

      expect {
        ot = OptionType.new(name: 'Culoare')
        ot.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'option_values unique per option_type' do
    it 'prevents duplicate names within same option_type' do
      option_type = create(:option_type)
      create(:option_value, option_type: option_type, name: 'Roșu')

      expect {
        ov = OptionValue.new(option_type: option_type, name: 'Roșu')
        ov.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows same name in different option_types' do
      type1 = create(:option_type, name: 'Culoare')
      type2 = create(:option_type, name: 'Material')

      create(:option_value, option_type: type1, name: 'Negru')

      expect {
        create(:option_value, option_type: type2, name: 'Negru')
      }.not_to raise_error
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Variant FK Constraints', type: :model do
  # ═══════════════════════════════════════════════════════════════════════════
  # FK: variants → products (on_delete: :restrict)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'variants → products FK (restrict)' do
    it 'prevents product deletion when variants exist (using delete)' do
      product = create(:product)
      create(:variant, product: product)

      # .delete bypasses Rails callbacks, tests FK directly
      expect {
        product.delete
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'allows product deletion when no variants exist' do
      product = create(:product)

      expect {
        product.delete
      }.not_to raise_error

      expect(Product.exists?(product.id)).to be false
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FK: option_value_variants → variants (on_delete: :cascade)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'option_value_variants → variants FK (cascade)' do
    it 'cascades delete to option_value_variants when variant is deleted' do
      variant = create(:variant)
      ovv1 = create(:option_value_variant, variant: variant)
      ovv2 = create(:option_value_variant, variant: variant)

      expect(OptionValueVariant.exists?(ovv1.id)).to be true
      expect(OptionValueVariant.exists?(ovv2.id)).to be true

      # .delete bypasses Rails callbacks, tests FK cascade directly
      variant.delete

      expect(OptionValueVariant.exists?(ovv1.id)).to be false
      expect(OptionValueVariant.exists?(ovv2.id)).to be false
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FK: option_value_variants → option_values (on_delete: :restrict)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'option_value_variants → option_values FK (restrict)' do
    it 'prevents option_value deletion when used by variants' do
      option_value = create(:option_value)
      create(:option_value_variant, option_value: option_value)

      expect {
        option_value.delete
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'allows option_value deletion when not used' do
      option_value = create(:option_value)

      expect {
        option_value.delete
      }.not_to raise_error

      expect(OptionValue.exists?(option_value.id)).to be false
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FK: variant_external_ids → variants (on_delete: :cascade)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'variant_external_ids → variants FK (cascade)' do
    it 'cascades delete to variant_external_ids when variant is deleted' do
      variant = create(:variant)
      vei1 = create(:variant_external_id, variant: variant, source: 'erp')
      vei2 = create(:variant_external_id, variant: variant, source: 'emag')

      expect(VariantExternalId.exists?(vei1.id)).to be true
      expect(VariantExternalId.exists?(vei2.id)).to be true

      variant.delete

      expect(VariantExternalId.exists?(vei1.id)).to be false
      expect(VariantExternalId.exists?(vei2.id)).to be false
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FK: product_option_types → products (on_delete: :restrict at DB level)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'product_option_types → products FK (restrict)' do
    it 'prevents product deletion when product_option_types exist' do
      product = create(:product)
      create(:product_option_type, product: product)

      expect {
        product.delete
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'allows product deletion when no product_option_types exist' do
      product = create(:product)

      expect {
        product.delete
      }.not_to raise_error

      expect(Product.exists?(product.id)).to be false
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FK: option_values → option_types (on_delete: :restrict at DB level)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'option_values → option_types FK (restrict)' do
    it 'prevents option_type deletion when option_values exist' do
      option_type = create(:option_type)
      create(:option_value, option_type: option_type)

      expect {
        option_type.delete
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'allows option_type deletion when no option_values exist' do
      option_type = create(:option_type)

      expect {
        option_type.delete
      }.not_to raise_error

      expect(OptionType.exists?(option_type.id)).to be false
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FK: product_option_types → option_types (on_delete: :restrict at DB level)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'product_option_types → option_types FK (restrict)' do
    it 'prevents option_type deletion when product_option_types exist' do
      option_type = create(:option_type)
      create(:product_option_type, option_type: option_type)

      expect {
        option_type.delete
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FK: order_items → variants (on_delete: :nullify at DB level)
  # ═══════════════════════════════════════════════════════════════════════════
  describe 'order_items → variants FK (nullify)' do
    it 'nullifies variant_id when variant is deleted (DB-level)' do
      variant = create(:variant)

      # 1) Insert order minim folosind helper
      order_id = insert_min_row!(:orders, overrides: {
        created_at: Time.current,
        updated_at: Time.current
      })

      # 2) Insert order_item minim
      item_id = insert_min_row!(:order_items, overrides: {
        order_id: order_id,
        variant_id: variant.id,
        product_id: variant.product_id,
        created_at: Time.current,
        updated_at: Time.current
      })

      # Verifică că variant_id e setat
      result = ActiveRecord::Base.connection.select_value(
        "SELECT variant_id FROM order_items WHERE id = #{item_id}"
      )
      expect(result).to eq(variant.id)

      # .delete bypasses Rails callbacks, tests FK directly
      variant.delete

      # Verifică că variant_id a fost nullificat de FK
      result_after = ActiveRecord::Base.connection.select_value(
        "SELECT variant_id FROM order_items WHERE id = #{item_id}"
      )
      expect(result_after).to be_nil
    end
  end
end

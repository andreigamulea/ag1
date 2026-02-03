# frozen_string_literal: true

require 'rails_helper'

# spec/services/lock_order_verification_spec.rb
#
# GOLD STANDARD: Verifică SQL-ul EXECUTAT efectiv în runtime.
# Garantează că serviciile respectă lock order: O → I → V* (ORDER BY id).
# Aceste teste sunt postgres-only deoarece SQLite nu suportă FOR UPDATE.

RSpec.describe "Lock order verification", :postgres_only do
  describe "RestockService lock order: O -> I -> V* (ORDER BY id)" do
    it "locks order, items, then variants in id order" do
      skip_unless_supports_for_update!
      assert_read_committed!

      product = create(:product)
      order = create(:order, status: 'cancelled')
      v1 = create(:variant, product: product, sku: 'LO-V1', stock: 0)
      v1.update_column(:options_digest, Digest::SHA256.hexdigest('lo-v1'))
      v2 = create(:variant, product: product, sku: 'LO-V2', stock: 0)
      v2.update_column(:options_digest, Digest::SHA256.hexdigest('lo-v2'))
      v3 = create(:variant, product: product, sku: 'LO-V3', stock: 0)
      v3.update_column(:options_digest, Digest::SHA256.hexdigest('lo-v3'))

      # Creăm items (ordinea de creare nu contează, service-ul sortează)
      create(:order_item, order: order, product: product, variant_id: v3.id, quantity: 1, price: 30.0)
      create(:order_item, order: order, product: product, variant_id: v1.id, quantity: 2, price: 10.0)
      create(:order_item, order: order, product: product, variant_id: v2.id, quantity: 1, price: 20.0)

      lock_sequence = []
      variants_lock_queries = []

      orders_lock = select_for_update_regex("orders")
      items_lock  = select_for_update_regex("order_items")
      vars_lock   = select_for_update_regex("variants")

      callback = ->(*, payload) {
        sql = payload[:sql].to_s
        return if sql.empty?
        return if sql =~ LockOrderHelper::SCHEMA_QUERY

        case sql
        when orders_lock then lock_sequence << :order
        when items_lock  then lock_sequence << :items
        when vars_lock
          lock_sequence << :variants
          variants_lock_queries << sql
        end
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        Orders::RestockService.new.call(order: order)
      end

      # Verificăm ORDINE RELATIVĂ: O înainte de I, I înainte de V
      order_idx = lock_sequence.index(:order)
      items_idx = lock_sequence.index(:items)
      variants_idx = lock_sequence.index(:variants)

      expect(order_idx).not_to be_nil, "Expected ORDER lock, got sequence: #{lock_sequence}"
      expect(items_idx).not_to be_nil, "Expected ORDER_ITEMS lock, got sequence: #{lock_sequence}"
      expect(variants_idx).not_to be_nil, "Expected VARIANTS lock, got sequence: #{lock_sequence}"

      expect(order_idx).to be < items_idx,
        "ORDER must be locked before ITEMS. Sequence: #{lock_sequence}"
      expect(items_idx).to be < variants_idx,
        "ITEMS must be locked before VARIANTS. Sequence: #{lock_sequence}"

      # Verificăm că ACELAȘI query are FOR UPDATE + ORDER BY id
      expect_lock_order!(variants_lock_queries, label: "variants lock")

      # Verificăm că stocul a fost restockat
      expect(v1.reload.stock).to eq(2)
      expect(v2.reload.stock).to eq(1)
      expect(v3.reload.stock).to eq(1)
    end
  end

  describe "FinalizeService lock order: O -> I -> V (individual locks)" do
    it "locks order and items before processing variants" do
      skip_unless_supports_for_update!
      assert_read_committed!

      product = create(:product)
      variant = create(:variant, product: product, sku: 'FIN-V1', price: 100.0, stock: 10)
      order = create(:order, status: 'pending')
      create(:order_item, order: order, product: product, variant_id: variant.id, quantity: 2, price: 100.0)

      lock_sequence = []

      orders_lock = select_for_update_regex("orders")
      items_lock  = select_for_update_regex("order_items")
      vars_lock   = select_for_update_regex("variants")

      callback = ->(*, payload) {
        sql = payload[:sql].to_s
        return if sql.empty?
        return if sql =~ LockOrderHelper::SCHEMA_QUERY

        case sql
        when orders_lock then lock_sequence << :order
        when items_lock  then lock_sequence << :items
        when vars_lock   then lock_sequence << :variants
        end
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        Checkout::FinalizeService.new.call(order: order)
      end

      # FinalizeService: O → I, then locks each variant individually
      order_idx = lock_sequence.index(:order)
      items_idx = lock_sequence.index(:items)

      expect(order_idx).not_to be_nil, "Expected ORDER lock, got sequence: #{lock_sequence}"
      expect(items_idx).not_to be_nil, "Expected ORDER_ITEMS lock, got sequence: #{lock_sequence}"
      expect(order_idx).to be < items_idx,
        "ORDER must be locked before ITEMS. Sequence: #{lock_sequence}"

      # Verificăm rezultatul
      expect(variant.reload.stock).to eq(8)
      expect(order.reload.status).to eq('paid')
    end
  end

  describe "UpdateOptionTypesService lock order: P -> V* (ORDER BY id)" do
    it "locks product before variants" do
      skip_unless_supports_for_update!
      assert_read_committed!

      product = create(:product)
      ot1 = create(:option_type)
      ot2 = create(:option_type)
      ov1 = create(:option_value, option_type: ot1)
      product.option_types << ot1
      product.option_types << ot2

      # Creăm variantă cu ov1
      variant = create(:variant, product: product, sku: 'OT-V1')
      variant.option_value_variants.create!(option_value_id: ov1.id)
      variant.save!

      lock_sequence = []

      products_lock = select_for_update_regex("products")
      vars_lock     = select_for_update_regex("variants")

      callback = ->(*, payload) {
        sql = payload[:sql].to_s
        return if sql.empty?
        return if sql =~ LockOrderHelper::SCHEMA_QUERY

        case sql
        when products_lock then lock_sequence << :product
        when vars_lock     then lock_sequence << :variants
        end
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        Products::UpdateOptionTypesService.new.call(
          product: product,
          option_type_ids: [ot2.id]  # Remove ot1 → deactivate variant
        )
      end

      product_idx = lock_sequence.index(:product)
      variants_idx = lock_sequence.index(:variants)

      expect(product_idx).not_to be_nil, "Expected PRODUCT lock, got sequence: #{lock_sequence}"
      expect(variants_idx).not_to be_nil, "Expected VARIANTS lock, got sequence: #{lock_sequence}"
      expect(product_idx).to be < variants_idx,
        "PRODUCT must be locked before VARIANTS. Sequence: #{lock_sequence}"
    end
  end
end

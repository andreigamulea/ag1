require 'rails_helper'

RSpec.describe 'Invoice PDF variant display', type: :model do
  let(:product) { create(:product, name: 'Carte Factura Test', price: 79.99) }
  let(:order) do
    create(:order,
      total: 179.97,
      first_name: 'Ion',
      last_name: 'Popescu',
      email: 'ion@test.com'
    )
  end
  let(:invoice) do
    create(:invoice, order: order, invoice_number: 9001, series: 'AY', emitted_at: Time.current)
  end

  describe 'order items with variant data for invoice' do
    it 'stores variant_options_text that will appear on invoice' do
      item1 = order.order_items.create!(
        product: product,
        product_name: 'Carte Factura Test',
        variant_options_text: 'Material: Bumbac, Culoare: Rosu',
        variant_sku: 'CF-BUM-ROS',
        quantity: 1,
        price: 79.99,
        total_price: 79.99
      )
      item2 = order.order_items.create!(
        product: product,
        product_name: 'Carte Factura Test',
        variant_options_text: 'Material: Digital',
        variant_sku: 'CF-DIG',
        quantity: 2,
        price: 49.99,
        total_price: 99.98
      )

      # Verify both items exist as distinct line items
      items = order.order_items.where.not(product_name: ['Discount', 'Transport'])
      expect(items.count).to eq(2)

      # Verify variant data is persisted
      expect(item1.reload.variant_options_text).to eq('Material: Bumbac, Culoare: Rosu')
      expect(item2.reload.variant_options_text).to eq('Material: Digital')

      # Verify they have different SKUs
      expect(item1.variant_sku).not_to eq(item2.variant_sku)
    end

    it 'stores items without variant data (backward compatible)' do
      item = order.order_items.create!(
        product: product,
        product_name: 'Carte Simpla',
        quantity: 1,
        price: 39.99,
        total_price: 39.99
      )

      expect(item.reload.variant_options_text).to be_nil
      expect(item.variant_sku).to be_nil
    end

    it 'excludes Transport and Discount from product listing' do
      order.order_items.create!(
        product: product,
        product_name: 'Carte Test',
        variant_options_text: 'Format: Fizic',
        quantity: 1,
        price: 79.99,
        total_price: 79.99
      )
      order.order_items.create!(
        product: nil,
        product_name: 'Transport',
        quantity: 1,
        price: 20.0,
        total_price: 20.0
      )
      order.order_items.create!(
        product: nil,
        product_name: 'Discount',
        quantity: 1,
        price: -10.0,
        total_price: -10.0
      )

      product_items = order.order_items.where.not(product_name: ['Discount', 'Transport'])
      expect(product_items.count).to eq(1)
      expect(product_items.first.variant_options_text).to eq('Format: Fizic')

      transport = order.order_items.find_by(product_name: 'Transport')
      expect(transport.total_price).to eq(20.0)

      discount = order.order_items.find_by(product_name: 'Discount')
      expect(discount.total_price).to eq(-10.0)
    end
  end

  describe 'invoice PDF template rendering' do
    it 'renders invoice template with variant items' do
      order.order_items.create!(
        product: product,
        product_name: 'Carte Factura Test',
        variant_options_text: 'Material: Bumbac',
        quantity: 1,
        price: 79.99,
        total_price: 79.99
      )

      # Render the template as string (same as the controller does)
      controller = ApplicationController.new
      html = controller.render_to_string(
        template: 'orders/invoice',
        layout: false,
        formats: [:pdf],
        locals: { order: order, invoice: invoice }
      )

      expect(html).to include('Carte Factura Test')
      expect(html).to include('Material: Bumbac')
      expect(html).to include('79.99 lei')
      expect(html).to include('FACTURA')
      expect(html).to include('9001')
    end

    it 'renders invoice without variant info for simple items' do
      order.order_items.create!(
        product: product,
        product_name: 'Carte Simpla',
        quantity: 1,
        price: 39.99,
        total_price: 39.99
      )

      controller = ApplicationController.new
      html = controller.render_to_string(
        template: 'orders/invoice',
        layout: false,
        formats: [:pdf],
        locals: { order: order, invoice: invoice }
      )

      expect(html).to include('Carte Simpla')
      expect(html).to include('39.99 lei')
      # Should not contain the variant options span
      expect(html).not_to include('font-size: 0.8em; color: #666;')
    end

    it 'renders two variant items as distinct lines' do
      order.order_items.create!(
        product: product,
        product_name: 'Carte Test',
        variant_options_text: 'Format: Fizic',
        quantity: 1,
        price: 79.99,
        total_price: 79.99
      )
      order.order_items.create!(
        product: product,
        product_name: 'Carte Test',
        variant_options_text: 'Format: Digital',
        quantity: 2,
        price: 49.99,
        total_price: 99.98
      )

      controller = ApplicationController.new
      html = controller.render_to_string(
        template: 'orders/invoice',
        layout: false,
        formats: [:pdf],
        locals: { order: order, invoice: invoice }
      )

      expect(html).to include('Format: Fizic')
      expect(html).to include('Format: Digital')
      expect(html).to include('79.99 lei')
      expect(html).to include('99.98 lei')
    end
  end
end

require 'rails_helper'

RSpec.describe 'orders/_order_items.html.erb', type: :view do
  let(:order) { create(:order, total: 179.97) }
  let(:product) { create(:product, name: 'Carte Partial Test') }

  context 'with variant order items' do
    let(:order_items) do
      [
        order.order_items.create!(
          product: product,
          product_name: 'Carte Partial Test',
          variant_options_text: 'Material: Bumbac, Marime: XL',
          variant_sku: 'CPT-BUM-XL',
          quantity: 1,
          price: 79.99,
          total_price: 79.99
        ),
        order.order_items.create!(
          product: product,
          product_name: 'Carte Partial Test',
          variant_options_text: 'Material: Digital',
          variant_sku: 'CPT-DIG',
          quantity: 2,
          price: 49.99,
          total_price: 99.98
        )
      ]
    end

    before do
      render partial: 'orders/order_items',
             locals: { order_items: order_items, order: order }
    end

    it 'shows product name for each item' do
      expect(rendered).to include('Carte Partial Test')
    end

    it 'shows variant options text for each variant item' do
      expect(rendered).to include('Material: Bumbac, Marime: XL')
      expect(rendered).to include('Material: Digital')
    end

    it 'renders variant info in small tags' do
      expect(rendered).to include('<small')
      expect(rendered).to include('color: #666')
    end

    it 'shows correct quantities' do
      expect(rendered).to include('1')  # qty for first item
      expect(rendered).to include('2')  # qty for second item
    end

    it 'shows correct prices' do
      expect(rendered).to include('79,99')
      expect(rendered).to include('49,99')
    end

    it 'shows order total' do
      expect(rendered).to include('Total Ordin')
    end
  end

  context 'with non-variant order items' do
    let(:order_items) do
      [
        order.order_items.create!(
          product: product,
          product_name: 'Carte Simpla',
          variant_options_text: nil,
          quantity: 1,
          price: 39.99,
          total_price: 39.99
        )
      ]
    end

    before do
      render partial: 'orders/order_items',
             locals: { order_items: order_items, order: order }
    end

    it 'shows product name' do
      expect(rendered).to include('Carte Simpla')
    end

    it 'does not show variant info small tag' do
      # Should not have the small tag with variant info
      expect(rendered).not_to include('<small')
    end
  end

  context 'with empty order items' do
    before do
      render partial: 'orders/order_items',
             locals: { order_items: [], order: order }
    end

    it 'shows no products message' do
      expect(rendered).to include('Nu există produse')
    end
  end
end

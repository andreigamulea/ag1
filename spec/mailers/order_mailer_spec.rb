require 'rails_helper'

RSpec.describe OrderMailer, type: :mailer do
  let(:product) { create(:product, name: 'Carte Email Test', price: 79.99) }
  let(:order) { create(:order, email: 'client@test.com', total: 179.97) }

  describe '#admin_new_order' do
    context 'with variant order items' do
      before do
        order.order_items.create!(
          product: product,
          product_name: product.name,
          variant_options_text: 'Material: Bumbac, Culoare: Rosu',
          quantity: 1,
          price: 79.99,
          total_price: 79.99
        )
        order.order_items.create!(
          product: product,
          product_name: product.name,
          variant_options_text: 'Material: Digital',
          quantity: 2,
          price: 49.99,
          total_price: 99.98
        )
      end

      let(:mail) { OrderMailer.admin_new_order(order) }

      it 'renders the subject with order id' do
        expect(mail.subject).to include(order.id.to_s)
      end

      it 'sends to admin emails' do
        expect(mail.to).to include('ayushcellromania@gmail.com')
        expect(mail.to).to include('comenzi@ayus.ro')
      end

      it 'includes variant options text in body for each item' do
        body = mail.body.encoded
        expect(body).to include('Material: Bumbac, Culoare: Rosu')
        expect(body).to include('Material: Digital')
      end

      it 'includes product name for each item' do
        body = mail.body.encoded
        expect(body).to include(product.name)
      end

      it 'shows variant info in parentheses after product name' do
        body = mail.body.encoded
        expect(body).to include('(Material: Bumbac, Culoare: Rosu)')
        expect(body).to include('(Material: Digital)')
      end

      it 'shows quantity for each variant item' do
        body = mail.body.encoded
        expect(body).to include('1 x')
        expect(body).to include('2 x')
      end
    end

    context 'with non-variant order items' do
      before do
        order.order_items.create!(
          product: product,
          product_name: product.name,
          quantity: 1,
          price: 49.99,
          total_price: 49.99
        )
      end

      let(:mail) { OrderMailer.admin_new_order(order) }

      it 'shows product name without empty parentheses' do
        body = mail.body.encoded
        expect(body).to include(product.name)
        expect(body).not_to include("#{product.name} ()")
      end
    end
  end

  describe '#payment_success' do
    context 'with variant order items' do
      before do
        order.order_items.create!(
          product: product,
          product_name: product.name,
          variant_options_text: 'Material: Bumbac',
          quantity: 2,
          price: 79.99,
          total_price: 159.98
        )
      end

      let(:mail) { OrderMailer.payment_success(order) }

      it 'renders the subject with order id' do
        expect(mail.subject).to include(order.id.to_s)
      end

      it 'sends to customer email' do
        expect(mail.to).to include('client@test.com')
      end

      it 'includes variant options text in body' do
        body = mail.body.encoded
        expect(body).to include('Material: Bumbac')
      end

      it 'shows product name' do
        body = mail.body.encoded
        expect(body).to include(product.name)
      end

      it 'shows quantity' do
        body = mail.body.encoded
        expect(body).to include('2 x')
      end
    end

    context 'with non-variant order items' do
      before do
        order.order_items.create!(
          product: product,
          product_name: product.name,
          variant_options_text: nil,
          quantity: 1,
          price: 49.99,
          total_price: 49.99
        )
      end

      let(:mail) { OrderMailer.payment_success(order) }

      it 'shows product name without variant info' do
        body = mail.body.encoded
        expect(body).to include(product.name)
        expect(body).not_to include('()')
      end
    end
  end
end

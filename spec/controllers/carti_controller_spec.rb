require 'rails_helper'

RSpec.describe CartiController, type: :request do
  include Devise::Test::IntegrationHelpers

  # Helper to create a product with the required categories for /carti (carte + fizic)
  def create_carti_product(attrs = {})
    product = create(:product, { status: 'active' }.merge(attrs))
    carte_cat = Category.find_or_create_by!(name: 'carte') { |c| c.slug = 'carte' }
    fizic_cat = Category.find_or_create_by!(name: 'fizic') { |c| c.slug = 'fizic' }
    product.categories << carte_cat unless product.categories.include?(carte_cat)
    product.categories << fizic_cat unless product.categories.include?(fizic_cat)
    product
  end

  # Create a variant-based product: create with price, add variants, then nullify price
  def create_carti_variant_product(attrs = {})
    product = create_carti_product({ price: 0.01 }.merge(attrs.except(:price)))
    product
  end

  def create_variant_with_options(product, option_values, variant_attrs = {})
    variant = create(:variant, { product: product }.merge(variant_attrs))
    option_values.each do |ov|
      create(:option_value_variant, variant: variant, option_value: ov)
    end
    variant.reload
    variant.save! # recompute options_digest
    variant
  end

  def nullify_product_price!(product)
    product.update_column(:price, nil)
    product.reload
  end

  describe 'GET /carti (index)' do
    context 'with a product that has no variants' do
      it 'returns success and shows the product' do
        product = create_carti_product(name: 'Carte Simpla', price: 49.99, stock: 10)

        get carti_index_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Carte Simpla')
        expect(response.body).to include('49,99')
      end
    end

    context 'with a product that has variants' do
      let(:product) { create_carti_variant_product(name: 'Carte Cu Variante') }
      let(:option_type) { create(:option_type, name: "Material-#{SecureRandom.hex(4)}", presentation: 'Material') }

      before do
        product.product_option_types.create!(option_type: option_type, position: 0, primary: true)
        ov_bumbac = create(:option_value, option_type: option_type, name: "Bumbac-#{SecureRandom.hex(4)}", presentation: 'Bumbac')
        ov_digital = create(:option_value, option_type: option_type, name: "Digital-#{SecureRandom.hex(4)}", presentation: 'Digital')

        @variant1 = create_variant_with_options(product, [ov_bumbac],
          sku: "CCV-BUM-#{SecureRandom.hex(4)}", price: 59.99, stock: 10)
        @variant2 = create_variant_with_options(product, [ov_digital],
          sku: "CCV-DIG-#{SecureRandom.hex(4)}", price: 39.99, stock: 5)

        nullify_product_price!(product)
      end

      it 'returns success' do
        get carti_index_path
        expect(response).to have_http_status(:success)
      end

      it 'shows each variant as a separate card' do
        get carti_index_path
        body = response.body
        expect(body).to include('59,99')
        expect(body).to include('39,99')
      end

      it 'includes variant_id in the add-to-cart form' do
        get carti_index_path
        body = response.body
        expect(body).to include("value=\"#{@variant1.id}\"")
        expect(body).to include("value=\"#{@variant2.id}\"")
      end

      it 'includes variant_id in hidden fields for each variant card' do
        get carti_index_path
        body = response.body
        expect(body).to include("name=\"variant_id\" value=\"#{@variant1.id}\"")
        expect(body).to include("name=\"variant_id\" value=\"#{@variant2.id}\"")
      end

      it 'shows variant options text on each card' do
        get carti_index_path
        body = response.body
        expect(body).to include(@variant1.options_text)
        expect(body).to include(@variant2.options_text)
      end
    end

    context 'variant stock display for admin' do
      let(:admin) { create(:user, :admin) }

      it 'shows stock count for admin users' do
        product = create_carti_variant_product(name: 'Carte Stoc Admin')
        option_type = create(:option_type, name: "FormatA-#{SecureRandom.hex(4)}", presentation: 'Format')
        product.product_option_types.create!(option_type: option_type, position: 0, primary: true)
        ov = create(:option_value, option_type: option_type, name: "FizicA-#{SecureRandom.hex(4)}", presentation: 'Fizic')
        create_variant_with_options(product, [ov],
          sku: "CSA-HIGH-#{SecureRandom.hex(4)}", price: 29.99, stock: 20)
        nullify_product_price!(product)

        sign_in admin
        get carti_index_path
        expect(response.body).to include('Stoc: 20')
      end
    end

    context 'variant stock display for regular users' do
      it 'shows Disponibil for in-stock variants' do
        product = create_carti_variant_product(name: 'Carte Disponibil')
        option_type = create(:option_type, name: "TipU-#{SecureRandom.hex(4)}", presentation: 'Tip')
        product.product_option_types.create!(option_type: option_type, position: 0, primary: true)
        ov = create(:option_value, option_type: option_type, name: "SoftU-#{SecureRandom.hex(4)}", presentation: 'Soft')
        create_variant_with_options(product, [ov],
          sku: "CD-SOFT-#{SecureRandom.hex(4)}", price: 29.99, stock: 5)
        nullify_product_price!(product)

        get carti_index_path
        expect(response.body).to include('Disponibil')
      end
    end

    context 'variant with zero stock' do
      it 'disables add-to-cart button for zero-stock variant' do
        product = create_carti_variant_product(name: 'Carte Epuizata')
        option_type = create(:option_type, name: "EditieZ-#{SecureRandom.hex(4)}", presentation: 'Editie')
        product.product_option_types.create!(option_type: option_type, position: 0, primary: true)
        ov = create(:option_value, option_type: option_type, name: "PrimaZ-#{SecureRandom.hex(4)}", presentation: 'Prima')
        create_variant_with_options(product, [ov],
          sku: "CE-PRIMA-#{SecureRandom.hex(4)}", price: 29.99, stock: 0)
        nullify_product_price!(product)

        get carti_index_path
        expect(response.body).to include('disabled')
      end
    end

    context 'variant promo pricing display' do
      it 'shows both original and discount price' do
        product = create_carti_variant_product(name: 'Carte Promo')
        option_type = create(:option_type, name: "PromoT-#{SecureRandom.hex(4)}", presentation: 'PromoType')
        product.product_option_types.create!(option_type: option_type, position: 0, primary: true)
        ov = create(:option_value, option_type: option_type, name: "PromoV-#{SecureRandom.hex(4)}", presentation: 'PromoVal')
        create_variant_with_options(product, [ov],
          sku: "CP-PROMO-#{SecureRandom.hex(4)}", price: 99.99, stock: 10,
          promo_active: true, discount_price: 69.99)
        nullify_product_price!(product)

        get carti_index_path
        body = response.body
        expect(body).to include('99,99')
        expect(body).to include('69,99')
        expect(body).to include('line-through')
      end
    end

    context 'category filtering' do
      it 'filters by category slug' do
        extra_cat = Category.create!(name: "ayurveda-#{SecureRandom.hex(4)}", slug: 'ayurveda')
        product = create_carti_product(name: 'Carte Ayurveda Filter', price: 29.99)
        product.categories << extra_cat

        get carti_index_path, params: { category: 'ayurveda' }
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Carte Ayurveda Filter')
      end
    end
  end

  describe 'GET /carti/:slug (show)' do
    context 'product without variants' do
      it 'returns success and shows product info' do
        product = create_carti_product(name: 'Carte Show Test', price: 59.99, description: 'O carte buna')
        get carti_path(product.slug)
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Carte Show Test')
        expect(response.body).to include('59.99')
      end
    end

    context 'product with variants' do
      let(:product) { create_carti_variant_product(name: 'Carte Variante Show', description: 'Carte cu variante') }
      let(:option_type) { create(:option_type, name: "ShowOT-#{SecureRandom.hex(4)}", presentation: 'Format') }

      before do
        product.product_option_types.create!(option_type: option_type, position: 0, primary: true)
        @ov1 = create(:option_value, option_type: option_type, name: "ShowFiz-#{SecureRandom.hex(4)}", presentation: 'Fizic')
        @ov2 = create(:option_value, option_type: option_type, name: "ShowDig-#{SecureRandom.hex(4)}", presentation: 'Digital')

        @variant1 = create_variant_with_options(product, [@ov1],
          sku: "CVS-FIZ-#{SecureRandom.hex(4)}", price: 79.99, stock: 15,
          external_image_url: 'https://cdn.example.com/fizic.jpg')
        @variant2 = create_variant_with_options(product, [@ov2],
          sku: "CVS-DIG-#{SecureRandom.hex(4)}", price: 49.99, stock: 25)

        nullify_product_price!(product)
      end

      it 'returns success' do
        get carti_path(product.slug)
        expect(response).to have_http_status(:success)
      end

      it 'defaults to first variant when no variant param' do
        get carti_path(product.slug)
        body = response.body
        expect(body).to include("value=\"#{@variant1.id}\"")
      end

      it 'selects specific variant when variant param is provided' do
        get carti_path(product.slug), params: { variant: @variant2.id }
        body = response.body
        expect(body).to include("value=\"#{@variant2.id}\"")
      end

      it 'shows variant price on initial load' do
        get carti_path(product.slug), params: { variant: @variant2.id }
        expect(response.body).to include('49.99')
      end

      it 'shows variant stock info' do
        get carti_path(product.slug), params: { variant: @variant1.id }
        expect(response.body).to include('15')
      end

      it 'uses variant image when available' do
        get carti_path(product.slug), params: { variant: @variant1.id }
        expect(response.body).to include('cdn.example.com/fizic.jpg')
      end

      it 'includes variants JSON data for JS' do
        get carti_path(product.slug)
        expect(response.body).to include('variants-data')
      end

      it 'shows option type dropdown' do
        get carti_path(product.slug)
        expect(response.body).to include('variant-selector')
      end
    end

    context 'product accessed by numeric id' do
      it 'returns success' do
        product = create_carti_product(name: 'Carte By ID', price: 29.99)
        get carti_path(product.id)
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Carte By ID')
      end
    end
  end
end

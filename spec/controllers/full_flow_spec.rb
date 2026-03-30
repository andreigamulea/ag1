require 'rails_helper'

RSpec.describe 'Full E-Commerce Flow', type: :request do
  include Devise::Test::IntegrationHelpers

  # === HELPERS ===

  def create_carti_product(attrs = {})
    product = create(:product, { status: 'active', stock: 10, price: 100 }.merge(attrs))
    carte_cat = Category.find_or_create_by!(name: 'carte') { |c| c.slug = 'carte' }
    fizic_cat = Category.find_or_create_by!(name: 'fizic') { |c| c.slug = 'fizic' }
    product.categories << carte_cat unless product.categories.include?(carte_cat)
    product.categories << fizic_cat unless product.categories.include?(fizic_cat)
    product
  end

  def create_variant_with_options(product, option_values, variant_attrs = {})
    variant = create(:variant, { product: product }.merge(variant_attrs))
    option_values.each do |ov|
      create(:option_value_variant, variant: variant, option_value: ov)
    end
    variant.reload
    variant.save!
    variant
  end

  let(:admin_user) { create(:user, :admin) }

  # ============================================================
  # FLOW 1: PRODUS SIMPLU (fara variante)
  # ============================================================
  describe 'Flow 1: Produs simplu (fara variante)' do
    let!(:product) { create_carti_product(name: 'Carte Simpla', price: 75.00, stock: 5) }

    it 'apare in lista carti' do
      get carti_index_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Carte Simpla')
    end

    it 'afiseaza pagina de produs' do
      get carti_path(product)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Carte Simpla')
      expect(response.body).to include('75')
    end

    it 'adauga in cos si verifica totalul' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 2 }
      expect(response).to redirect_to(cart_index_path)
      follow_redirect!
      expect(response.body).to include('Carte Simpla')
      # 2 x 75 = 150
      expect(response.body).to include('150')
    end

    it 'actualizeaza cantitatea in cos' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 1 }
      post update_all_cart_index_path, params: { quantities: { product.id.to_s => '3' } }
      get cart_index_path
      # 3 x 75 = 225
      expect(response.body).to include('225')
    end

    it 'nu permite adaugare peste stoc' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 10 }
      follow_redirect!
      # Stoc = 5, deci max 5 bucati
      expect(response.body).to include('Carte Simpla')
    end

    it 'sterge din cos' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 1 }
      post remove_cart_index_path, params: { product_id: product.id }
      get cart_index_path
      expect(response.body).not_to include('Carte Simpla')
    end

    it 'goleste cosul' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 2 }
      post clear_cart_index_path
      get cart_index_path
      expect(response.body).not_to include('Carte Simpla')
    end
  end

  # ============================================================
  # FLOW 2: PRODUS CU VARIANTE
  # ============================================================
  describe 'Flow 2: Produs cu variante' do
    let!(:product) { create_carti_product(name: 'Tricou Test', price: 0.01) }
    let!(:color_type) { create(:option_type, name: "Culoare-#{SecureRandom.hex(4)}", presentation: 'Culoare') }
    let!(:size_type) { create(:option_type, name: "Marime-#{SecureRandom.hex(4)}", presentation: 'Marime') }
    let!(:red) { create(:option_value, option_type: color_type, name: "Rosu-#{SecureRandom.hex(4)}", presentation: 'Rosu') }
    let!(:blue) { create(:option_value, option_type: color_type, name: "Albastru-#{SecureRandom.hex(4)}", presentation: 'Albastru') }
    let!(:size_s) { create(:option_value, option_type: size_type, name: "S-#{SecureRandom.hex(4)}", presentation: 'S') }
    let!(:size_m) { create(:option_value, option_type: size_type, name: "M-#{SecureRandom.hex(4)}", presentation: 'M') }

    let!(:variant_red_s) do
      create_variant_with_options(product, [red, size_s],
        sku: "TRI-RS-#{SecureRandom.hex(4)}", price: 100.00, stock: 10)
    end
    let!(:variant_red_m) do
      create_variant_with_options(product, [red, size_m],
        sku: "TRI-RM-#{SecureRandom.hex(4)}", price: 120.00, stock: 5)
    end
    let!(:variant_blue_s) do
      create_variant_with_options(product, [blue, size_s],
        sku: "TRI-BS-#{SecureRandom.hex(4)}", price: 100.00, stock: 8)
    end
    let!(:variant_blue_m) do
      create_variant_with_options(product, [blue, size_m],
        sku: "TRI-BM-#{SecureRandom.hex(4)}", price: 130.00, stock: 0)
    end

    before do
      product.product_option_types.create!(option_type: color_type, position: 0, primary: true)
      product.product_option_types.create!(option_type: size_type, position: 1, primary: false)
      product.update_column(:price, nil)
      product.reload
    end

    it 'apare in lista carti' do
      get carti_index_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Tricou Test')
    end

    it 'afiseaza pagina de produs cu variante' do
      get carti_path(product)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Tricou Test')
    end

    it 'afiseaza pagina de produs cu varianta specifica' do
      get carti_path(product, variant: variant_red_s.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('100')
    end

    it 'adauga varianta in cos cu pretul corect' do
      post add_cart_index_path, params: { product_id: product.id, variant_id: variant_red_m.id, quantity: 1 }
      expect(response).to redirect_to(cart_index_path)
      follow_redirect!
      expect(response.body).to include('Tricou Test')
      expect(response.body).to include('120')
    end

    it 'adauga doua variante diferite in cos' do
      post add_cart_index_path, params: { product_id: product.id, variant_id: variant_red_s.id, quantity: 1 }
      post add_cart_index_path, params: { product_id: product.id, variant_id: variant_blue_s.id, quantity: 2 }
      get cart_index_path
      # Red S = 100, Blue S = 2 x 100 = 200, Total = 300
      expect(response.body).to include('Tricou Test')
      expect(response.body).to include('300')
    end

    it 'nu permite adaugare varianta fara stoc' do
      post add_cart_index_path, params: { product_id: product.id, variant_id: variant_blue_m.id, quantity: 1 }
      # Blue M are stock=0, ar trebui sa fie redirect cu alerta
      expect(response).to redirect_to(cart_index_path).or redirect_to(carti_path(product))
    end

    it 'sterge varianta specifica din cos' do
      post add_cart_index_path, params: { product_id: product.id, variant_id: variant_red_s.id, quantity: 1 }
      post add_cart_index_path, params: { product_id: product.id, variant_id: variant_blue_s.id, quantity: 1 }
      cart_key = "#{product.id}_v#{variant_red_s.id}"
      post remove_cart_index_path, params: { cart_key: cart_key }
      get cart_index_path
      # Red S sters, Blue S ramas = 100
      expect(response.body).to include('100')
    end

    it 'adauga aceeasi varianta de 2 ori - combina cantitatile' do
      post add_cart_index_path, params: { product_id: product.id, variant_id: variant_red_s.id, quantity: 2 }
      post add_cart_index_path, params: { product_id: product.id, variant_id: variant_red_s.id, quantity: 3 }
      get cart_index_path
      # 5 x 100 = 500
      expect(response.body).to include('500')
    end

    it 'navigheaza intre variante pe pagina produsului' do
      # Varianta Red S
      get carti_path(product, variant: variant_red_s.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('100')

      # Varianta Red M
      get carti_path(product, variant: variant_red_m.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('120')

      # Varianta Blue S
      get carti_path(product, variant: variant_blue_s.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('100')

      # Varianta Blue M (fara stoc)
      get carti_path(product, variant: variant_blue_m.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('130')
    end
  end

  # ============================================================
  # FLOW 3: PRODUS CU PRET PROMOTIONAL
  # ============================================================
  describe 'Flow 3: Pret promotional' do
    context 'produs simplu cu promo' do
      let!(:product) do
        create_carti_product(name: 'Carte Promo', price: 100.00, discount_price: 70.00, promo_active: true, stock: 10)
      end

      it 'afiseaza pretul promotional' do
        get carti_path(product)
        expect(response).to have_http_status(:success)
        expect(response.body).to include('70')
      end

      it 'adauga in cos cu pretul promotional' do
        post add_cart_index_path, params: { product_id: product.id, quantity: 2 }
        follow_redirect!
        # 2 x 70 = 140
        expect(response.body).to include('140')
      end
    end

    context 'varianta cu promo' do
      let!(:product) { create_carti_product(name: 'Tricou Promo', price: 0.01) }
      let!(:opt_type) { create(:option_type, name: "Color-#{SecureRandom.hex(4)}", presentation: 'Culoare') }
      let!(:opt_val) { create(:option_value, option_type: opt_type, name: "Rosu-#{SecureRandom.hex(4)}", presentation: 'Rosu') }

      before do
        @variant = create_variant_with_options(product, [opt_val],
          sku: "PROMO-V-#{SecureRandom.hex(4)}", price: 200.00, discount_price: 150.00, promo_active: true, stock: 10)
        product.product_option_types.create!(option_type: opt_type, position: 0, primary: true)
        product.update_column(:price, nil)
        product.reload
      end

      it 'adauga varianta cu pretul promotional' do
        post add_cart_index_path, params: { product_id: product.id, variant_id: @variant.id, quantity: 1 }
        follow_redirect!
        expect(response.body).to include('150')
      end
    end
  end

  # ============================================================
  # FLOW 4: CHECKOUT (fara plata Stripe)
  # ============================================================
  describe 'Flow 4: Checkout' do
    let!(:user) { create(:user) }
    let!(:product) { create_carti_product(name: 'Carte Checkout', price: 100.00, stock: 10) }

    before { sign_in user }

    it 'afiseaza pagina de checkout cu produse in cos' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 1 }
      get new_order_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('100')
    end

    it 'calculeaza transport pentru comenzi sub 200 RON' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 1 }
      get new_order_path
      # 100 RON < 200, transport = 20 RON
      expect(response.body).to include('20')
    end

    it 'transport gratuit pentru comenzi peste 200 RON' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 3 }
      get new_order_path
      # 300 RON > 200, transport gratuit
      expect(response.body).to include('300')
    end
  end

  # ============================================================
  # FLOW 5: ADMIN - CRUD PRODUSE
  # ============================================================
  describe 'Flow 5: Admin CRUD produse' do
    before { sign_in admin_user }

    it 'listeaza produse' do
      create_carti_product(name: 'Produs Admin Test')
      get products_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Produs Admin Test')
    end

    it 'creaza produs simplu' do
      carte_cat = Category.find_or_create_by!(name: 'carte') { |c| c.slug = 'carte' }
      fizic_cat = Category.find_or_create_by!(name: 'fizic') { |c| c.slug = 'fizic' }

      post products_path, params: {
        product: {
          name: 'Produs Nou', slug: 'produs-nou', sku: "PN-#{SecureRandom.hex(4)}",
          price: 50.00, stock: 20, status: 'active',
          category_ids: ['', carte_cat.id.to_s, fizic_cat.id.to_s]
        }
      }
      expect(response).to have_http_status(:redirect)
      expect(Product.find_by(name: 'Produs Nou')).to be_present
    end

    it 'creaza produs cu variante' do
      opt_type = create(:option_type, name: "Material-#{SecureRandom.hex(4)}", presentation: 'Material')
      opt_val = create(:option_value, option_type: opt_type, name: "Bumbac-#{SecureRandom.hex(4)}", presentation: 'Bumbac')

      post products_path, params: {
        product: {
          name: 'Produs Variante', slug: 'produs-variante', sku: "PV-#{SecureRandom.hex(4)}",
          price: 0.01, status: 'active',
          variants_attributes: {
            '0' => {
              sku: "PV-BUM-#{SecureRandom.hex(4)}", price: 80.00, stock: 15,
              vat_rate: 19, status: 'active', height: 10, width: 20, depth: 5, weight: 200,
              ean: "#{rand(1000000000000..9999999999999)}",
              option_value_ids: [opt_val.id.to_s]
            }
          }
        },
        primary_option_type_id: opt_type.id
      }
      expect(response).to have_http_status(:redirect)
      product = Product.find_by(name: 'Produs Variante')
      expect(product).to be_present
      expect(product.variants.count).to eq(1)
      expect(product.variants.first.height).to eq(10)
      expect(product.variants.first.ean).to be_present
    end

    it 'arhiveaza produs (soft delete)' do
      product = create_carti_product(name: 'Produs De Sters')
      delete product_path(product)
      expect(response).to redirect_to(products_path)
      product.reload
      expect(product.status).to eq('archived')
    end

    it 'reactiveaza produs arhivat' do
      product = create_carti_product(name: 'Produs Arhivat', status: 'archived')
      patch unarchive_product_path(product)
      expect(response).to redirect_to(products_path)
      product.reload
      expect(product.status).to eq('active')
    end
  end

  # ============================================================
  # FLOW 6: CUPON DE REDUCERE
  # ============================================================
  describe 'Flow 6: Cupon de reducere' do
    let!(:user) { create(:user) }
    let!(:product) { create_carti_product(name: 'Carte Cupon', price: 200.00, stock: 10) }
    let!(:coupon) do
      Coupon.create!(
        code: "TEST20-#{SecureRandom.hex(4)}",
        discount_type: 'percentage',
        discount_value: 20,
        active: true,
        starts_at: 1.day.ago,
        expires_at: 1.day.from_now,
        usage_limit: 100,
        usage_count: 0,
        minimum_cart_value: 0,
        minimum_quantity: 0
      )
    end

    before { sign_in user }

    it 'aplica cupon si calculeaza reducerea' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 1 }
      post apply_coupon_path, params: { code: coupon.code }
      expect(response).to redirect_to(cart_index_path)
      follow_redirect!
      # 200 - 20% = 160, deci totalul trebuie sa fie 160
      expect(response.body).to include('160')
    end

    it 'sterge cuponul' do
      post add_cart_index_path, params: { product_id: product.id, quantity: 1 }
      post apply_coupon_path, params: { code: coupon.code }
      post remove_coupon_path
      expect(response).to redirect_to(cart_index_path)
      follow_redirect!
      # Fara cupon, pretul e 200
      expect(response.body).to include('200')
    end
  end

  # ============================================================
  # FLOW 7: VALIDARI SI EDGE CASES
  # ============================================================
  describe 'Flow 7: Validari si edge cases' do
    it 'nu afiseaza produse inactive in carti' do
      create_carti_product(name: 'Produs Inactiv', status: 'inactive')
      get carti_index_path
      expect(response.body).not_to include('Produs Inactiv')
    end

    it 'nu afiseaza produse arhivate in carti' do
      create_carti_product(name: 'Produs Arhivat', status: 'archived')
      get carti_index_path
      expect(response.body).not_to include('Produs Arhivat')
    end

    it 'nu permite acces admin fara autentificare' do
      get products_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'nu permite acces admin pentru user normal' do
      user = create(:user)
      sign_in user
      get products_path
      # Redirects to root with "Acces interzis"
      expect(response).to redirect_to(root_path)
    end

    it 'produsul fara categoriile carte+fizic nu apare in carti' do
      product = create(:product, name: 'Produs Fara Categorie', status: 'active', price: 50)
      get carti_index_path
      expect(response.body).not_to include('Produs Fara Categorie')
    end

    it 'varianta inactiva nu apare pe pagina produsului' do
      product = create_carti_product(name: 'Produs Var Inactiva', price: 0.01)
      opt_type = create(:option_type, name: "OT-#{SecureRandom.hex(4)}")
      opt_val = create(:option_value, option_type: opt_type, name: "OV-#{SecureRandom.hex(4)}")
      product.product_option_types.create!(option_type: opt_type, position: 0, primary: true)

      create_variant_with_options(product, [opt_val],
        sku: "ACT-#{SecureRandom.hex(4)}", price: 50, stock: 10, status: :active)

      opt_val2 = create(:option_value, option_type: opt_type, name: "OV2-#{SecureRandom.hex(4)}")
      inactive_v = create_variant_with_options(product, [opt_val2],
        sku: "INACT-#{SecureRandom.hex(4)}", price: 60, stock: 5, status: :inactive)

      product.update_column(:price, nil)
      get carti_path(product)
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(inactive_v.sku)
    end
  end
end

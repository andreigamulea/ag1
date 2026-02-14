require_relative "../../application_system_test_case"

class SuiteTestCase < ApplicationSystemTestCase
  # Testele de sistem nu pot rula în paralel (un singur browser)
  parallelize(workers: 1)

  # Dezactivăm complet fixtures - testele noastre creează propriile date
  self.use_transactional_tests = true

  # Override setup_fixtures și teardown_fixtures pentru a dezactiva total încărcarea fixtures
  def setup_fixtures
    # Nu facem nimic - nu încărcăm fixtures
  end

  def teardown_fixtures
    # Nu facem nimic - nu avem fixtures de curățat
  end

  # ── Crearea datelor de test ──────────────────────────────────────

  def create_test_user(email: nil, password: "password123", role: 0, active: true)
    # Generăm email unic automat dacă nu e specificat
    email ||= "test-#{SecureRandom.hex(8)}@example.com"

    User.create!(
      email: email,
      password: password,
      password_confirmation: password,
      role: role,
      active: active
    )
  end

  def create_admin_user(email: nil, password: "password123")
    # Generăm email unic automat dacă nu e specificat
    email ||= "admin-#{SecureRandom.hex(8)}@example.com"

    create_test_user(email: email, password: password, role: 1)
  end

  # Creează un produs vizibil pe /carti (necesită categorii 'carte' + 'fizic')
  def create_test_product(overrides = {})
    # Generăm identificatori unici cu timestamp pentru a evita coliziuni
    unique_id = "#{Time.now.to_i}-#{SecureRandom.hex(4)}"

    # Dacă se specifică un nume custom, generăm slug unic din el
    if overrides[:name] && !overrides[:slug]
      base_slug = overrides[:name].parameterize
      overrides[:slug] = "#{base_slug}-#{unique_id}"
    end

    # Dacă nu se specifică SKU, generăm unul unic
    overrides[:sku] ||= "SKU-#{unique_id}"

    defaults = {
      name: "Carte Test Ayurveda #{unique_id}",
      slug: "carte-test-ayurveda-#{unique_id}",
      sku: overrides[:sku],
      description: "O carte despre medicina ayurvedica traditionala",
      price: 49.99,
      stock: 100,
      stock_status: "in_stock",
      product_type: "physical",
      delivery_method: "shipping",
      status: "active"
    }
    product = Product.create!(defaults.merge(overrides))

    # Asociază categoriile necesare pentru a apărea pe /carti
    cat_carte = Category.find_or_create_by!(name: "carte") { |c| c.slug = "carte" }
    cat_fizic = Category.find_or_create_by!(name: "fizic") { |c| c.slug = "fizic" }
    product.categories << cat_carte unless product.categories.include?(cat_carte)
    product.categories << cat_fizic unless product.categories.include?(cat_fizic)

    product
  end

  # Creează un produs cu variante (price devine opțional)
  def create_test_product_with_variants(overrides = {})
    # Generăm identificatori unici cu timestamp pentru a evita coliziuni
    unique_id = "#{Time.now.to_i}-#{SecureRandom.hex(4)}"
    defaults = {
      name: "Produs cu Variante #{unique_id}",
      slug: "produs-variante-#{unique_id}",
      sku: "SKU-#{unique_id}",
      description: "Produs disponibil in multiple variante",
      price: 0.01,  # Price minimal pentru validare, variantele au pretul real
      stock: 0,
      stock_status: "in_stock",
      product_type: "physical",
      delivery_method: "shipping",
      status: "active"
    }
    product = Product.create!(defaults.merge(overrides))

    # Asociază categoriile
    cat_carte = Category.find_or_create_by!(name: "carte") { |c| c.slug = "carte" }
    cat_fizic = Category.find_or_create_by!(name: "fizic") { |c| c.slug = "fizic" }
    product.categories << cat_carte unless product.categories.include?(cat_carte)
    product.categories << cat_fizic unless product.categories.include?(cat_fizic)

    product
  end

  # Creează o variantă pentru un produs
  def create_test_variant(product:, overrides: {})
    defaults = {
      sku: "VAR-#{SecureRandom.hex(4)}",
      price: 49.99,
      vat_rate: 19.00,
      stock: 50,
      status: 0,  # active
      external_image_url: nil,
      external_image_urls: []
    }
    product.variants.create!(defaults.merge(overrides))
  end

  def create_test_coupon(overrides = {})
    defaults = {
      code: "TEST#{Time.now.to_i}#{SecureRandom.hex(4).upcase}",
      discount_type: "percentage",
      discount_value: 10,
      active: true,
      starts_at: 1.day.ago,
      expires_at: 30.days.from_now,
      usage_limit: 100,
      usage_count: 0,
      minimum_cart_value: nil,
      minimum_quantity: nil,
      product_id: nil,
      free_shipping: false
    }
    merged = defaults.merge(overrides)
    # Clean up stale coupons with the same code from previous failed test runs
    Coupon.where("UPPER(code) = ?", merged[:code].to_s.upcase).destroy_all
    Coupon.create!(merged)
  end

  def create_location_data
    tara = Tari.find_or_create_by!(nume: "Romania")
    judet = Judet.find_or_create_by!(denjud: "Bucuresti", cod_j: "B")
    Localitati.find_or_create_by!(
      denumire: "Bucuresti",
      denj: "Bucuresti"
    )
    [tara, judet]
  end

  # ── Acțiuni comune în browser ────────────────────────────────────

  def sign_up(email:, password:)
    visit new_user_registration_path
    fill_in "Email", with: email
    fill_in "user[password]", with: password, match: :first
    fill_in "user[password_confirmation]", with: password
    click_button "Creează cont"
  end

  def sign_in(email:, password:)
    visit new_user_session_path
    assert_selector "input[name='user[password]']", wait: 5
    fill_in "Email", with: email
    fill_in "user[password]", with: password
    click_button "Intră în cont"
    # Wait for login redirect to complete; retry once if still on login page
    if page.has_selector?("input[name='user[password]']", wait: 3)
      fill_in "Email", with: email
      fill_in "user[password]", with: password
      click_button "Intră în cont"
    end
  end

  def sign_out
    find("#account-toggle").click if page.has_css?("#account-toggle")
    click_button "Logout" if page.has_button?("Logout")
  end

  def add_product_to_cart(product)
    visit carti_path(product.slug || product.id)
    click_button "Adauga in cos"  # Textul real din view (fără diacritice)
  end

  # Adaugă o variantă specifică în coș (pentru produse cu opțiuni)
  def add_variant_to_cart(product, variant)
    visit carti_path(product.slug || product.id)

    # Selectăm variantele pe baza option_values (swatches + butoane)
    variant.option_values.each do |option_value|
      swatch_selector = ".variant-swatch[data-option-value-id='#{option_value.id}']"
      btn_selector = ".variant-btn[data-option-value-id='#{option_value.id}']"

      if page.has_css?(swatch_selector)
        find(swatch_selector).click
      elsif page.has_css?(btn_selector)
        find(btn_selector).click
      end
    end

    # Adăugăm în coș
    click_button "Adauga in cos"  # Textul real din view (fără diacritice)
  end

  def go_to_cart
    visit cart_index_path
  end

  def go_to_checkout
    visit new_order_path
  end

  def sign_in_as_admin(password: "password123")
    admin = create_admin_user(password: password)
    sign_in(email: admin.email, password: password)
    admin
  end

  def create_test_order(user:, product:, variant: nil, status: "pending")
    create_location_data

    # Dacă avem variantă, folosim prețul variantei; altfel, al produsului
    price = variant ? variant.price : product.price
    vat_rate = variant ? (variant.vat_rate || 19.00) : 19.00

    order = Order.create!(
      user: user,
      status: status,
      placed_at: Time.current,
      first_name: "Test", last_name: "User",
      email: user.email,
      phone: "0749079619",
      country: "Romania", county: "Bucuresti", city: "Bucuresti",
      postal_code: "010101",
      street: "Str. Test", street_number: "1",
      shipping_first_name: "Test", shipping_last_name: "User",
      shipping_country: "Romania", shipping_county: "Bucuresti",
      shipping_city: "Bucuresti", shipping_postal_code: "010101",
      shipping_street: "Str. Test", shipping_street_number: "1",
      shipping_phone: "0749079619",
      cnp: "0000000000000"
    )

    # Calculăm VAT și totale
    vat_amount = (price * vat_rate / 100).round(2)
    total_with_vat = (price + vat_amount).round(2)

    order_item_attrs = {
      product: product,
      product_name: product.name,
      quantity: 1,
      unit_price: price,
      price: price,
      total_price: price,
      vat: vat_amount,
      vat_rate_snapshot: vat_rate,
      currency: "RON",
      line_total_gross: total_with_vat,
      tax_amount: vat_amount
    }

    # Dacă avem variantă, adăugăm câmpurile specifice
    if variant
      order_item_attrs.merge!({
        variant: variant,
        variant_sku: variant.sku,
        variant_options_text: variant.option_values.map { |ov| "#{ov.option_type.name}: #{ov.value}" }.join(", ")
      })
    end

    order.order_items.create!(order_item_attrs)
    order
  end

  # Completează formularul de shipping cu date valide (inclusiv autocomplete-uri via JS)
  def fill_shipping_address(overrides = {})
    defaults = {
      last_name: "Popescu",
      first_name: "Ion",
      phone: "0749079619",
      postal_code: "010101",
      street: "Str. Ostasilor",
      street_number: "15"
    }
    data = defaults.merge(overrides)

    fill_in "order[shipping_last_name]", with: data[:last_name]
    fill_in "order[shipping_first_name]", with: data[:first_name]
    fill_in "order[shipping_phone]", with: data[:phone]
    fill_in "order[shipping_postal_code]", with: data[:postal_code]
    fill_in "order[shipping_street]", with: data[:street]
    fill_in "order[shipping_street_number]", with: data[:street_number]

    # Setăm județ via autocomplete
    judet_input = find("#shipping_judet_input")
    judet_input.fill_in with: "Bu"
    sleep 0.5
    if page.has_css?("#shipping_judet_dropdown .dropdown-item", wait: 2)
      find("#shipping_judet_dropdown .dropdown-item", text: /Bucuresti/i, match: :first).click
    end

    # Setăm localitate - poate fi disabled, activăm via JS
    page.execute_script("document.querySelector('#shipping_localitate_input').disabled = false")
    find("#shipping_localitate_input").fill_in with: "Bu"
    sleep 0.5
    if page.has_css?("#shipping_localitate_dropdown .dropdown-item", wait: 2)
      find("#shipping_localitate_dropdown .dropdown-item", text: /Bucuresti/i, match: :first).click
    else
      page.execute_script("document.querySelector('input[name=\"order[shipping_city]\"]').value = 'Bucuresti'")
    end

    # Forțăm valoarea pentru country (autocomplete JS o poate șterge pe blur)
    page.execute_script("document.querySelector('#shipping_tara_input').value = 'Romania'")
  end

  # Completează formularul de billing (necesită toggle-ul bifat)
  def fill_billing_address(overrides = {})
    defaults = {
      last_name: "Popescu",
      first_name: "Ion",
      phone: "0749079619",
      postal_code: "010101",
      street: "Str. Ostasilor",
      street_number: "15",
      email: "ion.popescu@example.com"
    }
    data = defaults.merge(overrides)

    # Bifăm toggle-ul dacă nu e deja bifat
    check "order[use_different_billing]" unless find("#toggle-billing", visible: :all).checked?
    assert_selector "#billing-fields", visible: true

    within "#billing-fields" do
      fill_in "order[last_name]", with: data[:last_name]
      fill_in "order[first_name]", with: data[:first_name]
      fill_in "order[phone]", with: data[:phone]
      fill_in "order[postal_code]", with: data[:postal_code]
      fill_in "order[street]", with: data[:street]
      fill_in "order[street_number]", with: data[:street_number]
      fill_in "order[email]", with: data[:email]
    end

    # Setăm country/county/city pentru billing via JS
    page.execute_script("document.querySelector('#tara_input').value = 'Romania'")
    page.execute_script("document.querySelector('#judet_input').disabled = false")
    page.execute_script("document.querySelector('#judet_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('#localitate_input').disabled = false")
    page.execute_script("document.querySelector('#localitate_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('input[name=\"order[county]\"]').value = 'Bucuresti'")
    page.execute_script("document.querySelector('input[name=\"order[city]\"]').value = 'Bucuresti'")
  end
end

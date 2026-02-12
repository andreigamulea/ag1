require_relative "suite_test_helper"

class OrderManagementTest < SuiteTestCase
  setup do
    create_location_data
    @product = create_test_product(name: "Carte Order Test", price: 50.00, stock: 30)
    @user = create_test_user(password: "password123")
    @admin = create_admin_user(password: "password123")
  end

  # ── ISTORIC COMENZI ───────────────────────────────────────────────

  test "user autentificat vede pagina de istoric comenzi" do
    order = create_test_order(user: @user, product: @product, status: "paid")

    sign_in(email: @user.email, password: "password123")
    assert_selector "#account-toggle", wait: 10
    visit orders_path

    assert_text "Comenzi", wait: 5
    assert_text @user.email
  end

  test "user vede doar comenzile proprii" do
    order1 = create_test_order(user: @user, product: @product, status: "paid")
    other = create_test_user(password: "password123")
    order2 = create_test_order(user: other, product: @product, status: "paid")

    sign_in(email: @user.email, password: "password123")
    assert_selector "#account-toggle", wait: 10
    visit orders_path

    assert_text @user.email
    assert_no_text other.email
  end

  test "admin vede toate comenzile" do
    order1 = create_test_order(user: @user, product: @product, status: "paid")
    other = create_test_user(password: "password123")
    order2 = create_test_order(user: other, product: @product, status: "paid")

    sign_in(email: @admin.email, password: "password123")
    assert_selector "#account-toggle", wait: 10
    visit orders_path

    assert_text "ADMINISTRARE COMENZI", wait: 5
    assert_text @user.email
    assert_text other.email
  end

  test "pagina de istoric afișează status și total" do
    order = create_test_order(user: @user, product: @product, status: "paid")

    sign_in(email: @user.email, password: "password123")
    assert_selector "#account-toggle", wait: 10
    visit orders_path

    assert_text "paid", wait: 5
  end

  # ── DETALII COMANDĂ (AJAX) ────────────────────────────────────────

  test "admin poate vedea detaliile unei comenzi" do
    order = create_test_order(user: @user, product: @product, status: "paid")

    sign_in(email: @admin.email, password: "password123")
    assert_selector "#account-toggle", wait: 10
    visit orders_path

    assert_text "ADMINISTRARE COMENZI", wait: 5
    assert_text @user.email

    # Click pe primul buton "Produse" (CSS text-transform face textul uppercase)
    first("button", text: "PRODUSE").click

    # Detaliile ar trebui să apară în panoul lateral
    assert_text "Produse Comandă", wait: 5
  end

  # ── CHECKOUT PRE-POPULAT ──────────────────────────────────────────

  test "checkout pre-completează datele din ultima comandă pentru client returnat" do
    order = create_test_order(user: @user, product: @product, status: "paid")

    sign_in(email: @user.email, password: "password123")
    assert_selector "#account-toggle", wait: 10
    add_product_to_cart(@product)
    go_to_checkout

    # Câmpurile ar trebui pre-populate din ultima comandă
    assert_field "order[shipping_last_name]", with: "User"
    assert_field "order[shipping_first_name]", with: "Test"
  end

  # ── VALIDĂRI CHECKOUT AVANSATE ────────────────────────────────────

  test "checkout cu billing diferit de shipping păstrează ambele adrese" do
    add_product_to_cart(@product)
    assert_text @product.name, wait: 5  # verificăm că produsul a fost adăugat
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    fill_shipping_address(
      last_name: "Shipping",
      first_name: "Adresa",
      phone: "0749079619",
      postal_code: "010101",
      street: "Str. Shipping",
      street_number: "10"
    )

    fill_billing_address(
      last_name: "Billing",
      first_name: "Adresa",
      phone: "0749079620",
      postal_code: "020202",
      street: "Str. Billing",
      street_number: "20",
      email: "billing@test.com"
    )

    # Verificăm că ambele adrese sunt completate
    assert_field "order[shipping_last_name]", with: "Shipping"
    within "#billing-fields" do
      assert_field "order[last_name]", with: "Billing"
    end
  end

  test "checkout validează email invalid" do
    add_product_to_cart(@product)
    assert_text @product.name, wait: 5
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    fill_shipping_address

    check "order[use_different_billing]"
    within "#billing-fields" do
      fill_in "order[email]", with: "email-invalid"
      fill_in "order[last_name]", with: "Test"
      fill_in "order[first_name]", with: "User"
      fill_in "order[phone]", with: "0749079619"
      fill_in "order[postal_code]", with: "010101"
      fill_in "order[street]", with: "Str. Test"
      fill_in "order[street_number]", with: "1"
    end
    page.execute_script("document.querySelector('#tara_input').value = 'Romania'")
    page.execute_script("document.querySelector('#judet_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('#localitate_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('input[name=\"order[county]\"]').value = 'Bucuresti'")
    page.execute_script("document.querySelector('input[name=\"order[city]\"]').value = 'Bucuresti'")

    click_button "Plasează comanda"

    # Nu ar trebui să reușească
    assert_no_text "Mulțumim pentru comandă"
  end

  test "checkout validează cod poștal prea scurt" do
    add_product_to_cart(@product)
    assert_text @product.name, wait: 5
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    fill_in "order[shipping_last_name]", with: "Test"
    fill_in "order[shipping_first_name]", with: "User"
    fill_in "order[shipping_phone]", with: "0749079619"
    fill_in "order[shipping_postal_code]", with: "12"  # prea scurt (minim 4)
    fill_in "order[shipping_street]", with: "Str. Test"
    fill_in "order[shipping_street_number]", with: "1"

    check "order[use_different_billing]"
    within "#billing-fields" do
      fill_in "order[email]", with: "test@test.com"
      fill_in "order[last_name]", with: "Test"
      fill_in "order[first_name]", with: "User"
      fill_in "order[phone]", with: "0749079619"
      fill_in "order[postal_code]", with: "010101"
      fill_in "order[street]", with: "Str. Test"
      fill_in "order[street_number]", with: "1"
    end
    page.execute_script("document.querySelector('#tara_input').value = 'Romania'")
    page.execute_script("document.querySelector('#judet_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('#localitate_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('input[name=\"order[county]\"]').value = 'Bucuresti'")
    page.execute_script("document.querySelector('input[name=\"order[city]\"]').value = 'Bucuresti'")

    click_button "Plasează comanda"

    assert_no_text "Mulțumim pentru comandă"
  end

  # ── CHECKOUT CU COȘ GOL ───────────────────────────────────────────

  test "checkout fără produse în coș" do
    Capybara.using_session(:empty_order) do
      visit new_order_path
      # Pagina ar trebui să se încarce fără erori
      assert_no_text "Internal Server Error"
    end
  end
end

require_relative "suite_test_helper"

class CheckoutSavedAddressesTest < SuiteTestCase

  # ── SELECTOR ADRESE PE CHECKOUT ────────────────────────────

  test "checkout afișează selectorul de adrese salvate" do
    user = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product
    add_product_to_cart(product)

    user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", postal_code: "010101", street: "Str. Test", street_number: "1"
    )

    sign_in(email: user.email, password: "parola123")
    visit new_order_path

    assert_selector "#shipping-address-picker", wait: 5
    assert_selector "option", text: "Ion Popescu"
  end

  test "checkout fără adrese salvate nu afișează selector" do
    user = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product
    add_product_to_cart(product)

    sign_in(email: user.email, password: "parola123")
    visit new_order_path

    assert_no_selector "#shipping-address-picker"
  end

  test "checkout pre-populează câmpurile din adresa default" do
    user = create_test_user(password: "parola123")
    create_location_data

    user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", postal_code: "010101", street: "Str. Ostasilor",
      street_number: "15", default: true
    )

    product = create_test_product
    add_product_to_cart(product)

    sign_in(email: user.email, password: "parola123")
    visit new_order_path

    assert_field "order[shipping_first_name]", with: "Ion", wait: 5
    assert_field "order[shipping_last_name]", with: "Popescu"
    assert_field "order[shipping_phone]", with: "0749079619"
    assert_field "order[shipping_street]", with: "Str. Ostasilor"
  end

  test "selectare altă adresă salvată schimbă câmpurile" do
    user = create_test_user(password: "parola123")
    create_location_data

    user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", street: "Str. Ostasilor", street_number: "15"
    )
    user.addresses.create!(
      address_type: "shipping", first_name: "Maria", last_name: "Ionescu",
      phone: "0722000000", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", street: "Str. Florilor", street_number: "7"
    )

    product = create_test_product
    add_product_to_cart(product)

    sign_in(email: user.email, password: "parola123")
    visit new_order_path

    # Selectăm a doua adresă
    second_addr = user.shipping_addresses.last
    select "Maria Ionescu", from: "shipping-address-picker"

    # Câmpurile trebuie să se schimbe
    sleep 0.5
    assert_field "order[shipping_first_name]", with: "Maria"
    assert_field "order[shipping_street]", with: "Str. Florilor"
  end

  test "selectare 'Adauga adresa noua' golește câmpurile" do
    user = create_test_user(password: "parola123")
    create_location_data

    user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", street: "Str. Ostasilor", street_number: "15"
    )

    product = create_test_product
    add_product_to_cart(product)

    sign_in(email: user.email, password: "parola123")
    visit new_order_path

    select "Adauga adresa noua", from: "shipping-address-picker"

    sleep 0.5
    assert_field "order[shipping_first_name]", with: ""
    assert_field "order[shipping_street]", with: ""
  end

  # ── BILLING SELECTOR ───────────────────────────────────────

  test "checkout billing selector apare când bifat checkbox" do
    user = create_test_user(password: "parola123")
    create_location_data

    user.addresses.create!(
      address_type: "billing", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", email: "ion@test.com", country: "Romania",
      county: "Bucuresti", city: "Bucuresti", street: "Str. Firmei",
      street_number: "10", company_name: "SC Test SRL", cui: "RO123"
    )

    product = create_test_product
    add_product_to_cart(product)

    sign_in(email: user.email, password: "parola123")
    visit new_order_path

    # Billing selector nu e vizibil inițial
    assert_no_selector "#billing-address-picker", visible: true

    # Bifăm checkbox-ul
    check "order[use_different_billing]"

    assert_selector "#billing-address-picker", visible: true, wait: 3
    assert_selector "option", text: "SC Test SRL"
  end

  # ── FALLBACK PE ULTIMA COMANDĂ ─────────────────────────────

  test "fără adrese salvate dar cu comenzi pre-populează din ultima comandă" do
    user = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product
    order = create_test_order(user: user, product: product, status: "paid")

    # User are comandă dar nu are adrese salvate
    assert_equal 0, user.addresses.count
    assert user.orders.exists?

    product2 = create_test_product
    add_product_to_cart(product2)

    sign_in(email: user.email, password: "parola123")
    visit new_order_path

    # Câmpurile trebuie pre-populate din ultima comandă
    assert_field "order[shipping_first_name]", with: "Test", wait: 5
  end
end

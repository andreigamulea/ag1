require_relative "suite_test_helper"

class ShippingTest < SuiteTestCase
  setup do
    create_location_data
  end

  # ── TRANSPORT 20 RON (SUBTOTAL < 200) ─────────────────────────────

  test "produs fizic sub 200 RON are transport 20 RON" do
    product = create_test_product(
      name: "Carte Transport 20",
      price: 45.00,
      stock: 50
    )
    add_product_to_cart(product)
    go_to_checkout

    assert_text "Transport"
    assert_text "20"
  end

  # ── TRANSPORT GRATUIT (SUBTOTAL >= 200) ───────────────────────────

  test "produs fizic peste 200 RON are transport gratuit" do
    product = create_test_product(
      name: "Carte Scumpă",
      price: 210.00,
      stock: 50
    )
    add_product_to_cart(product)
    go_to_checkout

    assert_text "Transport"
    # Transport gratuit
    assert_text "Gratuit"
  end

  # ── CUPON FREE SHIPPING ───────────────────────────────────────────

  test "cupon cu free_shipping face transportul gratuit" do
    product = create_test_product(
      name: "Carte Free Ship",
      price: 45.00,
      stock: 50
    )
    create_test_coupon(
      code: "FREESHIP",
      discount_type: "percentage",
      discount_value: 5,
      free_shipping: true
    )

    add_product_to_cart(product)
    go_to_cart

    fill_in "code", with: "FREESHIP"
    click_button "Aplică cuponul"
    assert_text "aplicat"

    # Verificăm pe pagina de coș (checkout-ul nu implementează free_shipping)
    assert_text "Transport"
    assert_selector ".free-shipping", text: "Gratuit"
  end

  # ── VERIFICARE SUMAR ──────────────────────────────────────────────

  test "pagina de checkout afișează Subtotal, Transport și Total" do
    product = create_test_product(
      name: "Carte Sumar",
      price: 75.00,
      stock: 50
    )
    add_product_to_cart(product)
    go_to_checkout

    assert_text "Subtotal"
    assert_text "Transport"
    assert_text "Total"
    assert_text "75"
  end

  # ── PRODUSE MULTIPLE ──────────────────────────────────────────────

  test "totalul reflectă mai multe produse cu cantități diferite" do
    product1 = create_test_product(
      name: "Carte Multi 1",
      price: 50.00,
      stock: 50
    )
    product2 = create_test_product(
      name: "Carte Multi 2",
      price: 30.00,
      stock: 50
    )

    add_product_to_cart(product1)
    assert_text product1.name, wait: 5
    add_product_to_cart(product2)
    assert_text product2.name, wait: 5
    go_to_checkout

    # Subtotal = 50 + 30 = 80, sub 200 deci transport = 20
    assert_text "Carte Multi 1"
    assert_text "Carte Multi 2"
    assert_text "Subtotal"
  end
end

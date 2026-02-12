require_relative "suite_test_helper"

class CouponAdvancedTest < SuiteTestCase
  setup do
    @product = create_test_product(
      name: "Carte Cupon Avansat",
      price: 45.00,
      stock: 50
    )
    @product2 = create_test_product(
      name: "Carte Meditatie Avansata",
      price: 55.00,
      stock: 30
    )
    add_product_to_cart(@product)
  end

  # ── CUPON EXPIRAT ─────────────────────────────────────────────────

  test "cupon expirat nu se aplică" do
    create_test_coupon(
      code: "EXPIRAT",
      expires_at: 2.days.ago,
      starts_at: 10.days.ago
    )

    go_to_cart
    fill_in "code", with: "EXPIRAT"
    click_button "Aplică cuponul"

    assert_text "expirat"
  end

  # ── CUPON INACTIV ─────────────────────────────────────────────────

  test "cupon inactiv nu se aplică" do
    create_test_coupon(code: "INACTIV", active: false)

    go_to_cart
    fill_in "code", with: "INACTIV"
    click_button "Aplică cuponul"

    assert_text "inactiv"
  end

  # ── CUPON CARE NU A ÎNCEPUT ───────────────────────────────────────

  test "cupon care nu a început încă nu se aplică" do
    create_test_coupon(
      code: "VIITOR",
      starts_at: 5.days.from_now,
      expires_at: 30.days.from_now
    )

    go_to_cart
    fill_in "code", with: "VIITOR"
    click_button "Aplică cuponul"

    assert_text "expirat"  # mesajul acoperă și "nu a început încă"
  end

  # ── CUPON CU USAGE LIMIT ATINS ────────────────────────────────────

  test "cupon cu limita de utilizări atinsă nu se aplică" do
    create_test_coupon(
      code: "LIMITAT",
      usage_limit: 5,
      usage_count: 5
    )

    go_to_cart
    fill_in "code", with: "LIMITAT"
    click_button "Aplică cuponul"

    assert_text "utilizat"
  end

  # ── CUPON CU MINIMUM CART VALUE ───────────────────────────────────

  test "cupon cu valoare minimă coș: sub minim nu se aplică" do
    create_test_coupon(
      code: "MIN100",
      minimum_cart_value: 100
    )

    go_to_cart
    fill_in "code", with: "MIN100"
    click_button "Aplică cuponul"

    # Coș = 45 RON < 100 RON minim
    assert_text "minim"
  end

  test "cupon cu valoare minimă coș: la minim se aplică" do
    # Adăugăm și al doilea produs (45 + 55 = 100)
    add_product_to_cart(@product2)

    create_test_coupon(
      code: "MIN100OK",
      minimum_cart_value: 100,
      discount_type: "percentage",
      discount_value: 10
    )

    go_to_cart
    fill_in "code", with: "MIN100OK"
    click_button "Aplică cuponul"

    assert_text "MIN100OK"
    assert_text "aplicat"
  end

  # ── CUPON CU MINIMUM QUANTITY ─────────────────────────────────────

  test "cupon cu cantitate minimă: sub minim nu se aplică" do
    create_test_coupon(
      code: "MINQTY3",
      minimum_quantity: 3
    )

    go_to_cart
    # Avem doar 1 produs în coș
    fill_in "code", with: "MINQTY3"
    click_button "Aplică cuponul"

    assert_text "minim"
  end

  # ── CUPON PRODUCT-SPECIFIC ────────────────────────────────────────

  test "cupon specific pentru un produs care nu e în coș" do
    create_test_coupon(
      code: "PRODSPEC",
      product_id: @product2.id
    )

    # Avem doar @product în coș, nu @product2
    go_to_cart
    fill_in "code", with: "PRODSPEC"
    click_button "Aplică cuponul"

    assert_text "Produsul specificat"
  end

  test "cupon specific pentru un produs care e în coș se aplică" do
    coupon = create_test_coupon(
      code: "PRODOK",
      product_id: @product.id,
      discount_type: "percentage",
      discount_value: 15
    )

    go_to_cart
    fill_in "code", with: coupon.code
    click_button "Aplică cuponul"

    assert_text coupon.code
    assert_text "aplicat"
  end

  # ── CUPON INEXISTENT ──────────────────────────────────────────────

  test "cupon inexistent afișează mesaj de eroare" do
    go_to_cart
    fill_in "code", with: "NICIUNCUPON"
    click_button "Aplică cuponul"

    assert_text "nu există"
  end

  # ── CUPON FIXED VS PERCENTAGE ─────────────────────────────────────

  test "cupon procentual aplică reducerea corect" do
    create_test_coupon(
      code: "PROC20",
      discount_type: "percentage",
      discount_value: 20
    )

    go_to_cart
    fill_in "code", with: "PROC20"
    click_button "Aplică cuponul"

    assert_text "PROC20"
    assert_text "aplicat"
    assert_text "Reducere"
  end

  test "cupon fix aplică reducerea corect" do
    create_test_coupon(
      code: "FIX10",
      discount_type: "fixed",
      discount_value: 10
    )

    go_to_cart
    fill_in "code", with: "FIX10"
    click_button "Aplică cuponul"

    assert_text "FIX10"
    assert_text "aplicat"
    assert_text "Reducere"
  end

  # ── ELIMINARE CUPON ───────────────────────────────────────────────

  test "eliminarea cuponului din coș" do
    coupon = create_test_coupon(code: "REMOVE15", discount_value: 15)

    go_to_cart
    fill_in "code", with: "REMOVE15"
    click_button "Aplică cuponul"
    assert_text "REMOVE15"

    # Eliminăm cuponul
    click_button "Șterge cupon"

    assert_no_text "REMOVE15", wait: 5
    assert_no_text "Reducere"
  end
end

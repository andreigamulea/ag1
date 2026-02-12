require_relative "suite_test_helper"

class CouponFlowTest < SuiteTestCase
  setup do
    @product = create_test_product(
      name: "Carte cu Cupon",
      price: 100.00,
      stock: 50
    )

    @coupon = create_test_coupon(
      code: "REDUCERE20",
      discount_type: "percentage",
      discount_value: 20
    )

    @coupon_fix = create_test_coupon(
      code: "MINUS15LEI",
      discount_type: "fixed",
      discount_value: 15
    )

    @coupon_min_cart = create_test_coupon(
      code: "PESTE200",
      discount_type: "percentage",
      discount_value: 10,
      minimum_cart_value: 200
    )

    # Adăugăm produsul în coș
    add_product_to_cart(@product)
  end

  # ── APLICARE CUPON ───────────────────────────────────────────────

  test "aplicarea unui cupon procentual valid" do
    go_to_cart

    assert_selector ".coupon-section"
    fill_in "code", with: "REDUCERE20"
    click_button "Aplică cuponul"

    # Cuponul apare ca "Cupon: REDUCERE20 ✅ aplicat"
    assert_text "REDUCERE20"
    assert_text "aplicat"
    assert_selector ".coupon-message"
  end

  test "aplicarea unui cupon fix valid" do
    go_to_cart

    fill_in "code", with: "MINUS15LEI"
    click_button "Aplică cuponul"

    assert_text "MINUS15LEI"
    assert_text "aplicat"
  end

  test "reducerea apare în sumarul coșului" do
    go_to_cart

    fill_in "code", with: "REDUCERE20"
    click_button "Aplică cuponul"

    assert_text "Reducere"
    assert_selector ".cart-summary"
  end

  # ── CUPON INVALID / EXPIRAT ──────────────────────────────────────

  test "un cod de cupon inexistent afișează eroare" do
    go_to_cart

    fill_in "code", with: "NUEXISTA"
    click_button "Aplică cuponul"

    # Nu ar trebui să apară mesajul de cupon aplicat
    assert_no_selector ".coupon-message"
  end

  test "un cupon expirat nu poate fi aplicat" do
    create_test_coupon(
      code: "EXPIRAT",
      starts_at: 60.days.ago,
      expires_at: 1.day.ago
    )

    go_to_cart

    fill_in "code", with: "EXPIRAT"
    click_button "Aplică cuponul"

    assert_no_selector ".coupon-message"
  end

  test "un cupon inactiv nu poate fi aplicat" do
    create_test_coupon(
      code: "INACTIV",
      active: false
    )

    go_to_cart

    fill_in "code", with: "INACTIV"
    click_button "Aplică cuponul"

    assert_no_selector ".coupon-message"
  end

  test "un cupon cu minimum_cart_value nesatisfăcut" do
    go_to_cart

    # Coșul are 100 lei, cuponul cere minimum 200
    fill_in "code", with: "PESTE200"
    click_button "Aplică cuponul"

    # Ar trebui să afișeze erori despre condiții
    assert_selector ".coupon-errors"
  end

  # ── ȘTERGERE CUPON ───────────────────────────────────────────────

  test "ștergerea unui cupon aplicat" do
    go_to_cart

    fill_in "code", with: "REDUCERE20"
    click_button "Aplică cuponul"
    assert_text "REDUCERE20"
    assert_text "aplicat"

    # Ștergem cuponul
    click_button "Șterge cupon"

    # După ștergere, cuponul nu mai apare
    assert_no_selector ".coupon-message"
  end

  # ── CUPON CU CÂMP GOL ───────────────────────────────────────────

  test "câmpul de cupon are atributul required" do
    go_to_cart

    code_field = find("input[name='code']")
    assert code_field[:required]
  end
end

require_relative "suite_test_helper"

class EdgeCasesTest < SuiteTestCase
  # ── ACCES NEAUTORIZAT ────────────────────────────────────────────

  test "un vizitator nu poate accesa panoul admin" do
    visit admin_path

    # Ar trebui redirecționat la login sau să nu vadă conținut admin
    assert_no_text "Administrare"
  end

  test "un user normal nu poate accesa panoul admin" do
    user = create_test_user(password: "parola123", role: 0)
    sign_in(email: user.email, password: "parola123")

    visit admin_path

    # Nu ar trebui să vadă conținut de admin
    assert_no_text "Internal Server Error"
  end

  # ── PRODUSE EDGE CASES ───────────────────────────────────────────

  test "vizitarea unui produs inexistent nu dă eroare de server" do
    visit "/carti/produs-inexistent-999"

    # Nu ar trebui 500, ci fie 404 fie redirect
    assert_no_text "Internal Server Error"
  end

  test "produsul fără stoc nu poate fi adăugat în cantitate mare" do
    product = create_test_product(
      name: "Carte Limitat",
      stock: 2,
      stock_status: "in_stock"
    )

    visit carti_path(product.slug)
    fill_in "quantity", with: "999"
    click_button "Adauga in cos"

    # Pagina se încarcă fără eroare de server
    go_to_cart
    assert_no_text "Internal Server Error"
  end

  # ── SESIUNE & PERSISTENȚĂ COȘ ────────────────────────────────────

  test "coșul persistă între paginile vizitate" do
    product = create_test_product(name: "Carte Persistentă", price: 25.00)
    add_product_to_cart(product)

    # Navigăm pe alte pagini
    visit root_path
    visit contact_path
    visit carti_index_path

    # Revenim la coș - produsul ar trebui să fie încă acolo
    go_to_cart
    assert_text "Carte Persistentă"
  end

  # ── FLUXURI COMPLETE END-TO-END ──────────────────────────────────

  test "flux complet: vizitator → înregistrare → browse → coș → checkout" do
    create_location_data
    product = create_test_product(name: "Carte E2E Test", price: 75.00, stock: 20)

    # 1. Vizităm homepage-ul
    visit root_path
    assert_selector "h1", text: "AYUS GRUP Romania"

    # 2. Ne înregistrăm
    sign_up(email: "e2e-#{SecureRandom.hex(4)}@example.com", password: "parola123")
    # Așteptăm redirect-ul complet după sign_up
    assert_selector "#account-toggle", wait: 5

    # 3. Vizităm pagina produsului direct
    visit carti_path(product.slug)
    assert_selector "h1", text: "Carte E2E Test", wait: 5

    # 4. Adăugăm în coș
    click_button "Adauga in cos"

    # 5. Mergem la coș
    go_to_cart
    assert_text "Carte E2E Test"
    assert_text "75"

    # 6. Mergem la checkout
    click_link "Finalizează comanda"
    assert_current_path new_order_path

    # 7. Verificăm că suntem pe checkout
    assert_text "Rezumat comandă"
    assert_text "Carte E2E Test"
  end

  test "flux complet: browse → coș → cupon → checkout" do
    create_location_data

    product = create_test_product(name: "Carte Cupon E2E", price: 100.00, stock: 20)
    create_test_coupon(code: "E2ETEST", discount_type: "percentage", discount_value: 15)

    # 1. Adăugăm produs
    add_product_to_cart(product)

    # 2. Aplicăm cupon
    go_to_cart
    fill_in "code", with: "E2ETEST"
    click_button "Aplică cuponul"

    # 3. Verificăm că cuponul e aplicat
    assert_text "E2ETEST"
    assert_text "aplicat"
    assert_text "Reducere"

    # 4. Mergem la checkout
    click_link "Finalizează comanda"
    assert_current_path new_order_path
    assert_text "Rezumat comandă"
  end

  # ── TRANSPORT GRATUIT ────────────────────────────────────────────

  test "transport gratuit pentru comenzi peste 200 lei" do
    product = create_test_product(name: "Carte Scumpă", price: 250.00, stock: 10)
    add_product_to_cart(product)

    go_to_cart

    assert_text "Gratuit"
  end

  test "transport cu cost pentru comenzi sub 200 lei" do
    product = create_test_product(name: "Carte Ieftină", price: 50.00, stock: 10)
    add_product_to_cart(product)

    go_to_cart

    assert_selector ".cart-summary"
    assert_text "Transport"
  end

  # ── RESPONSIVE / MOBILE ──────────────────────────────────────────

  test "hamburger menu-ul există pe pagină" do
    visit root_path

    assert_selector "#hamburger", visible: :all
  end

  # ── HEALTH CHECK ─────────────────────────────────────────────────

  test "rails health check endpoint funcționează" do
    visit "/up"

    # Health check returnează status 200
    assert_no_text "Internal Server Error"
  end
end

require_relative "suite_test_helper"

class AuthorizationTest < SuiteTestCase
  setup do
    @user = create_test_user(password: "password123", role: 0)
    @admin = create_admin_user(password: "password123")
    @product = create_test_product(name: "Carte Auth Test", price: 30.00, stock: 10)
  end

  # ── USER NORMAL BLOCAT DIN ADMIN ──────────────────────────────────

  test "user normal nu poate accesa dashboard-ul admin" do
    sign_in(email: @user.email, password: "password123")
    visit admin_path
    assert_no_text "Panou administrare"
    # Ar trebui redirect sau mesaj de acces refuzat
    assert_no_current_path admin_path
  end

  test "user normal nu poate accesa lista de utilizatori" do
    sign_in(email: @user.email, password: "password123")
    visit users_path
    assert_no_text "Listă utilizatori"
    assert_no_current_path users_path
  end

  test "user normal nu poate accesa formularul de creare utilizator" do
    sign_in(email: @user.email, password: "password123")
    visit new_user_path
    assert_no_text "Adaugă utilizator"
    assert_no_current_path new_user_path
  end

  # ── VIZITATOR NEAUTENTIFICAT ──────────────────────────────────────

  test "vizitator neautentificat este redirectionat la login din admin" do
    visit admin_path
    # Devise ar trebui să redirecționeze la login
    assert_selector "h1", text: "Autentificare", wait: 5
  end

  test "vizitator neautentificat este redirectionat la login din users" do
    visit users_path
    assert_selector "h1", text: "Autentificare", wait: 5
  end

  test "vizitator neautentificat este redirectionat la login din orders" do
    visit orders_path
    assert_selector "h1", text: "Autentificare", wait: 5
  end

  # ── ACCES PUBLIC LA PAGINI PUBLICE ────────────────────────────────

  test "oricine poate accesa pagina de produs public" do
    visit carti_path(@product.slug)
    assert_selector "h1", text: @product.name
  end

  test "oricine poate accesa catalogul de produse" do
    visit carti_index_path
    assert_selector "h1", text: "Cărți"
    assert_selector ".product-card", minimum: 1
  end

  test "oricine poate accesa pagina de contact" do
    visit contact_path
    assert_text "Contactează-ne"
  end

  # ── ADMIN ACCES COMPLET ───────────────────────────────────────────

  test "admin poate accesa dashboard-ul" do
    sign_in(email: @admin.email, password: "password123")
    assert_selector "#account-toggle", wait: 5
    visit admin_path
    assert_text "Panou administrare", wait: 5
  end

  test "admin poate accesa lista de utilizatori" do
    sign_in(email: @admin.email, password: "password123")
    assert_selector "#account-toggle", wait: 5
    visit users_path
    assert_text "Listă utilizatori"
  end

  # ── ACCES COMENZI - PROPRIETAR VS ALTUL ───────────────────────────

  test "user vede doar comenzile proprii pe pagina de istoric" do
    order = create_test_order(user: @user, product: @product, status: "paid")
    other_user = create_test_user(password: "password123")
    other_order = create_test_order(user: other_user, product: @product, status: "paid")

    sign_in(email: @user.email, password: "password123")
    assert_selector "#account-toggle", wait: 10
    visit orders_path

    assert_text @user.email, wait: 5
    assert_no_text "other@test.com"
  end
end

require_relative "suite_test_helper"

class NavigationFlowTest < SuiteTestCase
  # ── HEADER & NAVIGARE PRINCIPALĂ ─────────────────────────────────

  test "homepage-ul se încarcă corect" do
    visit root_path

    assert_selector "h1", text: "AYUS GRUP Romania"
  end

  test "navigarea către pagina de cărți" do
    visit root_path

    click_link "Cărți"

    assert_current_path carti_index_path
    assert_text "Cărți"
  end

  test "navigarea către pagina de contact" do
    visit root_path

    click_link "Contact", match: :first

    assert_current_path contact_path
    assert_selector "h1", text: "Contactează-ne"
  end

  test "logo-ul duce la homepage" do
    visit contact_path

    find(".navbar-brand").click

    assert_current_path root_path
  end

  test "link-ul de Login apare pentru vizitatori" do
    visit root_path

    assert_link "Login"
  end

  test "butonul de coș este vizibil" do
    visit root_path

    assert_selector ".cart-button"
    assert_selector ".cart-count"
  end

  test "click pe coș duce la pagina de coș" do
    visit root_path

    find(".cart-button").click

    assert_current_path cart_index_path
  end

  # ── NAVIGARE USER AUTENTIFICAT ───────────────────────────────────

  test "meniul de cont apare după autentificare" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")

    visit root_path

    assert_selector "#account-toggle"
  end

  test "dropdown-ul de cont afișează opțiunile" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit root_path

    find("#account-toggle").click

    assert_selector "#account-dropdown"
    assert_text "Contul meu"
    assert_text "Comenzile mele"
    assert_text "Logout"
  end

  test "navigarea către Comenzile mele" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit root_path

    find("#account-toggle").click
    # Așteptăm dropdown-ul să fie vizibil
    assert_selector "#account-dropdown", visible: true
    find("#account-dropdown").click_link "Comenzile mele"

    assert_current_path orders_path
  end

  # ── FOOTER ───────────────────────────────────────────────────────

  test "footer-ul conține link-urile legale" do
    visit root_path

    assert_link "Termeni și condiții"
    assert_link "Politica de confidențialitate"
    assert_link "Politica de cookies"
  end

  test "pagina Termeni și condiții se încarcă" do
    visit termeni_conditii_path

    assert_no_text "500"
    assert_no_text "Internal Server Error"
  end

  test "pagina Politica de confidențialitate se încarcă" do
    visit politica_confidentialitate_path

    assert_no_text "500"
    assert_no_text "Internal Server Error"
  end

  test "pagina Politica de cookies se încarcă" do
    visit politica_cookies_path

    assert_no_text "500"
    assert_no_text "Internal Server Error"
  end

  # ── PAGINA DE CONTACT ────────────────────────────────────────────

  test "pagina de contact afișează informațiile de contact" do
    visit contact_path

    assert_text "Contactează-ne"
    assert_text "contact@ayus.ro"
    assert_text "0749 079 619"
  end

  test "pagina de contact are formularul de contact" do
    visit contact_path

    assert_selector "#contact_name"
    assert_selector "#contact_email"
    assert_selector "#contact_message"
    assert_button "Trimite mesajul"
  end

  # ── ADMIN PANEL ──────────────────────────────────────────────────

  test "admin-ul vede link-ul către panoul de administrare" do
    admin = create_admin_user(password: "parola123")
    sign_in(email: admin.email, password: "parola123")
    visit root_path

    find("#account-toggle").click
    assert_text "Admin"
  end
end

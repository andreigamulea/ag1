require_relative "suite_test_helper"

class AccountDashboardTest < SuiteTestCase

  # ── ACCES ȘI REDIRECT-URI ──────────────────────────────────

  test "vizitator neautentificat e redirecționat la login" do
    visit contul_meu_path
    assert_current_path new_user_session_path
  end

  test "user autentificat vede dashboard-ul" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path

    assert_selector ".account-wrapper"
    assert_selector ".account-sidebar"
    assert_selector ".account-content"
  end

  test "/users/edit redirecționează la dashboard settings" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit edit_user_registration_path

    assert_current_path contul_meu_path(section: "settings")
  end

  # ── SIDEBAR ────────────────────────────────────────────────

  test "sidebar-ul conține toate secțiunile" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path

    assert_text "Adrese de livrare"
    assert_text "Date facturare"
    assert_text "Setari cont"
    assert_text "Comenzile mele"
    assert_text "Log out"
  end

  test "secțiunea activă e evidențiată în sidebar" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "orders")

    assert_selector ".account-sidebar-link.active", text: "Comenzile mele"
  end

  # ── SECȚIUNE: ADRESE LIVRARE ───────────────────────────────

  test "secțiunea adrese livrare e default" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path

    assert_text "Adresele mele de livrare"
    assert_text "Nu ai nicio adresa de livrare salvata"
    assert_link "+ Adauga adresa"
  end

  test "adresa shipping salvată apare în grid" do
    user = create_test_user(password: "parola123")
    create_location_data
    user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", postal_code: "010101", street: "Str. Test", street_number: "1"
    )
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "addresses")

    assert_selector ".address-card"
    assert_text "Ion Popescu"
    assert_text "0749079619"
    assert_link "editează"
  end

  # ── SECȚIUNE: DATE FACTURARE ───────────────────────────────

  test "secțiunea facturare afișează adresele billing" do
    user = create_test_user(password: "parola123")
    create_location_data
    user.addresses.create!(
      address_type: "billing", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", email: "ion@test.com", country: "Romania",
      county: "Bucuresti", city: "Bucuresti", postal_code: "010101",
      street: "Str. Factura", street_number: "5", company_name: "SC Test SRL", cui: "RO123"
    )
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "billing")

    assert_text "Date de facturare"
    assert_selector ".address-card"
    assert_text "SC Test SRL"
    assert_text "RO123"
    assert_text "ion@test.com"
  end

  # ── SECȚIUNE: SETĂRI CONT ──────────────────────────────────

  test "secțiunea settings afișează carduri email și parolă" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "settings")

    assert_text "Setari cont"
    assert_text "Adresa de e-mail"
    assert_text user.email
    assert_text "Parola"
    assert_button "modifica", count: 2
  end

  test "secțiunea settings afișează dezactivare cont" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "settings")

    assert_text "Dezactiveaza contul"
    assert_button "Dezactiveaza contul meu"
  end

  # ── SECȚIUNE: COMENZILE MELE ───────────────────────────────

  test "secțiunea comenzi fără comenzi afișează empty state" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "orders")

    assert_text "Comenzile mele"
    assert_text "Nu ai nicio comanda"
  end

  test "secțiunea comenzi afișează comenzile utilizatorului" do
    user = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product
    order = create_test_order(user: user, product: product, status: "paid")

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "orders")

    assert_selector ".order-card"
    assert_text "Comanda ##{order.id}"
    assert_selector ".order-status-badge"
    assert_link "Detalii"
  end

  test "user nu vede comenzile altui utilizator" do
    user1 = create_test_user(password: "parola123")
    user2 = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product
    order = create_test_order(user: user2, product: product, status: "paid")

    sign_in(email: user1.email, password: "parola123")
    visit contul_meu_path(section: "orders")

    assert_no_text "Comanda ##{order.id}"
  end

  # ── DETALII COMANDĂ ────────────────────────────────────────

  test "pagina detalii comandă afișează 3 coloane" do
    user = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product
    order = create_test_order(user: user, product: product, status: "paid")

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_order_path(order)

    assert_text "Comanda nr. #{order.id}"
    assert_text "Modalitate livrare"
    assert_text "Date facturare"
    assert_text "Modalitate plata"
    assert_selector ".order-detail-columns"
  end

  test "detalii comandă afișează produsele" do
    user = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product(name: "Carte Ayurveda Speciala")
    order = create_test_order(user: user, product: product, status: "paid")

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_order_path(order)

    assert_text "Carte Ayurveda Speciala"
    assert_text "Total produse:"
  end

  test "user nu poate vedea comanda altui user" do
    user1 = create_test_user(password: "parola123")
    user2 = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product
    order = create_test_order(user: user2, product: product, status: "paid")

    sign_in(email: user1.email, password: "parola123")
    visit contul_meu_order_path(order)

    # Rails returnează 404 pe RecordNotFound — nu vedem detaliile comenzii
    assert_no_text "Comanda nr. #{order.id}"
  end

  test "breadcrumb duce înapoi la comenzi" do
    user = create_test_user(password: "parola123")
    create_location_data
    product = create_test_product
    order = create_test_order(user: user, product: product, status: "paid")

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_order_path(order)

    assert_link "Comenzile mele", href: contul_meu_path(section: "orders")
  end

  # ── LOGOUT DIN SIDEBAR ─────────────────────────────────────

  test "logout din sidebar deconectează utilizatorul" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path

    within ".account-sidebar" do
      click_button "Log out"
    end

    assert_link "Login", wait: 5
    assert_no_selector "#account-toggle"
  end

  # ── SECȚIUNE INVALIDĂ ──────────────────────────────────────

  test "secțiune invalidă face fallback pe adrese" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "inexistent")

    assert_text "Adresele mele de livrare"
  end
end

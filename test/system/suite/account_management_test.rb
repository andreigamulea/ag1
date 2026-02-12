require_relative "suite_test_helper"

class AccountManagementTest < SuiteTestCase
  # ── EDITARE PROFIL ────────────────────────────────────────────────

  test "user accesează pagina de editare profil" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    assert_selector "#account-toggle", wait: 5

    visit edit_user_registration_path
    assert_text "Editează Contul", wait: 5
    assert_field "user[email]"
  end

  test "user schimbă parola cu succes" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    assert_selector "#account-toggle", wait: 5

    visit edit_user_registration_path
    assert_text "Editează Contul", wait: 5

    fill_in "user[password]", with: "newpassword456", match: :first
    fill_in "user[password_confirmation]", with: "newpassword456"

    # Parola curentă - primul câmp (din formularul de editare, nu cel de dezactivare)
    # Pagina are 2 câmpuri user[current_password]: unul în form-ul de edit, altul în cancel-account
    all(:field, "user[current_password]", visible: true).first.set("password123")
    click_button "Actualizeaza"

    assert_no_text "Internal Server Error"
  end

  test "user NU poate schimba parola fără parola curentă" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    assert_selector "#account-toggle", wait: 5

    visit edit_user_registration_path
    assert_text "Editează Contul", wait: 5
    fill_in "user[password]", with: "newpassword456", match: :first
    fill_in "user[password_confirmation]", with: "newpassword456"
    # Nu completăm current_password
    click_button "Actualizeaza"

    # Ar trebui eroare
    assert_text "Editează Contul"
  end

  # ── DEZACTIVARE CONT ──────────────────────────────────────────────

  test "user dezactivează contul cu parola corectă" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    assert_selector "#account-toggle", wait: 5

    visit edit_user_registration_path
    assert_text "Dezactiveaza contul", wait: 5

    within ".cancel-account-section" do
      fill_in "user[current_password]", with: "password123"
    end

    # Submitem formularul de dezactivare direct via JS (bypass confirm dialog)
    page.execute_script(<<~JS)
      var form = document.querySelector('.cancel-account-section form');
      if (form) { form.submit(); }
    JS

    # Ar trebui delogat și redirecționat
    assert_selector "h1", text: "AYUS GRUP Romania", wait: 5
  end

  test "user NU poate dezactiva contul cu parola greșită" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    assert_selector "#account-toggle", wait: 5

    visit edit_user_registration_path
    assert_text "Dezactiveaza contul", wait: 5

    within ".cancel-account-section" do
      fill_in "user[current_password]", with: "parolagresita"
    end

    # Submitem formularul direct via JS (bypass confirm dialog)
    page.execute_script(<<~JS)
      var form = document.querySelector('.cancel-account-section form');
      if (form) { form.submit(); }
    JS

    # Ar trebui să rămână pe pagina de edit cu eroare
    assert_text "Editează Contul", wait: 5
  end

  # ── USER DEZACTIVAT NU SE POATE AUTENTIFICA ───────────────────────

  test "user dezactivat nu se poate autentifica" do
    user = create_test_user(password: "password123", active: false)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "user[password]", with: "password123"
    click_button "Intră în cont"

    # Nu ar trebui să fie autentificat
    assert_no_selector "#account-toggle"
  end

  # ── REACTIVARE DE CĂTRE ADMIN ─────────────────────────────────────

  test "admin reactivează un cont și userul se poate autentifica din nou" do
    inactive = create_test_user(password: "password123", active: false)

    admin = sign_in_as_admin
    assert_selector "#account-toggle", wait: 5
    visit users_path
    assert_text "Listă utilizatori", wait: 5
    within("tr", text: inactive.email) do
      click_button "Reactivează"
    end

    sign_out
    assert_link "Login", wait: 5

    sign_in(email: inactive.email, password: "password123")
    assert_selector "#account-toggle", wait: 5
  end

  # ── SIGNUP CU EMAIL EXISTENT ──────────────────────────────────────

  test "signup cu email deja existent afișează eroare" do
    user = create_test_user(password: "password123")

    sign_up(email: user.email, password: "password456")

    # Ar trebui eroare de validare
    assert_text "Email"
    assert_no_selector "#account-toggle"
  end

  # ── REDIRECT DUPĂ LOGIN ───────────────────────────────────────────

  test "user este redirecționat la pagina anterioară după login" do
    user = create_test_user(password: "password123")

    visit orders_path
    assert_selector "h1", text: "Autentificare", wait: 5

    fill_in "Email", with: user.email
    fill_in "user[password]", with: "password123"
    click_button "Intră în cont"

    assert_current_path orders_path, wait: 5
  end
end

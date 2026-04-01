require_relative "suite_test_helper"

class AccountManagementTest < SuiteTestCase

  # ── REDIRECT /users/edit → DASHBOARD ─────────────────────────

  test "/users/edit redirecționează la dashboard settings" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit edit_user_registration_path

    assert_current_path contul_meu_path(section: "settings")
  end

  # ── SETĂRI CONT: CARDURI EMAIL/PAROLĂ ────────────────────────

  test "setări cont afișează email-ul curent" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    assert_text "Setari cont"
    assert_text user.email
    assert_button "modifica", count: 2
  end

  test "toggle modifică email afișează formularul" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    # Click pe primul buton "modifica" (email)
    within(".settings-card-display[data-card='email']") do
      click_button "modifica"
    end

    assert_field "user[email]", wait: 3
    assert_field "user[current_password]"
    assert_button "Salveaza"
    assert_button "Anuleaza"
  end

  test "toggle modifică parolă afișează formularul" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    within(".settings-card-display[data-card='password']") do
      click_button "modifica"
    end

    assert_field "user[password]", wait: 3
    assert_field "user[password_confirmation]"
    assert_field "user[current_password]"
  end

  # ── SCHIMBARE EMAIL ──────────────────────────────────────────

  test "schimbare email cu parolă curentă corectă" do
    user = create_test_user(password: "password123")
    new_email = "newemail-#{SecureRandom.hex(4)}@example.com"
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    within(".settings-card-display[data-card='email']") do
      click_button "modifica"
    end

    fill_in "user[email]", with: new_email
    all(:field, "user[current_password]", visible: true).first.set("password123")

    within(".settings-card-form[data-card='email']") do
      click_button "Salveaza noua adresa"
    end

    assert_current_path contul_meu_path(section: "settings"), wait: 5
  end

  test "schimbare email fără parolă curentă eșuează" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    within(".settings-card-display[data-card='email']") do
      click_button "modifica"
    end

    fill_in "user[email]", with: "alt-email@example.com"
    # Nu completăm current_password

    within(".settings-card-form[data-card='email']") do
      click_button "Salveaza noua adresa"
    end

    # Rămâne pe dashboard cu erori
    assert_selector ".account-wrapper", wait: 5
  end

  # ── SCHIMBARE PAROLĂ ─────────────────────────────────────────

  test "schimbare parolă cu date corecte" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    within(".settings-card-display[data-card='password']") do
      click_button "modifica"
    end

    fill_in "user[password]", with: "newpassword456", match: :first
    fill_in "user[password_confirmation]", with: "newpassword456"
    all(:field, "user[current_password]", visible: true).last.set("password123")

    within(".settings-card-form[data-card='password']") do
      click_button "Schimba parola"
    end

    assert_current_path contul_meu_path(section: "settings"), wait: 5
  end

  test "schimbare parolă cu confirmare diferită eșuează" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    within(".settings-card-display[data-card='password']") do
      click_button "modifica"
    end

    fill_in "user[password]", with: "newpass123", match: :first
    fill_in "user[password_confirmation]", with: "altaparola"
    all(:field, "user[current_password]", visible: true).last.set("password123")

    within(".settings-card-form[data-card='password']") do
      click_button "Schimba parola"
    end

    # Rămâne pe dashboard
    assert_selector ".account-wrapper", wait: 5
  end

  # ── DEZACTIVARE CONT ─────────────────────────────────────────

  test "dezactivare cont cu parolă corectă" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    assert_text "Dezactiveaza contul"

    within ".settings-deactivate" do
      fill_in "user[current_password]", with: "password123"
    end

    # Submit direct via JS (bypass turbo_confirm)
    page.execute_script("document.querySelector('.settings-deactivate form').submit()")

    # Delogat și redirecționat
    assert_no_selector "#account-toggle", wait: 5
  end

  test "dezactivare cont cu parolă greșită eșuează" do
    user = create_test_user(password: "password123")
    sign_in(email: user.email, password: "password123")
    visit contul_meu_path(section: "settings")

    within ".settings-deactivate" do
      fill_in "user[current_password]", with: "parolagresita"
    end

    page.execute_script("document.querySelector('.settings-deactivate form').submit()")

    # Rămâne logat, redirecționat la settings cu eroare
    assert_selector ".account-wrapper", wait: 5
    assert_text "Parola curenta este incorecta"
  end

  test "user dezactivat nu se poate autentifica" do
    user = create_test_user(password: "password123", active: false)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "user[password]", with: "password123"
    click_button "Intră în cont"

    assert_no_selector "#account-toggle"
  end

  # ── REACTIVARE DE CĂTRE ADMIN ────────────────────────────────

  test "admin reactivează un cont dezactivat" do
    inactive = create_test_user(password: "password123", active: false)

    admin = sign_in_as_admin
    assert_selector "#account-toggle", wait: 5
    visit users_path
    assert_text inactive.email, wait: 5

    within("tr", text: inactive.email) do
      click_button "Reactivează"
    end

    sign_out
    assert_link "Login", wait: 5

    sign_in(email: inactive.email, password: "password123")
    assert_selector "#account-toggle", wait: 5
  end
end

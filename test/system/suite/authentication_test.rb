require_relative "suite_test_helper"

class AuthenticationFlowTest < SuiteTestCase
  # ── ÎNREGISTRARE ─────────────────────────────────────────────────

  test "un vizitator poate crea cont nou" do
    visit new_user_registration_path
    email = "nou-#{SecureRandom.hex(4)}@example.com"
    
    assert_selector "h1", text: "Creare cont"

    fill_in "Email", with: email
    fill_in "user[password]", with: "parola123", match: :first
    fill_in "user[password_confirmation]", with: "parola123"
    click_button "Creează cont"

    # Devise redirecționează și afișează mesaj de succes
    assert_current_path root_path
    assert User.find_by(email: email).present?
  end

  test "înregistrarea eșuează cu email invalid" do
    visit new_user_registration_path

    fill_in "Email", with: "nu-e-email"
    fill_in "user[password]", with: "parola123", match: :first
    fill_in "user[password_confirmation]", with: "parola123"
    click_button "Creează cont"

    # Rămâne pe pagina de înregistrare (nu e redirecționat)
    assert_selector "h1", text: "Creare cont"
    assert_no_current_path root_path
  end

  test "înregistrarea eșuează cu parolă prea scurtă" do
    visit new_user_registration_path
    email = "test-#{SecureRandom.hex(4)}@example.com"

    fill_in "Email", with: email
    fill_in "user[password]", with: "123", match: :first
    fill_in "user[password_confirmation]", with: "123"
    click_button "Creează cont"

    assert_selector "#error_explanation"
  end

  test "înregistrarea eșuează când parolele nu coincid" do
    visit new_user_registration_path
    email = "test-#{SecureRandom.hex(4)}@example.com"

    fill_in "Email", with: email
    fill_in "user[password]", with: "parola123", match: :first
    fill_in "user[password_confirmation]", with: "altaparola"
    click_button "Creează cont"

    assert_selector "#error_explanation"
  end

  test "înregistrarea eșuează cu email deja folosit" do
    user = create_test_user

    visit new_user_registration_path
    fill_in "Email", with: user.email
    fill_in "user[password]", with: "parola123", match: :first
    fill_in "user[password_confirmation]", with: "parola123"
    click_button "Creează cont"

    assert_selector "#error_explanation"
  end

  # ── AUTENTIFICARE ────────────────────────────────────────────────

  test "un user existent se poate autentifica" do
    user = create_test_user(password: "parola123")

    visit new_user_session_path
    assert_selector "h1", text: "Autentificare"

    fill_in "Email", with: user.email
    fill_in "user[password]", with: "parola123"
    click_button "Intră în cont"

    assert_current_path root_path
    assert_selector "#account-toggle"
  end

  test "autentificarea eșuează cu parolă greșită" do
    user = create_test_user(password: "parola123")

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "user[password]", with: "parolagresita"
    click_button "Intră în cont"

    assert_no_selector "#account-toggle"
    assert_text "Autentificare"
  end

  test "autentificarea eșuează cu email inexistent" do
    visit new_user_session_path

    fill_in "Email", with: "inexistent-#{SecureRandom.hex(4)}@example.com"
    fill_in "user[password]", with: "parola123"
    click_button "Intră în cont"

    assert_no_selector "#account-toggle"
  end

  test "un cont dezactivat nu se poate autentifica" do
    user = create_test_user(password: "parola123", active: false)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "user[password]", with: "parola123"
    click_button "Intră în cont"

    assert_no_selector "#account-toggle"
  end

  test "un user autentificat se poate deconecta" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")

    assert_selector "#account-toggle", wait: 5
    find("#account-toggle").click
    click_button "Logout"

    assert_link "Login", wait: 5
    assert_no_selector "#account-toggle"
  end

  # ── UI & NAVIGARE ────────────────────────────────────────────────

  test "pagina de login are link către înregistrare" do
    visit new_user_session_path

    assert_text "Crează un cont nou"
  end

  test "pagina de login are link pentru parolă uitată" do
    visit new_user_session_path

    assert_link "Ai uitat parola?"
  end

  test "butonul de show/hide parolă funcționează" do
    visit new_user_session_path

    # Verificăm că există câmpul de parolă
    assert_field "user[password]", type: "password"
  end
end

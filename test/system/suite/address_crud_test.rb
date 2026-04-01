require_relative "suite_test_helper"

class AddressCrudTest < SuiteTestCase

  # ── ADĂUGARE ADRESĂ SHIPPING ───────────────────────────────

  test "adaugă adresă de livrare" do
    user = create_test_user(password: "parola123")
    create_location_data
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "addresses")

    click_link "+ Adauga adresa"
    assert_text "Adauga adresa de livrare"

    fill_in "Nume", with: "Popescu"
    fill_in "Prenume", with: "Ion"
    fill_in "Telefon", with: "0749079619"
    fill_in "Cod postal", with: "010101"
    fill_in "Strada", with: "Str. Ostasilor"
    fill_in "Numar", with: "15"

    # Autocomplete județ
    judet_input = find("#address_judet_input")
    judet_input.fill_in with: "Bu"
    sleep 0.5
    if page.has_css?("#address_judet_dropdown .dropdown-item", wait: 2)
      find("#address_judet_dropdown .dropdown-item", text: /Bucuresti/i, match: :first).click
    else
      judet_input.set("Bucuresti")
    end

    # Autocomplete localitate
    sleep 0.3
    localitate_input = find("#address_localitate_input")
    page.execute_script("document.querySelector('#address_localitate_input').disabled = false") if localitate_input.disabled?
    localitate_input.fill_in with: "Bu"
    sleep 0.5
    if page.has_css?("#address_localitate_dropdown .dropdown-item", wait: 2)
      find("#address_localitate_dropdown .dropdown-item", text: /Bucuresti/i, match: :first).click
    else
      localitate_input.set("Bucuresti")
    end

    click_button "Salveaza adresa"

    assert_text "Adresa a fost salvata", wait: 5
    assert_selector ".address-card"
    assert_text "Ion Popescu"
    assert_text "0749079619"
  end

  test "adaugă adresă de livrare cu etichetă și default" do
    user = create_test_user(password: "parola123")
    create_location_data
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "shipping")

    fill_in "Nume", with: "Popescu"
    fill_in "Prenume", with: "Ion"
    fill_in "Telefon", with: "0749079619"
    fill_in "Cod postal", with: "010101"
    fill_in "Strada", with: "Str. Test"
    fill_in "Numar", with: "1"

    # Setăm județ și localitate direct via JS
    page.execute_script("document.querySelector('#address_judet_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('#address_localitate_input').disabled = false")
    page.execute_script("document.querySelector('#address_localitate_input').value = 'Bucuresti'")

    fill_in "Etichetă (optional)", with: "Acasa"
    check "Adresa principala"

    click_button "Salveaza adresa"

    assert_text "Adresa a fost salvata", wait: 5
    assert_text "Acasa"
    assert_text "Adresa principala"
  end

  # ── ADĂUGARE ADRESĂ BILLING ────────────────────────────────

  test "adaugă adresă de facturare cu firmă" do
    user = create_test_user(password: "parola123")
    create_location_data
    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "billing")

    click_link "+ Adauga adresa"
    assert_text "Adauga adresa de facturare"

    fill_in "Nume", with: "Popescu"
    fill_in "Prenume", with: "Ion"
    fill_in "Telefon", with: "0749079619"
    fill_in "Companie (optional)", with: "SC Ayus SRL"
    fill_in "CUI (optional)", with: "RO12345678"
    fill_in "Email", with: "firma@ayus.ro"
    fill_in "Cod postal", with: "010101"
    fill_in "Strada", with: "Str. Firmei"
    fill_in "Numar", with: "10"

    page.execute_script("document.querySelector('#address_judet_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('#address_localitate_input').disabled = false")
    page.execute_script("document.querySelector('#address_localitate_input').value = 'Bucuresti'")

    click_button "Salveaza adresa"

    assert_current_path contul_meu_path(section: "billing"), wait: 5
    assert_text "SC Ayus SRL"
    assert_text "RO12345678"
    assert_text "firma@ayus.ro"
  end

  test "adresa billing fără email eșuează" do
    user = create_test_user(password: "parola123")
    create_location_data
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "billing")

    fill_in "Nume", with: "Popescu"
    fill_in "Prenume", with: "Ion"
    fill_in "Telefon", with: "0749079619"
    fill_in "Cod postal", with: "010101"
    fill_in "Strada", with: "Str. Test"
    fill_in "Numar", with: "1"

    page.execute_script("document.querySelector('#address_judet_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('#address_localitate_input').disabled = false")
    page.execute_script("document.querySelector('#address_localitate_input').value = 'Bucuresti'")

    # Nu completăm email-ul — bypass HTML5 required și submit
    page.execute_script("document.querySelector('.address-form').noValidate = true")
    click_button "Salveaza adresa"

    assert_selector ".address-form-errors", wait: 5
  end

  # ── EDITARE ADRESĂ ─────────────────────────────────────────

  test "editare adresă existentă" do
    user = create_test_user(password: "parola123")
    create_location_data
    address = user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", postal_code: "010101", street: "Str. Veche", street_number: "1"
    )

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "addresses")
    click_link "editează"

    assert_text "Editare adresa de livrare"
    fill_in "Strada", with: "Str. Noua"
    fill_in "Numar", with: "99"
    click_button "Salveaza adresa"

    assert_text "Adresa a fost actualizata", wait: 5
    assert_text "Str. Noua"
  end

  # ── ȘTERGERE ADRESĂ ────────────────────────────────────────

  test "ștergere adresă cu confirmare" do
    user = create_test_user(password: "parola123")
    create_location_data
    user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", postal_code: "010101", street: "Str. Stearsa", street_number: "1"
    )

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "addresses")

    assert_selector ".address-card"

    # Turbo confirm — bypass dialog și submit direct
    page.execute_script("document.querySelector('.address-action-delete').closest('form').submit()")

    assert_text "Adresa a fost stearsa", wait: 5
    assert_no_selector ".address-card"
    assert_text "Nu ai nicio adresa"
  end

  # ── SECURITATE ─────────────────────────────────────────────

  test "user nu poate edita adresa altui user" do
    user1 = create_test_user(password: "parola123")
    user2 = create_test_user(password: "parola123")
    create_location_data

    address = user2.addresses.create!(
      address_type: "shipping", first_name: "Alt", last_name: "User",
      phone: "0722000000", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", postal_code: "020202", street: "Str. Alta", street_number: "2"
    )

    sign_in(email: user1.email, password: "parola123")
    visit edit_address_path(address)

    # Rails returnează 404 pe RecordNotFound
    assert_no_text "Editare adresa"
  end

  # ── BUTON ÎNAPOI ───────────────────────────────────────────

  test "butonul Înapoi duce la secțiunea corectă" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "billing")

    click_link "Inapoi"
    assert_current_path contul_meu_path(section: "billing")
  end

  test "butonul Înapoi de la shipping duce la addresses" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "shipping")

    click_link "Inapoi"
    assert_current_path contul_meu_path(section: "addresses")
  end

  # ── VALIDĂRI FORMULAR ──────────────────────────────────────

  test "salvare adresă fără câmpuri obligatorii afișează erori" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "shipping")

    # Bypass HTML5 required și submit direct via JS
    page.execute_script("document.querySelector('.address-form').noValidate = true")
    click_button "Salveaza adresa"

    assert_selector ".address-form-errors", wait: 5
  end

  test "adresă shipping cu telefon invalid eșuează" do
    user = create_test_user(password: "parola123")
    create_location_data
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "shipping")

    fill_in "Nume", with: "Popescu"
    fill_in "Prenume", with: "Ion"
    fill_in "Telefon", with: "abc invalid"
    fill_in "Strada", with: "Str. Test"
    fill_in "Numar", with: "1"

    page.execute_script("document.querySelector('#address_judet_input').value = 'Bucuresti'")
    page.execute_script("document.querySelector('#address_localitate_input').disabled = false")
    page.execute_script("document.querySelector('#address_localitate_input').value = 'Bucuresti'")

    # Bypass HTML5 pattern validation pe telefon
    page.execute_script("document.querySelector('.address-form').noValidate = true")
    click_button "Salveaza adresa"

    assert_selector ".address-form-errors", wait: 5
  end

  test "formular billing afișează câmpuri CUI și email" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "billing")

    assert_field "address[cui]"
    assert_field "address[email]"
  end

  test "formular shipping nu afișează câmpuri CUI și email" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "shipping")

    assert_no_field "address[cui]"
    assert_no_field "address[email]"
  end

  test "type invalid în URL face fallback pe shipping" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "invalid")

    assert_text "Adauga adresa de livrare"
  end

  # ── STELUȚE CÂMPURI OBLIGATORII ────────────────────────────

  test "câmpurile obligatorii au steluță roșie" do
    user = create_test_user(password: "parola123")
    sign_in(email: user.email, password: "parola123")
    visit new_address_path(type: "shipping")

    assert_selector ".required", minimum: 8  # Nume, Prenume, Telefon, Tara, Judet, Localitate, Strada, Numar
  end

  # ── ADRESĂ DEFAULT ─────────────────────────────────────────

  test "adresa default apare cu badge" do
    user = create_test_user(password: "parola123")
    create_location_data
    user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", street: "Str. Default", street_number: "1", default: true
    )

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "addresses")

    assert_text "Adresa principala"
  end

  test "adresa cu etichetă afișează label-ul" do
    user = create_test_user(password: "parola123")
    create_location_data
    user.addresses.create!(
      address_type: "shipping", first_name: "Ion", last_name: "Popescu",
      phone: "0749079619", country: "Romania", county: "Bucuresti",
      city: "Bucuresti", street: "Str. Acasa", street_number: "1", label: "Acasa"
    )

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "addresses")

    assert_text "Acasa"
  end

  # ── MULTIPLE ADRESE ────────────────────────────────────────

  test "mai multe adrese apar în grid" do
    user = create_test_user(password: "parola123")
    create_location_data

    3.times do |i|
      user.addresses.create!(
        address_type: "shipping", first_name: "User#{i}", last_name: "Test",
        phone: "074900000#{i}", country: "Romania", county: "Bucuresti",
        city: "Bucuresti", street: "Str. #{i}", street_number: "#{i + 1}"
      )
    end

    sign_in(email: user.email, password: "parola123")
    visit contul_meu_path(section: "addresses")

    assert_selector ".address-card", count: 3
  end
end

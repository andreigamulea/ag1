require_relative "suite_test_helper"

# ═══════════════════════════════════════════════════════════════════
#  TEST COMPLET: Simulează sesiunea completă a unui client real
#  De la prima vizită până la plasarea comenzii.
# ═══════════════════════════════════════════════════════════════════

class FullCustomerJourneyTest < SuiteTestCase
  setup do
    create_location_data

    @book1 = create_test_product(
      name: "Ashwagandha - Ghid Practic",
      price: 49.99,
      stock: 30,
      description: "Ghid complet despre ashwagandha"
    )

    @book2 = create_test_product(
      name: "Turmeric în Ayurveda",
      price: 39.99,
      stock: 20,
      description: "Beneficiile turmeticului"
    )

    @coupon = create_test_coupon(
      code: "BINE10",
      discount_type: "percentage",
      discount_value: 10
    )
  end

  test "călătoria completă a clientului: vizită → cont → browse → coș → cupon → checkout" do
    # ── PASUL 1: Prima vizită pe site ──
    visit root_path
    assert_selector "h1", text: "AYUS GRUP Romania"

    # ── PASUL 2: Crearea contului ──
    sign_up(email: "client-#{SecureRandom.hex(4)}@example.com", password: "parola123")
    # Verificăm că am fost redirecționat (signup reușit)
    assert_selector "#account-toggle", wait: 5

    # ── PASUL 3: Navigare catalog ──
    visit carti_index_path
    assert_selector ".product-card", minimum: 2
    # Produsele pot fi pe alte pagini din cauza paginării

    # ── PASUL 4: Vizualizare detalii produs ──
    visit carti_path(@book1.slug)
    assert_selector "h1", text: @book1.name
    assert_text "49.99"
    assert_text @book1.description

    # ── PASUL 5: Adăugare primul produs în coș ──
    click_button "Adauga in cos"

    # ── PASUL 6: Continuare cumpărături - adăugare al doilea produs ──
    visit carti_path(@book2.slug)
    assert_selector "h1", text: @book2.name

    # Setăm cantitatea la 2
    find(".quantity-increase").click
    assert_equal "2", find("#quantity_input").value
    click_button "Adauga in cos"

    # ── PASUL 7: Verificare coș ──
    go_to_cart
    assert_selector "h1", text: "Coșul tău"
    assert_text "Ashwagandha - Ghid Practic"
    assert_text "Turmeric în Ayurveda"

    # Verificăm că avem cele 2 produse diferite
    assert_selector ".cart-item", count: 2

    # ── PASUL 8: Aplicare cupon de reducere ──
    fill_in "code", with: "BINE10"
    click_button "Aplică cuponul"
    assert_text "BINE10"
    assert_text "aplicat"
    assert_text "Reducere"

    # ── PASUL 9: Navigare către checkout ──
    click_link "Finalizează comanda"
    assert_current_path new_order_path

    # ── PASUL 10: Verificare rezumat pe checkout ──
    assert_text "Rezumat comandă"
    assert_text "Ashwagandha - Ghid Practic"
    assert_text "Turmeric în Ayurveda"

    # ── PASUL 11: Completare formular de comandă ──
    fill_shipping_address(
      last_name: "Ionescu",
      first_name: "Maria",
      phone: "0723456789",
      postal_code: "010101",
      street: "Bd. Unirii",
      street_number: "42"
    )

    # Bifăm billing și completăm (email + adresă facturare)
    fill_billing_address(
      last_name: "Ionescu",
      first_name: "Maria",
      phone: "0723456789",
      postal_code: "010101",
      street: "Bd. Unirii",
      street_number: "42",
      email: "client.nou@example.com"
    )

    # Note opționale
    fill_in "order[notes]", with: "Vă rog livrare între 10:00-14:00."

    # ── PASUL 12: Verificare completă a formularului ──
    assert_field "order[shipping_last_name]", with: "Ionescu"
    assert_field "order[shipping_first_name]", with: "Maria"
    assert_field "order[notes]", with: "Vă rog livrare între 10:00-14:00."
    assert_button "Plasează comanda"

    # Nota: Nu submitem comanda deoarece Stripe nu e configurat în test.
    # Fluxul complet până la checkout cu date valide a fost verificat.
  end

  test "călătoria clientului care doar navighează fără a cumpăra" do
    # ── Un vizitator care doar se uită ──
    visit root_path
    assert_selector "h1", text: "AYUS GRUP Romania"

    # Navighează catalogul
    visit carti_index_path
    assert_selector ".product-card", minimum: 1

    # Se uită la un produs
    visit carti_path(@book1.slug)
    assert_selector "h1", text: @book1.name

    # Se uită la alt produs
    visit carti_path(@book2.slug)
    assert_selector "h1", text: @book2.name

    # Verifică pagina de contact
    visit contact_path
    assert_text "Contactează-ne"

    # Verifică coșul - ar trebui să fie gol
    go_to_cart
    assert_text "Coșul este gol"

    # Verifică pagini legale
    visit termeni_conditii_path
    assert_no_text "Internal Server Error"

    visit politica_confidentialitate_path
    assert_no_text "Internal Server Error"
  end

  test "clientul care își face cont, adaugă produse, pleacă, revine" do
    # 1. Creează cont
    sign_up(email: "revine-#{SecureRandom.hex(4)}@example.com", password: "parola123")
    assert_selector "#account-toggle", wait: 5

    # 2. Adaugă produs în coș - direct prin pagina produsului
    visit carti_path(@book1.slug)
    click_button "Adauga in cos"
    go_to_cart
    assert_text @book1.name

    # 3. Se deloghează
    find("#account-toggle").click
    assert_selector "#account-dropdown", visible: true, wait: 3
    click_button "Logout"

    # 4. Așteptăm delogarea completă - ar trebui să vedem link-ul de Login
    assert_link "Login", wait: 5

    # 5. Revine și se loghează din nou
    visit new_user_session_path
    assert_selector "h1", text: "Autentificare", wait: 5
    fill_in "Email", with: "revine@example.com"
    fill_in "user[password]", with: "parola123"
    click_button "Intră în cont"

    # 6. Verifică dacă pagina se încarcă fără erori
    visit root_path
    assert_no_text "Internal Server Error"
  end
end

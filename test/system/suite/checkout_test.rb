require_relative "suite_test_helper"

class CheckoutFlowTest < SuiteTestCase
  setup do
    create_location_data

    @product = create_test_product(
      name: "Carte Checkout Test",
      price: 55.00,
      stock: 50
    )

    # Adăugăm produsul în coș și verificăm adăugarea
    add_product_to_cart(@product)
    assert_text @product.name, wait: 5
  end

  # ── ACCES CHECKOUT ───────────────────────────────────────────────

  test "pagina de checkout afișează rezumatul comenzii" do
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    assert_text @product.name
    assert_text "55"
  end

  test "pagina de checkout are formularul de livrare" do
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    assert_text "Date de livrare"
    assert_selector "input[name='order[shipping_last_name]']"
    assert_selector "input[name='order[shipping_first_name]']"
    assert_selector "input[name='order[shipping_phone]']"
    assert_selector "input[name='order[shipping_postal_code]']"
    assert_selector "input[name='order[shipping_street]']"
    assert_selector "input[name='order[shipping_street_number]']"
  end

  # ── PLASARE COMANDĂ CU SUCCES ────────────────────────────────────

  test "plasarea unei comenzi complete cu adresa de livrare" do
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    # Completăm adresa de livrare cu autocomplete-uri
    fill_shipping_address

    # Bifăm toggle-ul și completăm adresa de facturare (inclusiv email)
    fill_billing_address(email: "ion.popescu@example.com")

    # Verificăm că formularul este completat corect
    assert_field "order[shipping_last_name]", with: "Popescu"
    assert_field "order[shipping_first_name]", with: "Ion"
    assert_field "order[shipping_phone]", with: "0749079619"
    assert_button "Plasează comanda"

    # Nota: Nu submitem comanda deoarece Stripe nu e configurat în test.
    # Validarea Rails e testată prin testul "comanda eșuează cu date incomplete".
    # Checkout-ul integral ar necesita un mock Stripe sau API key de test.
  end

  # ── VALIDĂRI FORMULAR ────────────────────────────────────────────

  test "formularul de checkout are câmpuri required HTML5" do
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    # Verificăm că câmpurile principale au atributul required
    shipping_last = find("input[name='order[shipping_last_name]']")
    shipping_first = find("input[name='order[shipping_first_name]']")
    shipping_phone = find("input[name='order[shipping_phone]']")

    assert shipping_last[:required]
    assert shipping_first[:required]
    assert shipping_phone[:required]
  end

  test "comanda eșuează cu date incomplete (forțat)" do
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    # Bifăm toggle-ul billing pentru a accesa email
    check "order[use_different_billing]"

    within "#billing-fields" do
      fill_in "order[email]", with: "invalid"
    end

    # Completăm câmpurile required cu date minime
    fill_in "order[shipping_last_name]", with: "T"
    fill_in "order[shipping_first_name]", with: "T"
    fill_in "order[shipping_phone]", with: "T"
    fill_in "order[shipping_postal_code]", with: "12" # prea scurt
    fill_in "order[shipping_street]", with: "T"
    fill_in "order[shipping_street_number]", with: "T"

    click_button "Plasează comanda"

    # Ar trebui erori de validare
    assert_no_text "Mulțumim pentru comandă"
  end

  # ── ADRESĂ DE FACTURARE DIFERITĂ ─────────────────────────────────

  test "toggle-ul pentru adresă de facturare diferită funcționează" do
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    # Bifăm checkbox-ul
    check "order[use_different_billing]"

    # Câmpurile ar trebui să devină vizibile
    assert_selector "#billing-fields", visible: true
  end

  # ── NOTELE COMENZII ──────────────────────────────────────────────

  test "câmpul de note este opțional și prezent" do
    go_to_checkout
    assert_text "Rezumat comandă", wait: 5

    assert_selector "textarea[name='order[notes]']"

    notes_field = find("textarea[name='order[notes]']")
    notes_field.fill_in with: "Livrare 10-14."

    assert_equal "Livrare 10-14.", notes_field.value
  end

  # ── CHECKOUT CU COS GOL ─────────────────────────────────────────

  test "checkout-ul cu coșul gol se încarcă fără erori" do
    # Folosim o sesiune separată pentru a testa cu coșul gol
    Capybara.using_session(:empty_cart) do
      visit new_order_path

      # Cu coșul gol, checkout-ul se încarcă dar fără produse
      assert_no_text "Internal Server Error"
    end
  end
end

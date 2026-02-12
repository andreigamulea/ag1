require "test_helper"
require_relative "suite_test_helper"

class ProductVariantsUITest < SuiteTestCase
  setup do
    @admin = create_admin_user(password: "password123")
    sign_in(email: @admin.email, password: "password123")
  end

  # ══════════════════════════════════════════════════════════════════════
  #  TESTE UI - COMPORTAMENT VIZUAL ȘI INTERACȚIUNI
  # ══════════════════════════════════════════════════════════════════════

  test "checkbox 'Are variante?' este prezent și funcțional" do
    visit new_product_path

    # Verificăm că checkbox-ul există
    assert_field "has_variants", type: "checkbox"

    # Inițial este debifat
    assert_unchecked_field "has_variants"
  end

  test "bifând 'Are variante?' secțiunea de variante devine vizibilă" do
    visit new_product_path

    # Inițial secțiunea e ascunsă
    assert_selector "#section-variants", visible: :hidden

    # Bifăm checkbox-ul
    check "has_variants"

    # Secțiunea devine vizibilă
    assert_selector "#section-variants", visible: :visible, wait: 2
    assert_selector "#btn-add-variant", visible: :visible
    assert_selector ".variants-table", visible: :visible
  end

  test "debifând 'Are variante?' secțiunea de variante dispare" do
    visit new_product_path

    # Bifăm pentru a face secțiunea vizibilă
    check "has_variants"
    assert_selector "#section-variants", visible: :visible, wait: 2

    # Debifăm
    uncheck "has_variants"

    # Secțiunea devine ascunsă
    assert_selector "#section-variants", visible: :hidden, wait: 2
  end

  test "tabelul de variante are structura corectă" do
    visit new_product_path
    check "has_variants"

    # Verificăm că tabelul are toate coloanele necesare
    within ".variants-table" do
      assert_text "Imagine"
      assert_text "SKU"
      assert_text "Pret"
      assert_text "Stoc"
      assert_text "TVA"
      assert_text "Status"
      assert_text "Optiuni"
      assert_text "Sursa"
    end
  end

  test "butonul 'Adaugă variantă' este prezent și funcțional" do
    visit new_product_path
    check "has_variants"

    # Verificăm că butonul există
    assert_button "Adauga varianta"

    # Număr inițial de rânduri
    initial_rows = all(".variant-row").count

    # Click pe buton
    find("#btn-add-variant").click

    # Verificăm că s-a adăugat un rând nou
    assert_equal initial_rows + 1, all(".variant-row").count, wait: 2
  end

  test "câmpurile variantei au clasele CSS corecte pentru JavaScript" do
    visit new_product_path
    check "has_variants"

    within first(".variant-row") do
      # Verificăm că toate câmpurile au clasele corecte
      assert_selector ".variant-sku"
      assert_selector ".variant-price"
      assert_selector ".variant-stock"
      assert_selector ".variant-vat"
      assert_selector ".variant-status"
    end
  end

  test "varianta nouă are buton de ștergere" do
    visit new_product_path
    check "has_variants"

    within first(".variant-row") do
      # Verificăm că butonul de ștergere există
      assert_selector ".btn-remove-variant"
    end
  end

  test "în pagina de edit checkbox 'Are variante?' reflectă starea corectă" do
    # Produs fără variante
    product_without_variants = create_test_product(
      name: "Produs Fără Variante #{SecureRandom.hex(4)}"
    )

    visit edit_product_path(product_without_variants)
    assert_unchecked_field "has_variants"

    # Produs cu variante
    product_with_variants = create_test_product(
      name: "Produs Cu Variante #{SecureRandom.hex(4)}"
    )
    create_test_variant(
      product: product_with_variants,
      overrides: { sku: "TEST-#{SecureRandom.hex(2)}", price: 29.99, vat_rate: 19.0 }
    )

    visit edit_product_path(product_with_variants)
    assert_checked_field "has_variants"
  end

  test "variantele existente se afișează în tabelul de edit" do
    product = create_test_product(name: "Carte Cu 2 Variante #{SecureRandom.hex(4)}")

    v1 = create_test_variant(
      product: product,
      overrides: { sku: "VAR-1-#{SecureRandom.hex(2)}", price: 39.99, vat_rate: 19.0 }
    )

    v2 = create_test_variant(
      product: product,
      overrides: {
        sku: "VAR-2-#{SecureRandom.hex(2)}",
        price: 49.99,
        vat_rate: 9.0,
        status: 1 # inactive
      }
    )

    visit edit_product_path(product)

    # Verificăm că ambele variante apar în tabel
    assert_text v1.sku
    assert_text v2.sku
    assert_equal 2, all(".variant-row").count
  end

  test "zona de upload imagini este prezentă pentru fiecare variantă" do
    visit new_product_path
    check "has_variants"

    within first(".variant-row") do
      # Verificăm că există input file pentru imagini
      assert_selector "input.variant-image-input[type='file']", visible: :all

      # Verificăm butonul de adăugare imagini
      assert_selector ".variant-add-img-btn"

      # Verificăm container-ul pentru galerie
      assert_selector ".variant-image-gallery"
    end
  end
end

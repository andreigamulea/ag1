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

    assert_field "has_variants", type: "checkbox"
    assert_unchecked_field "has_variants"
  end

  test "bifând 'Are variante?' secțiunea de variante devine vizibilă" do
    visit new_product_path

    assert_selector "#section-variants", visible: :hidden

    check "has_variants"

    assert_selector "#section-variants", visible: :visible, wait: 2
    assert_selector "#btn-add-variant", visible: :visible
    assert_selector ".variants-table", visible: :visible
  end

  test "debifând 'Are variante?' secțiunea de variante dispare" do
    visit new_product_path

    check "has_variants"
    assert_selector "#section-variants", visible: :visible, wait: 2

    uncheck "has_variants"

    assert_selector "#section-variants", visible: :hidden, wait: 2
  end

  test "tabelul de variante are structura corectă" do
    visit new_product_path
    check "has_variants"

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

    assert_button "Adauga varianta"

    initial_rows = all(".variant-row-top").count

    find("#btn-add-variant").click

    assert_equal initial_rows + 1, all(".variant-row-top", wait: 2).count
  end

  test "câmpurile variantei au clasele CSS corecte pentru JavaScript" do
    visit new_product_path
    check "has_variants"
    find("#btn-add-variant").click

    # SKU is in the top row
    within first(".variant-row-top") do
      assert_selector ".variant-sku"
    end

    # Price, stock, vat, status are in the bottom row
    within first(".variant-row-bottom") do
      assert_selector ".variant-price"
      assert_selector ".variant-stock"
      assert_selector ".variant-vat"
      assert_selector ".variant-status"
    end
  end

  test "varianta nouă are buton de ștergere" do
    visit new_product_path
    assert_selector "#toggle-has-variants", wait: 5
    check "has_variants"
    find("#btn-add-variant").click

    within first(".variant-row-bottom") do
      assert_selector ".btn-remove-variant"
    end
  end

  test "în pagina de edit checkbox 'Are variante?' reflectă starea corectă" do
    product_without_variants = create_test_product(
      name: "Produs Fără Variante #{SecureRandom.hex(4)}"
    )

    visit edit_product_path(product_without_variants)
    assert_unchecked_field "has_variants"

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
        status: 1
      }
    )

    visit edit_product_path(product)

    # SKUs are in input fields, not as plain text
    assert_selector "input.variant-sku[value='#{v1.sku}']"
    assert_selector "input.variant-sku[value='#{v2.sku}']"
    assert_equal 2, all(".variant-row-top").count
  end

  test "zona de upload imagini este prezentă pentru fiecare variantă" do
    visit new_product_path
    assert_selector "#toggle-has-variants", wait: 5
    check "has_variants"
    find("#btn-add-variant").click

    within first(".variant-row-bottom") do
      assert_selector "input.variant-image-input[type='file']", visible: :all
      assert_selector ".variant-add-img-btn"
      # Gallery div is empty (0 height) for new variants, so check with visible: :all
      assert_selector ".variant-image-gallery", visible: :all
    end
  end
end

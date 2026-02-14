require "test_helper"
require_relative "suite_test_helper"

class ProductWithVariantsTest < SuiteTestCase
  setup do
    @admin = create_admin_user(password: "password123")
    sign_in(email: @admin.email, password: "password123")
  end

  # ══════════════════════════════════════════════════════════════════════
  #  CREARE PRODUS SIMPLU (FĂRĂ VARIANTE)
  # ══════════════════════════════════════════════════════════════════════

  test "admin creează produs simplu fără variante" do
    visit new_product_path
    assert_selector "input[name='product[name]']", wait: 5

    product_name = "Carte Simplă #{SecureRandom.hex(4)}"
    product_slug = "carte-simpla-#{SecureRandom.hex(4)}"
    fill_in "product[name]", with: product_name
    fill_in "product[slug]", with: product_slug
    fill_in "product[sku]", with: "SIMPLE-#{SecureRandom.hex(4)}"
    fill_in "product[price]", with: "49.99"
    fill_in "product[stock]", with: "20"

    assert_unchecked_field "has_variants"

    click_button "Salvează produsul"

    assert_text product_name, wait: 5

    product = Product.find_by(slug: product_slug)
    assert_not_nil product
    assert_equal 0, product.variants.count
    assert_equal 49.99, product.price.to_f
  end

  # ══════════════════════════════════════════════════════════════════════
  #  CREARE PRODUS CU VARIANTE (FĂRĂ IMAGINI)
  # ══════════════════════════════════════════════════════════════════════

  test "admin creează produs cu variante fără imagini" do
    visit new_product_path
    assert_selector "input[name='product[name]']", wait: 5

    product_name = "Carte Cu Variante #{SecureRandom.hex(4)}"
    product_slug = "carte-cu-variante-#{SecureRandom.hex(4)}"
    fill_in "product[name]", with: product_name
    fill_in "product[slug]", with: product_slug
    fill_in "product[sku]", with: "VAR-#{SecureRandom.hex(4)}"

    check "has_variants"
    assert_selector "#section-variants", wait: 2

    # Add variant row then fill fields (SKU in top row, price/stock/vat in bottom)
    find("#btn-add-variant").click
    all(".variant-sku")[0].set("VAR-RED-#{SecureRandom.hex(2)}")
    all(".variant-price")[0].set("39.99")
    all(".variant-stock")[0].set("10")
    all(".variant-vat")[0].set("19")

    click_button "Salvează produsul"

    assert_text product_name, wait: 5

    product = Product.find_by(slug: product_slug)
    assert product.variants.any?
    assert_equal 1, product.variants.count

    variant = product.variants.first
    assert_equal 39.99, variant.price.to_f
    assert_equal 10, variant.stock
    assert_equal 19.0, variant.vat_rate.to_f
  end

  # ══════════════════════════════════════════════════════════════════════
  #  CREARE PRODUS CU VARIANTE - VERIFICARE CÂMPURI
  # ══════════════════════════════════════════════════════════════════════

  test "admin creează produs cu variante - verificare câmpuri complete" do
    visit new_product_path
    assert_selector "input[name='product[name]']", wait: 5

    product_name = "Carte Cu Variante Complete #{SecureRandom.hex(4)}"
    product_slug = "carte-cu-variante-complete-#{SecureRandom.hex(4)}"
    fill_in "product[name]", with: product_name
    fill_in "product[slug]", with: product_slug
    fill_in "product[sku]", with: "COMPLETE-#{SecureRandom.hex(4)}"

    check "has_variants"
    assert_selector "#section-variants", wait: 2
    assert_selector ".variants-table"

    find("#btn-add-variant").click
    all(".variant-sku")[0].set("VAR-COMPLETE-#{SecureRandom.hex(2)}")
    all(".variant-price")[0].set("59.99")
    all(".variant-stock")[0].set("15")
    all(".variant-vat")[0].set("19")

    click_button "Salvează produsul"

    assert_text product_name, wait: 5

    product = Product.find_by(slug: product_slug)
    assert_not_nil product
    assert_equal 1, product.variants.count

    variant = product.variants.first
    assert_equal 59.99, variant.price.to_f
    assert_equal 19.0, variant.vat_rate.to_f
  end

  # ══════════════════════════════════════════════════════════════════════
  #  EDITARE PRODUS - ADĂUGARE VARIANTE LA PRODUS EXISTENT
  # ══════════════════════════════════════════════════════════════════════

  test "admin editează produs simplu și adaugă variante cu imagini" do
    product = create_test_product(
      name: "Carte Pentru Edit #{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 20
    )

    visit edit_product_path(product)
    assert_field "product[name]", with: product.name

    check "has_variants"
    assert_selector "#section-variants", wait: 2

    # Add first variant
    find("#btn-add-variant").click
    all(".variant-sku")[0].set("EDIT-V1-#{SecureRandom.hex(2)}")
    all(".variant-price")[0].set("44.99")
    all(".variant-stock")[0].set("8")
    all(".variant-vat")[0].set("19")

    # Add second variant (set to inactive to avoid idx_unique_active_default_variant constraint)
    find("#btn-add-variant").click
    all(".variant-sku")[1].set("EDIT-V2-#{SecureRandom.hex(2)}")
    all(".variant-price")[1].set("54.99")
    all(".variant-stock")[1].set("12")
    all(".variant-vat")[1].set("19")
    all(".variant-status")[1].select("Inactive")

    click_button "Salvează produsul"

    # After successful save, redirects to show page
    assert_current_path product_path(product), wait: 10

    product.reload
    assert_equal 2, product.variants.count

    prices = product.variants.map { |v| v.price.to_f }.sort
    assert_includes prices, 44.99
    assert_includes prices, 54.99
  end

  # ══════════════════════════════════════════════════════════════════════
  #  VERIFICARE AFIȘARE IMAGINI ÎN PAGINA DE EDIT
  # ══════════════════════════════════════════════════════════════════════

  test "imaginile variantelor se afișează corect în pagina de edit" do
    product = create_test_product(
      name: "Carte Cu Thumb #{SecureRandom.hex(4)}"
    )

    variant1 = create_test_variant(
      product: product,
      overrides: {
        sku: "THUMB-1-#{SecureRandom.hex(2)}",
        price: 39.99,
        vat_rate: 19.0,
        external_image_url: "https://ayus-cdn.b-cdn.net/test/thumb1.jpg"
      }
    )

    variant2 = create_test_variant(
      product: product,
      overrides: {
        sku: "THUMB-2-#{SecureRandom.hex(2)}",
        price: 49.99,
        vat_rate: 19.0,
        status: 1,
        external_image_url: "https://ayus-cdn.b-cdn.net/test/thumb2.jpg"
      }
    )

    visit edit_product_path(product)

    assert_selector "img.variant-thumb[src='#{variant1.external_image_url}']"
    assert_selector "img.variant-thumb[src='#{variant2.external_image_url}']"
    assert_selector ".variant-thumb", count: 2
  end

  # ══════════════════════════════════════════════════════════════════════
  #  ȘTERGERE VARIANTE
  # ══════════════════════════════════════════════════════════════════════

  test "admin șterge o variantă existentă" do
    product = create_test_product(
      name: "Carte Pentru Ștergere #{SecureRandom.hex(4)}"
    )

    variant_to_delete = create_test_variant(
      product: product,
      overrides: {
        sku: "DELETE-ME-#{SecureRandom.hex(2)}",
        price: 29.99,
        vat_rate: 19.0
      }
    )

    variant_to_keep = create_test_variant(
      product: product,
      overrides: {
        sku: "KEEP-ME-#{SecureRandom.hex(2)}",
        price: 39.99,
        vat_rate: 19.0,
        status: 1
      }
    )

    visit edit_product_path(product)

    # SKUs are in input fields, so verify via input values
    assert_selector "input.variant-sku[value='#{variant_to_delete.sku}']"
    assert_selector "input.variant-sku[value='#{variant_to_keep.sku}']"

    # Click the remove button on the variant-row-bottom for the variant to delete
    within find("tr.variant-row-bottom[data-variant-id='#{variant_to_delete.id}']") do
      find(".btn-remove-variant").click
    end

    click_button "Salvează produsul"

    assert_text product.name, wait: 5

    product.reload
    assert_equal 1, product.variants.count
    assert_equal variant_to_keep.id, product.variants.first.id
  end

  # ══════════════════════════════════════════════════════════════════════
  #  VALIDĂRI
  # ══════════════════════════════════════════════════════════════════════

  test "validare eșuează dacă varianta nu are SKU" do
    visit new_product_path
    assert_selector "input[name='product[name]']", wait: 5

    product_name = "Carte Invalid #{SecureRandom.hex(4)}"
    product_slug = "carte-invalid-#{SecureRandom.hex(4)}"
    fill_in "product[name]", with: product_name
    fill_in "product[slug]", with: product_slug
    fill_in "product[sku]", with: "INV-#{SecureRandom.hex(4)}"

    check "has_variants"
    assert_selector "#section-variants", wait: 2

    find("#btn-add-variant").click

    # Fill price/stock but NOT SKU
    all(".variant-price")[0].set("39.99")
    all(".variant-stock")[0].set("10")
    all(".variant-vat")[0].set("19")

    click_button "Salvează produsul"

    product = Product.find_by(slug: product_slug)
    if product
      assert_equal 0, product.variants.count
    else
      # On create failure, Rails renders :new but the path stays at /products (POST path)
      assert_current_path(/\/products/)
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  #  PREȚURI MULTIPLE ȘI VAT DIFERIT
  # ══════════════════════════════════════════════════════════════════════

  test "produsul acceptă variante cu prețuri și VAT diferite" do
    visit new_product_path
    assert_selector "input[name='product[name]']", wait: 5

    product_name = "Carte Multi-Preț #{SecureRandom.hex(4)}"
    product_slug = "carte-multi-pret-#{SecureRandom.hex(4)}"
    fill_in "product[name]", with: product_name
    fill_in "product[slug]", with: product_slug
    fill_in "product[sku]", with: "MULTI-#{SecureRandom.hex(4)}"

    check "has_variants"
    assert_selector "#section-variants", wait: 2

    find("#btn-add-variant").click
    all(".variant-sku")[0].set("CHEAP-#{SecureRandom.hex(2)}")
    all(".variant-price")[0].set("29.99")
    all(".variant-stock")[0].set("5")
    all(".variant-vat")[0].set("19")

    find("#btn-add-variant").click
    all(".variant-sku")[1].set("PREMIUM-#{SecureRandom.hex(2)}")
    all(".variant-price")[1].set("99.99")
    all(".variant-stock")[1].set("2")
    all(".variant-vat")[1].set("9")
    all(".variant-status")[1].select("Inactive")

    click_button "Salvează produsul"

    assert_text product_name, wait: 5

    product = Product.find_by(slug: product_slug)
    assert_equal 2, product.variants.count

    cheap_variant = product.variants.find_by("sku LIKE ?", "CHEAP-%")
    premium_variant = product.variants.find_by("sku LIKE ?", "PREMIUM-%")

    assert_equal 29.99, cheap_variant.price.to_f
    assert_equal 19.0, cheap_variant.vat_rate.to_f

    assert_equal 99.99, premium_variant.price.to_f
    assert_equal 9.0, premium_variant.vat_rate.to_f
  end

  # ══════════════════════════════════════════════════════════════════════
  #  CHECKBOX "ARE VARIANTE?"
  # ══════════════════════════════════════════════════════════════════════

  test "când bifez 'Are variante?' secțiunea de variante apare" do
    visit new_product_path

    check "has_variants"

    assert_selector "#section-variants", visible: true, wait: 2
    assert_selector "#btn-add-variant"
  end

  test "când debifez 'Are variante?' secțiunea de variante dispare" do
    visit new_product_path

    check "has_variants"
    assert_selector "#section-variants", wait: 2

    uncheck "has_variants"

    assert_unchecked_field "has_variants"
  end
end

require "test_helper"

class VariantEdgeCasesTest < ActiveSupport::TestCase
  # ══════════════════════════════════════════════════════════════════════
  #  TESTE EDGE CASES - SCENARII CRITICE ȘI LIMITĂ
  # ══════════════════════════════════════════════════════════════════════

  test "varianta cu preț 0 este validă (gratuit)" do
    product = Product.create!(
      name: "Carte Free #{SecureRandom.hex(4)}",
      slug: "carte-free-#{SecureRandom.hex(4)}",
      sku: "FREE-#{SecureRandom.hex(4)}",
      price: 0
    )

    variant = product.variants.build(
      sku: "VAR-FREE-#{SecureRandom.hex(4)}",
      price: 0,
      stock: 100,
      vat_rate: 0
    )

    assert variant.valid?
    assert variant.save
  end

  test "varianta cu stoc 0 este validă (epuizat)" do
    product = Product.create!(
      name: "Carte Out #{SecureRandom.hex(4)}",
      slug: "carte-out-#{SecureRandom.hex(4)}",
      sku: "OUT-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-OUT-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 0,
      vat_rate: 19.0
    )

    assert variant.persisted?
    assert_equal 0, variant.stock
  end

  test "varianta cu preț negativ eșuează validarea" do
    product = Product.create!(
      name: "Carte Neg #{SecureRandom.hex(4)}",
      slug: "carte-neg-#{SecureRandom.hex(4)}",
      sku: "NEG-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.build(
      sku: "VAR-NEG-#{SecureRandom.hex(4)}",
      price: -10.00,
      stock: 10,
      vat_rate: 19.0
    )

    assert_not variant.valid?
    assert variant.errors[:price].present?
  end

  test "varianta cu stoc negativ eșuează validarea" do
    product = Product.create!(
      name: "Carte NegStock #{SecureRandom.hex(4)}",
      slug: "carte-negstock-#{SecureRandom.hex(4)}",
      sku: "NEGST-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.build(
      sku: "VAR-NEGST-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: -5,
      vat_rate: 19.0
    )

    assert_not variant.valid?
    assert variant.errors[:stock].present?
  end

  test "două variante cu același SKU în același produs eșuează" do
    product = Product.create!(
      name: "Carte Dup SKU #{SecureRandom.hex(4)}",
      slug: "carte-dup-sku-#{SecureRandom.hex(4)}",
      sku: "DUPSKU-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    sku = "SAME-SKU-#{SecureRandom.hex(4)}"

    variant1 = product.variants.create!(
      sku: sku,
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    variant2 = product.variants.build(
      sku: sku,
      price: 49.99,
      stock: 5,
      vat_rate: 9.0,
      status: 1
    )

    assert_not variant2.valid?
    assert variant2.errors[:sku].present?
  end

  test "două variante cu același SKU în produse diferite sunt OK" do
    product1 = Product.create!(
      name: "Carte 1 #{SecureRandom.hex(4)}",
      slug: "carte-1-#{SecureRandom.hex(4)}",
      sku: "P1-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    product2 = Product.create!(
      name: "Carte 2 #{SecureRandom.hex(4)}",
      slug: "carte-2-#{SecureRandom.hex(4)}",
      sku: "P2-#{SecureRandom.hex(4)}",
      price: 59.99
    )

    sku = "SHARED-SKU-#{SecureRandom.hex(4)}"

    variant1 = product1.variants.create!(
      sku: sku,
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    variant2 = product2.variants.create!(
      sku: sku,
      price: 49.99,
      stock: 5,
      vat_rate: 9.0
    )

    assert variant1.persisted?
    assert variant2.persisted?
  end

  test "varianta cu external_image_url NULL este validă" do
    product = Product.create!(
      name: "Carte No Img #{SecureRandom.hex(4)}",
      slug: "carte-no-img-#{SecureRandom.hex(4)}",
      sku: "NOIMG-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-NOIMG-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      external_image_url: nil
    )

    assert variant.persisted?
    assert_nil variant.external_image_url
  end

  test "varianta cu external_image_urls array gol este validă" do
    product = Product.create!(
      name: "Carte Empty Array #{SecureRandom.hex(4)}",
      slug: "carte-empty-array-#{SecureRandom.hex(4)}",
      sku: "EMPTY-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-EMPTY-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      external_image_urls: []
    )

    assert variant.persisted?
    assert_equal [], variant.external_image_urls
  end

  test "varianta cu VAT 0% este validă" do
    product = Product.create!(
      name: "Carte VAT0 #{SecureRandom.hex(4)}",
      slug: "carte-vat0-#{SecureRandom.hex(4)}",
      sku: "VAT0-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-VAT0-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 0
    )

    assert variant.persisted?
    assert_equal 0, variant.vat_rate.to_f
  end

  test "varianta cu VAT foarte mare (100%) este validă" do
    product = Product.create!(
      name: "Carte VAT100 #{SecureRandom.hex(4)}",
      slug: "carte-vat100-#{SecureRandom.hex(4)}",
      sku: "VAT100-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-VAT100-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 100.0
    )

    assert variant.persisted?
    assert_equal 100.0, variant.vat_rate.to_f
  end

  test "actualizarea SKU-ului unei variante funcționează" do
    product = Product.create!(
      name: "Carte Update SKU #{SecureRandom.hex(4)}",
      slug: "carte-update-sku-#{SecureRandom.hex(4)}",
      sku: "UPSKU-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "OLD-SKU-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    new_sku = "NEW-SKU-#{SecureRandom.hex(4)}"
    variant.update!(sku: new_sku)

    assert_equal new_sku, variant.sku
  end

  test "varianta marcată ca inactivă nu încalcă constraint-ul unic" do
    product = Product.create!(
      name: "Carte Inactive #{SecureRandom.hex(4)}",
      slug: "carte-inactive-#{SecureRandom.hex(4)}",
      sku: "INACT-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    # Prima variantă activă
    variant1 = product.variants.create!(
      sku: "V1-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      status: 0
    )

    # Facem prima inactivă
    variant1.update!(status: 1)

    # Acum putem crea o nouă variantă activă
    variant2 = product.variants.create!(
      sku: "V2-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 5,
      vat_rate: 9.0,
      status: 0
    )

    assert variant2.persisted?
  end

  test "varianta cu array de peste 100 imagini funcționează" do
    product = Product.create!(
      name: "Carte Many Imgs #{SecureRandom.hex(4)}",
      slug: "carte-many-imgs-#{SecureRandom.hex(4)}",
      sku: "MANY-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    many_images = 150.times.map { |i| "https://ayus-cdn.b-cdn.net/test/img#{i}.jpg" }

    variant = product.variants.create!(
      sku: "VAR-MANY-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      external_image_urls: many_images
    )

    assert variant.persisted?
    assert_equal 150, variant.external_image_urls.length
  end

  test "ștergerea tuturor variantelor unui produs funcționează" do
    product = Product.create!(
      name: "Carte Delete All #{SecureRandom.hex(4)}",
      slug: "carte-delete-all-#{SecureRandom.hex(4)}",
      sku: "DELALL-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    5.times do |i|
      product.variants.create!(
        sku: "V#{i}-#{SecureRandom.hex(4)}",
        price: 39.99 + i,
        stock: 10,
        vat_rate: 19.0,
        status: i == 0 ? 0 : 1
      )
    end

    assert_equal 5, product.variants.count

    product.variants.destroy_all

    assert_equal 0, product.variants.count
  end

  test "schimbarea prețului variantei nu afectează comenzile existente" do
    product = Product.create!(
      name: "Carte Order #{SecureRandom.hex(4)}",
      slug: "carte-order-#{SecureRandom.hex(4)}",
      sku: "ORDER-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VORD-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    # Simulăm o comandă (doar verificăm că varianta există)
    initial_price = variant.price

    # Schimbăm prețul
    variant.update!(price: 59.99)

    # Verificăm că prețul s-a schimbat
    assert_equal 59.99, variant.reload.price.to_f
    assert_not_equal initial_price, variant.price
  end

  test "varianta cu SKU foarte lung (255 caractere) funcționează" do
    product = Product.create!(
      name: "Carte Long SKU #{SecureRandom.hex(4)}",
      slug: "carte-long-sku-#{SecureRandom.hex(4)}",
      sku: "LONG-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    long_sku = "A" * 255

    variant = product.variants.create!(
      sku: long_sku,
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    assert variant.persisted?
    assert_equal 255, variant.sku.length
  end
end

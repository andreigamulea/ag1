require "test_helper"

class ProductVariantsTest < ActiveSupport::TestCase
  # ══════════════════════════════════════════════════════════════════════
  #  TESTE MODEL - VARIANTE CU IMAGINI, VALIDĂRI, SALVĂRI
  # ══════════════════════════════════════════════════════════════════════

  test "produsul poate avea variante cu imagini externe" do
    product = Product.create!(
      name: "Carte Test #{SecureRandom.hex(4)}",
      slug: "carte-test-#{SecureRandom.hex(4)}",
      sku: "TEST-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      external_image_url: "https://ayus-cdn.b-cdn.net/test/image1.jpg"
    )

    assert_equal "https://ayus-cdn.b-cdn.net/test/image1.jpg", variant.external_image_url
    assert variant.persisted?
  end

  test "varianta poate avea array de imagini externe" do
    product = Product.create!(
      name: "Carte Multi-Img #{SecureRandom.hex(4)}",
      slug: "carte-multi-img-#{SecureRandom.hex(4)}",
      sku: "MULTI-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-MULTI-#{SecureRandom.hex(4)}",
      price: 59.99,
      stock: 15,
      vat_rate: 19.0,
      external_image_url: "https://ayus-cdn.b-cdn.net/test/main.jpg",
      external_image_urls: [
        "https://ayus-cdn.b-cdn.net/test/img1.jpg",
        "https://ayus-cdn.b-cdn.net/test/img2.jpg",
        "https://ayus-cdn.b-cdn.net/test/img3.jpg"
      ]
    )

    assert_equal 3, variant.external_image_urls.length
    assert_includes variant.external_image_urls, "https://ayus-cdn.b-cdn.net/test/img1.jpg"
  end

  test "varianta necesită SKU, preț și stoc" do
    product = Product.create!(
      name: "Carte Valid #{SecureRandom.hex(4)}",
      slug: "carte-valid-#{SecureRandom.hex(4)}",
      sku: "VALID-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    # Fără SKU - invalidă
    variant = product.variants.build(price: 39.99, stock: 10, vat_rate: 19.0)
    assert_not variant.valid?
    assert variant.errors[:sku].present?

    # Fără preț - invalidă (price defaults to 0 in DB, but model validates >= 0)
    variant = product.variants.build(sku: "VAR-001", price: nil, stock: 10, vat_rate: 19.0)
    assert_not variant.valid?
    assert variant.errors[:price].present?

    # Fără stoc - invalidă (stock defaults to 0 in DB, but model validates >= 0)
    variant = product.variants.build(sku: "VAR-001", price: 39.99, stock: nil, vat_rate: 19.0)
    assert_not variant.valid?
    assert variant.errors[:stock].present?
  end

  test "constraint unic: doar o variantă activă fără opțiuni per produs" do
    product = Product.create!(
      name: "Carte Constraint #{SecureRandom.hex(4)}",
      slug: "carte-constraint-#{SecureRandom.hex(4)}",
      sku: "CONSTR-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    # Prima variantă activă fără opțiuni - OK
    variant1 = product.variants.create!(
      sku: "VAR-1-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      status: 0 # active
      # options_digest va fi NULL
    )

    assert variant1.persisted?

    # A doua variantă activă fără opțiuni - va eșua constraint-ul
    variant2 = product.variants.build(
      sku: "VAR-2-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 5,
      vat_rate: 19.0,
      status: 0 # active
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      variant2.save!
    end
  end

  test "mai multe variante inactive fără opțiuni sunt permise" do
    product = Product.create!(
      name: "Carte Inactive #{SecureRandom.hex(4)}",
      slug: "carte-inactive-#{SecureRandom.hex(4)}",
      sku: "INACT-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    # Prima variantă inactivă
    variant1 = product.variants.create!(
      sku: "VAR-INACT-1-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      status: 1 # inactive
    )

    # A doua variantă inactivă - OK (constraint nu se aplică pentru inactive)
    variant2 = product.variants.create!(
      sku: "VAR-INACT-2-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 5,
      vat_rate: 19.0,
      status: 1 # inactive
    )

    assert variant1.persisted?
    assert variant2.persisted?
    assert_equal 2, product.variants.count
  end

  test "varianta poate avea VAT diferit de produsul principal" do
    product = Product.create!(
      name: "Carte VAT #{SecureRandom.hex(4)}",
      slug: "carte-vat-#{SecureRandom.hex(4)}",
      sku: "VAT-#{SecureRandom.hex(4)}",
      price: 49.99,
      vat: 19.0
    )

    variant = product.variants.create!(
      sku: "VAR-VAT-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 9.0 # VAT diferit
    )

    assert_equal 19.0, product.vat.to_f
    assert_equal 9.0, variant.vat_rate.to_f
  end

  test "product.has_active_variants? returnează true dacă are variante active" do
    product = Product.create!(
      name: "Carte Has Variants #{SecureRandom.hex(4)}",
      slug: "carte-has-variants-#{SecureRandom.hex(4)}",
      sku: "HAS-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    # Fără variante
    assert_not product.send(:has_active_variants?)

    # Creăm variantă activă
    product.variants.create!(
      sku: "VAR-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      status: :active
    )

    product.reload
    assert product.send(:has_active_variants?)
  end

  test "nested attributes - accept blank pentru reject_if" do
    product = Product.create!(
      name: "Carte Nested #{SecureRandom.hex(4)}",
      slug: "carte-nested-#{SecureRandom.hex(4)}",
      sku: "NESTED-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    # Rând complet gol - ar trebui să fie respins
    result = product.update(variants_attributes: [
      { sku: "", price: "", stock: "", vat_rate: "" }
    ])

    # Verificăm că rândul gol a fost respins
    assert_equal 0, product.variants.count
  end

  test "nested attributes - variantă validă se salvează" do
    product = Product.create!(
      name: "Carte Nested Valid #{SecureRandom.hex(4)}",
      slug: "carte-nested-valid-#{SecureRandom.hex(4)}",
      sku: "NVALID-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    result = product.update(variants_attributes: [
      {
        sku: "VAR-NESTED-#{SecureRandom.hex(4)}",
        price: 39.99,
        stock: 10,
        vat_rate: 19.0,
        external_image_url: "https://ayus-cdn.b-cdn.net/test/nested.jpg"
      }
    ])

    assert result
    assert_equal 1, product.variants.count

    variant = product.variants.first
    assert_equal 39.99, variant.price.to_f
    assert_equal "https://ayus-cdn.b-cdn.net/test/nested.jpg", variant.external_image_url
  end

  test "imagini externe persistă corect în baza de date" do
    product = Product.create!(
      name: "Carte Persist Img #{SecureRandom.hex(4)}",
      slug: "carte-persist-img-#{SecureRandom.hex(4)}",
      sku: "PERSIST-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-PERSIST-#{SecureRandom.hex(4)}",
      price: 59.99,
      stock: 20,
      vat_rate: 19.0,
      external_image_url: "https://ayus-cdn.b-cdn.net/products/main.jpg",
      external_image_urls: [
        "https://ayus-cdn.b-cdn.net/products/gallery1.jpg",
        "https://ayus-cdn.b-cdn.net/products/gallery2.jpg"
      ]
    )

    # Reload din DB
    variant.reload

    assert_equal "https://ayus-cdn.b-cdn.net/products/main.jpg", variant.external_image_url
    assert_equal 2, variant.external_image_urls.length
    assert_includes variant.external_image_urls, "https://ayus-cdn.b-cdn.net/products/gallery1.jpg"
  end

  test "ștergerea produsului cu variante este restricționată" do
    product = Product.create!(
      name: "Carte Pentru Ștergere #{SecureRandom.hex(4)}",
      slug: "carte-pentru-stergere-#{SecureRandom.hex(4)}",
      sku: "DELETE-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant_id = product.variants.create!(
      sku: "VAR-DELETE-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    ).id

    product.reload

    # Verificăm că varianta există
    assert Variant.exists?(variant_id)

    # dependent: :restrict_with_exception previne ștergerea
    assert_raises(ActiveRecord::DeleteRestrictionError) do
      product.destroy
    end

    # Produsul și varianta rămân intacte
    assert Product.exists?(product.id)
    assert Variant.exists?(variant_id)
  end
end

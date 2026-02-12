require "test_helper"

class ProductsControllerVariantsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      email: "admin-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true
    )
    sign_in @admin
  end

  # ══════════════════════════════════════════════════════════════════════
  #  TESTE CONTROLLER - CREARE PRODUSE CU VARIANTE
  # ══════════════════════════════════════════════════════════════════════

  test "POST /products cu variante valide creează produsul și variantele" do
    assert_difference "Product.count", 1 do
      assert_difference "Variant.count", 2 do
        post products_path, params: {
          product: {
            name: "Carte Test #{SecureRandom.hex(4)}",
            slug: "carte-test-#{SecureRandom.hex(4)}",
            sku: "TEST-#{SecureRandom.hex(4)}",
            price: 49.99,
            stock: 10,
            variants_attributes: [
              {
                sku: "V1-#{SecureRandom.hex(4)}",
                price: 39.99,
                stock: 5,
                vat_rate: 19.0,
                status: 0
              },
              {
                sku: "V2-#{SecureRandom.hex(4)}",
                price: 49.99,
                stock: 8,
                vat_rate: 9.0,
                status: 1
              }
            ]
          }
        }
      end
    end

    assert_response :redirect
    product = Product.last
    assert_equal 2, product.variants.count
  end

  test "POST /products cu variantă cu imagini externe" do
    assert_difference "Product.count", 1 do
      assert_difference "Variant.count", 1 do
        post products_path, params: {
          product: {
            name: "Carte Cu Imagini #{SecureRandom.hex(4)}",
            slug: "carte-cu-imagini-#{SecureRandom.hex(4)}",
            sku: "IMG-#{SecureRandom.hex(4)}",
            price: 49.99,
            variants_attributes: [
              {
                sku: "VIMG-#{SecureRandom.hex(4)}",
                price: 59.99,
                stock: 10,
                vat_rate: 19.0,
                external_image_url: "https://ayus-cdn.b-cdn.net/test/var1.jpg",
                external_image_urls: [
                  "https://ayus-cdn.b-cdn.net/test/var1-gal1.jpg",
                  "https://ayus-cdn.b-cdn.net/test/var1-gal2.jpg"
                ]
              }
            ]
          }
        }
      end
    end

    product = Product.last
    variant = product.variants.first
    assert_equal "https://ayus-cdn.b-cdn.net/test/var1.jpg", variant.external_image_url
    assert_equal 2, variant.external_image_urls.length
  end

  test "POST /products respinge rânduri de variante goale" do
    assert_difference "Product.count", 1 do
      assert_no_difference "Variant.count" do
        post products_path, params: {
          product: {
            name: "Carte Reject #{SecureRandom.hex(4)}",
            slug: "carte-reject-#{SecureRandom.hex(4)}",
            sku: "REJECT-#{SecureRandom.hex(4)}",
            price: 49.99,
            variants_attributes: [
              {
                sku: "",
                price: "",
                stock: "",
                vat_rate: ""
              }
            ]
          }
        }
      end
    end

    product = Product.last
    assert_equal 0, product.variants.count
  end

  test "PATCH /products/:id adaugă variante la produs existent" do
    product = Product.create!(
      name: "Carte Fără Variante #{SecureRandom.hex(4)}",
      slug: "carte-fara-variante-#{SecureRandom.hex(4)}",
      sku: "FARA-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 20
    )

    assert_difference "Variant.count", 2 do
      patch product_path(product), params: {
        product: {
          variants_attributes: [
            {
              sku: "NEW-V1-#{SecureRandom.hex(4)}",
              price: 44.99,
              stock: 8,
              vat_rate: 19.0
            },
            {
              sku: "NEW-V2-#{SecureRandom.hex(4)}",
              price: 54.99,
              stock: 12,
              vat_rate: 19.0,
              status: 1
            }
          ]
        }
      }
    end

    product.reload
    assert_equal 2, product.variants.count
  end

  test "PATCH /products/:id actualizează variante existente" do
    product = Product.create!(
      name: "Carte Cu Variante #{SecureRandom.hex(4)}",
      slug: "carte-cu-variante-#{SecureRandom.hex(4)}",
      sku: "CU-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "OLD-V-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    patch product_path(product), params: {
      product: {
        variants_attributes: [
          {
            id: variant.id,
            price: 44.99,
            stock: 15,
            vat_rate: 9.0
          }
        ]
      }
    }

    variant.reload
    assert_equal 44.99, variant.price.to_f
    assert_equal 15, variant.stock
    assert_equal 9.0, variant.vat_rate.to_f
  end

  test "PATCH /products/:id șterge variante cu _destroy flag" do
    product = Product.create!(
      name: "Carte Delete Variant #{SecureRandom.hex(4)}",
      slug: "carte-delete-variant-#{SecureRandom.hex(4)}",
      sku: "DEL-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "DEL-V-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    assert_difference "Variant.count", -1 do
      patch product_path(product), params: {
        product: {
          variants_attributes: [
            {
              id: variant.id,
              _destroy: "1"
            }
          ]
        }
      }
    end

    product.reload
    assert_equal 0, product.variants.count
  end

  test "POST /products fără permisiuni admin eșuează" do
    sign_out @admin

    regular_user = User.create!(
      email: "user-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 0,
      active: true
    )
    sign_in regular_user

    assert_no_difference "Product.count" do
      post products_path, params: {
        product: {
          name: "Carte Unauthorized #{SecureRandom.hex(4)}",
          slug: "carte-unauthorized-#{SecureRandom.hex(4)}",
          sku: "UNAUTH-#{SecureRandom.hex(4)}",
          price: 49.99
        }
      }
    end

    assert_response :redirect
  end

  test "PATCH /products/:id actualizează imagini variante" do
    product = Product.create!(
      name: "Carte Update Images #{SecureRandom.hex(4)}",
      slug: "carte-update-images-#{SecureRandom.hex(4)}",
      sku: "UPIMG-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "UPV-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      external_image_url: "https://ayus-cdn.b-cdn.net/old.jpg"
    )

    patch product_path(product), params: {
      product: {
        variants_attributes: [
          {
            id: variant.id,
            external_image_url: "https://ayus-cdn.b-cdn.net/new.jpg",
            external_image_urls: [
              "https://ayus-cdn.b-cdn.net/new-gal1.jpg",
              "https://ayus-cdn.b-cdn.net/new-gal2.jpg",
              "https://ayus-cdn.b-cdn.net/new-gal3.jpg"
            ]
          }
        ]
      }
    }

    variant.reload
    assert_equal "https://ayus-cdn.b-cdn.net/new.jpg", variant.external_image_url
    assert_equal 3, variant.external_image_urls.length
    assert_includes variant.external_image_urls, "https://ayus-cdn.b-cdn.net/new-gal1.jpg"
  end

  test "POST /products cu variante cu prețuri și VAT diferite" do
    assert_difference "Product.count", 1 do
      assert_difference "Variant.count", 3 do
        post products_path, params: {
          product: {
            name: "Carte Multi #{SecureRandom.hex(4)}",
            slug: "carte-multi-#{SecureRandom.hex(4)}",
            sku: "MULTI-#{SecureRandom.hex(4)}",
            price: 49.99,
            variants_attributes: [
              { sku: "CHEAP-#{SecureRandom.hex(4)}", price: 29.99, stock: 20, vat_rate: 19.0 },
              { sku: "MID-#{SecureRandom.hex(4)}", price: 49.99, stock: 10, vat_rate: 9.0, status: 1 },
              { sku: "PREMIUM-#{SecureRandom.hex(4)}", price: 99.99, stock: 5, vat_rate: 5.0, status: 1 }
            ]
          }
        }
      end
    end

    product = Product.last
    prices = product.variants.map { |v| v.price.to_f }.sort
    assert_equal [29.99, 49.99, 99.99], prices

    vat_rates = product.variants.map { |v| v.vat_rate.to_f }.sort
    assert_includes vat_rates, 5.0
    assert_includes vat_rates, 9.0
    assert_includes vat_rates, 19.0
  end

  test "GET /products/new returnează pagina de formular" do
    get new_product_path
    assert_response :success
    assert_select "input[name='product[name]']"
    assert_select "input[type='checkbox'][id='toggle-has-variants']"
  end

  test "GET /products/:id/edit cu variante existente afișează variantele" do
    product = Product.create!(
      name: "Carte Edit #{SecureRandom.hex(4)}",
      slug: "carte-edit-#{SecureRandom.hex(4)}",
      sku: "EDIT-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    v1 = product.variants.create!(
      sku: "EV1-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    v2 = product.variants.create!(
      sku: "EV2-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 5,
      vat_rate: 9.0,
      status: 1
    )

    get edit_product_path(product)
    assert_response :success
    # Verificăm că hidden fields pentru variante există
    assert_select "input[type='hidden'][value='#{v1.id}']"
    assert_select "input[type='hidden'][value='#{v2.id}']"
  end
end

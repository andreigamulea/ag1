require "test_helper"

class ProductVariantsIntegrationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ══════════════════════════════════════════════════════════════════════
  #  TESTE INTEGRARE - FLOW COMPLET FĂRĂ UI (prin controllere direct)
  # ══════════════════════════════════════════════════════════════════════

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

  test "crearea unui produs cu variante prin POST request" do
    product_params = {
      product: {
        name: "Carte API #{SecureRandom.hex(4)}",
        slug: "carte-api-#{SecureRandom.hex(4)}",
        sku: "API-#{SecureRandom.hex(4)}",
        price: 49.99,
        stock: 100,
        variants_attributes: [
          {
            sku: "VAR-API-1-#{SecureRandom.hex(2)}",
            price: 39.99,
            stock: 10,
            vat_rate: 19.0,
            external_image_url: "https://ayus-cdn.b-cdn.net/test/api1.jpg"
          },
          {
            sku: "VAR-API-2-#{SecureRandom.hex(2)}",
            price: 49.99,
            stock: 15,
            vat_rate: 9.0,
            status: "inactive",
            external_image_url: "https://ayus-cdn.b-cdn.net/test/api2.jpg"
          }
        ]
      }
    }

    assert_difference "Product.count", 1 do
      assert_difference "Variant.count", 2 do
        post products_path, params: product_params
      end
    end

    product = Product.last
    assert_equal 2, product.variants.count

    # Verificăm că imaginile s-au salvat
    variant1 = product.variants.first
    assert_equal "https://ayus-cdn.b-cdn.net/test/api1.jpg", variant1.external_image_url
  end

  test "editarea unui produs pentru a adăuga variante" do
    # Creăm un produs fără variante
    product = Product.create!(
      name: "Carte Fără Variante #{SecureRandom.hex(4)}",
      slug: "carte-fara-variante-#{SecureRandom.hex(4)}",
      sku: "FARA-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 50
    )

    # Adăugăm variante prin UPDATE
    update_params = {
      product: {
        variants_attributes: [
          {
            sku: "VAR-ADD-1-#{SecureRandom.hex(2)}",
            price: 44.99,
            stock: 8,
            vat_rate: 19.0
          },
          {
            sku: "VAR-ADD-2-#{SecureRandom.hex(2)}",
            price: 54.99,
            stock: 12,
            vat_rate: 19.0,
            status: "inactive"
          }
        ]
      }
    }

    assert_difference "Variant.count", 2 do
      patch product_path(product), params: update_params
    end

    product.reload
    assert_equal 2, product.variants.count
  end

  test "ștergerea unei variante prin _destroy flag" do
    product = Product.create!(
      name: "Carte Cu Variante #{SecureRandom.hex(4)}",
      slug: "carte-cu-variante-#{SecureRandom.hex(4)}",
      sku: "CU-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant_to_delete = product.variants.create!(
      sku: "VAR-DELETE-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0
    )

    variant_to_keep = product.variants.create!(
      sku: "VAR-KEEP-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 5,
      vat_rate: 19.0,
      status: 1
    )

    # Ștergem prima variantă
    update_params = {
      product: {
        variants_attributes: [
          {
            id: variant_to_delete.id,
            _destroy: "1"
          },
          {
            id: variant_to_keep.id
          }
        ]
      }
    }

    assert_difference "Variant.count", -1 do
      patch product_path(product), params: update_params
    end

    product.reload
    assert_equal 1, product.variants.count
    assert_equal variant_to_keep.id, product.variants.first.id
  end

  test "actualizarea imaginilor unei variante existente" do
    product = Product.create!(
      name: "Carte Update Img #{SecureRandom.hex(4)}",
      slug: "carte-update-img-#{SecureRandom.hex(4)}",
      sku: "UPIMG-#{SecureRandom.hex(4)}",
      price: 49.99
    )

    variant = product.variants.create!(
      sku: "VAR-UPIMG-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      external_image_url: "https://ayus-cdn.b-cdn.net/old/image.jpg"
    )

    # Actualizăm imaginea
    update_params = {
      product: {
        variants_attributes: [
          {
            id: variant.id,
            external_image_url: "https://ayus-cdn.b-cdn.net/new/image.jpg",
            external_image_urls: [
              "https://ayus-cdn.b-cdn.net/new/gallery1.jpg",
              "https://ayus-cdn.b-cdn.net/new/gallery2.jpg"
            ]
          }
        ]
      }
    }

    patch product_path(product), params: update_params

    variant.reload
    assert_equal "https://ayus-cdn.b-cdn.net/new/image.jpg", variant.external_image_url
    assert_equal 2, variant.external_image_urls.length
    assert_includes variant.external_image_urls, "https://ayus-cdn.b-cdn.net/new/gallery1.jpg"
  end

  test "validarea eșuează pentru variantă fără SKU" do
    product_params = {
      product: {
        name: "Carte Invalid #{SecureRandom.hex(4)}",
        slug: "carte-invalid-#{SecureRandom.hex(4)}",
        sku: "INVALID-#{SecureRandom.hex(4)}",
        price: 49.99,
        variants_attributes: [
          {
            # SKU lipsă
            price: 39.99,
            stock: 10,
            vat_rate: 19.0
          }
        ]
      }
    }

    # Varianta invalidă (fără SKU) face ca tot produsul să nu se salveze
    assert_no_difference "Product.count" do
      post products_path, params: product_params
    end

    assert_response :unprocessable_entity
  end

  test "crearea produsului cu variante cu prețuri și VAT diferite" do
    product_params = {
      product: {
        name: "Carte Multi-Price #{SecureRandom.hex(4)}",
        slug: "carte-multi-price-#{SecureRandom.hex(4)}",
        sku: "MULTI-#{SecureRandom.hex(4)}",
        price: 49.99,
        variants_attributes: [
          {
            sku: "VAR-CHEAP-#{SecureRandom.hex(2)}",
            price: 29.99,
            stock: 20,
            vat_rate: 19.0
          },
          {
            sku: "VAR-PREMIUM-#{SecureRandom.hex(2)}",
            price: 99.99,
            stock: 5,
            vat_rate: 9.0,
            status: "inactive"
          }
        ]
      }
    }

    assert_difference "Product.count", 1 do
      assert_difference "Variant.count", 2 do
        post products_path, params: product_params
      end
    end

    product = Product.last
    variants = product.variants.order(:price)

    assert_equal 29.99, variants.first.price.to_f
    assert_equal 19.0, variants.first.vat_rate.to_f

    assert_equal 99.99, variants.last.price.to_f
    assert_equal 9.0, variants.last.vat_rate.to_f
  end

  test "produsul fără variante rămâne valid și funcțional" do
    product_params = {
      product: {
        name: "Carte Simplă #{SecureRandom.hex(4)}",
        slug: "carte-simpla-#{SecureRandom.hex(4)}",
        sku: "SIMPLE-#{SecureRandom.hex(4)}",
        price: 49.99,
        stock: 100
        # Nu trimitem variants_attributes
      }
    }

    assert_difference "Product.count", 1 do
      post products_path, params: product_params
    end

    product = Product.last
    assert_equal 0, product.variants.count
    assert_not product.send(:has_active_variants?)
    assert_equal 49.99, product.price.to_f
  end

  test "răspunsul HTTP pentru creare cu succes" do
    product_params = {
      product: {
        name: "Carte HTTP #{SecureRandom.hex(4)}",
        slug: "carte-http-#{SecureRandom.hex(4)}",
        sku: "HTTP-#{SecureRandom.hex(4)}",
        price: 49.99,
        variants_attributes: [
          {
            sku: "VAR-HTTP-#{SecureRandom.hex(2)}",
            price: 39.99,
            stock: 10,
            vat_rate: 19.0
          }
        ]
      }
    }

    post products_path, params: product_params

    # Verificăm redirect după creare (302 sau 303)
    assert_response :redirect

    # Ar trebui să redirecționeze la pagina produsului
    product = Product.last
    assert_redirected_to product_path(product) || products_path
  end
end

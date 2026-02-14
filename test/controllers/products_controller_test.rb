require "test_helper"

class ProductsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      email: "admin-pct-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true
    )
    sign_in @admin

    @product = Product.create!(
      name: "Test Product #{SecureRandom.hex(4)}",
      slug: "test-product-#{SecureRandom.hex(4)}",
      sku: "TP-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 10
    )
  end

  test "should get index" do
    get products_url
    assert_response :success
  end

  test "should get new" do
    get new_product_url
    assert_response :success
  end

  test "should create product" do
    assert_difference("Product.count") do
      post products_url, params: { product: {
        name: "New Product #{SecureRandom.hex(4)}",
        sku: "SKU-NEW-#{SecureRandom.hex(4)}",
        slug: "new-product-#{SecureRandom.hex(4)}",
        price: 99.99,
        stock: 50
      } }
    end

    assert_redirected_to product_url(Product.last)
  end

  test "should show product" do
    get product_url(@product)
    assert_response :success
  end

  test "should get edit" do
    get edit_product_url(@product)
    assert_response :success
  end

  test "should update product" do
    patch product_url(@product), params: { product: { name: "Updated Name", price: 59.99 } }
    assert_redirected_to product_url(@product)
  end

  test "should archive product on destroy" do
    delete product_url(@product)
    assert_redirected_to products_url

    @product.reload
    assert_equal "archived", @product.status
  end
end

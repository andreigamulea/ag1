require "test_helper"

# =============================================================================
# Teste pentru fix-urile de securitate și integritate
# Fix 1: Auth pe ProductsController + CouponsController + UploadsController
# Fix 4: Upload validare fișier
# Fix 5: Cart quantity validation
# =============================================================================

class ProductsAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      email: "admin-auth-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true,
      confirmed_at: Time.current
    )

    @regular_user = User.create!(
      email: "user-auth-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 0,
      active: true,
      confirmed_at: Time.current
    )

    @product = Product.create!(
      name: "Test Auth Product #{SecureRandom.hex(4)}",
      slug: "test-auth-#{SecureRandom.hex(4)}",
      sku: "AUTH-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 10
    )
  end

  # --- Guest (neautentificat) nu poate accesa admin ---

  test "guest cannot access products index" do
    get products_url
    assert_redirected_to new_user_session_path
  end

  test "guest cannot access new product" do
    get new_product_url
    assert_redirected_to new_user_session_path
  end

  test "guest cannot create product" do
    assert_no_difference("Product.count") do
      post products_url, params: { product: {
        name: "Hack Product", sku: "HACK-1", slug: "hack", price: 1
      } }
    end
    assert_redirected_to new_user_session_path
  end

  test "guest cannot edit product" do
    get edit_product_url(@product)
    assert_redirected_to new_user_session_path
  end

  test "guest cannot update product" do
    patch product_url(@product), params: { product: { name: "Hacked" } }
    assert_redirected_to new_user_session_path
    assert_not_equal "Hacked", @product.reload.name
  end

  test "guest cannot destroy product" do
    delete product_url(@product)
    assert_redirected_to new_user_session_path
    assert_equal "active", @product.reload.status
  end

  test "guest CAN view product show page" do
    get product_url(@product)
    assert_response :success
  end

  # --- Regular user nu poate accesa admin ---

  test "regular user cannot access products index" do
    sign_in @regular_user
    get products_url
    assert_redirected_to root_path
  end

  test "regular user cannot create product" do
    sign_in @regular_user
    assert_no_difference("Product.count") do
      post products_url, params: { product: {
        name: "Hack Product", sku: "HACK-2", slug: "hack-2", price: 1
      } }
    end
    assert_redirected_to root_path
  end

  test "regular user cannot edit product" do
    sign_in @regular_user
    get edit_product_url(@product)
    assert_redirected_to root_path
  end

  test "regular user cannot destroy product" do
    sign_in @regular_user
    delete product_url(@product)
    assert_redirected_to root_path
    assert_equal "active", @product.reload.status
  end

  test "regular user CAN view product show page" do
    sign_in @regular_user
    get product_url(@product)
    assert_response :success
  end

  # --- Admin poate accesa totul ---

  test "admin can access products index" do
    sign_in @admin
    get products_url
    assert_response :success
  end

  test "admin can create product" do
    sign_in @admin
    assert_difference("Product.count") do
      post products_url, params: { product: {
        name: "Admin Product #{SecureRandom.hex(4)}",
        sku: "ADM-#{SecureRandom.hex(4)}",
        slug: "admin-prod-#{SecureRandom.hex(4)}",
        price: 99.99,
        stock: 10
      } }
    end
  end

  test "admin can edit product" do
    sign_in @admin
    get edit_product_url(@product)
    assert_response :success
  end

  test "admin can update product" do
    sign_in @admin
    patch product_url(@product), params: { product: { name: "Updated by Admin" } }
    assert_redirected_to product_url(@product)
    assert_equal "Updated by Admin", @product.reload.name
  end

  test "admin can archive product" do
    sign_in @admin
    delete product_url(@product)
    assert_redirected_to products_url
    assert_equal "archived", @product.reload.status
  end
end


class CouponsAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      email: "admin-coup-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true,
      confirmed_at: Time.current
    )

    @regular_user = User.create!(
      email: "user-coup-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 0,
      active: true,
      confirmed_at: Time.current
    )

    @coupon = Coupon.create!(
      code: "TESTCOUP#{SecureRandom.hex(3)}",
      discount_type: "percentage",
      discount_value: 10,
      active: true,
      starts_at: 1.day.ago,
      expires_at: 1.day.from_now
    )
  end

  test "guest cannot access coupons index" do
    get coupons_url
    assert_redirected_to new_user_session_path
  end

  test "guest cannot create coupon" do
    assert_no_difference("Coupon.count") do
      post coupons_url, params: { coupon: {
        code: "HACK", discount_type: "fixed", discount_value: 100,
        starts_at: 1.day.ago, expires_at: 1.day.from_now
      } }
    end
    assert_redirected_to new_user_session_path
  end

  test "guest cannot destroy coupon" do
    assert_no_difference("Coupon.count", -1) do
      delete coupon_url(@coupon)
    end
    assert_redirected_to new_user_session_path
  end

  test "regular user cannot access coupons" do
    sign_in @regular_user
    get coupons_url
    assert_redirected_to root_path
  end

  test "regular user cannot create coupon" do
    sign_in @regular_user
    assert_no_difference("Coupon.count") do
      post coupons_url, params: { coupon: {
        code: "HACK2", discount_type: "fixed", discount_value: 100,
        starts_at: 1.day.ago, expires_at: 1.day.from_now
      } }
    end
    assert_redirected_to root_path
  end

  test "admin can access coupons index" do
    sign_in @admin
    get coupons_url
    assert_response :success
  end

  test "admin can create coupon" do
    sign_in @admin
    assert_difference("Coupon.count") do
      post coupons_url, params: { coupon: {
        code: "ADMIN#{SecureRandom.hex(3)}",
        discount_type: "fixed",
        discount_value: 10,
        active: true,
        starts_at: 1.day.ago,
        expires_at: 1.day.from_now
      } }
    end
    assert_redirected_to coupons_path
  end

  test "admin can destroy coupon" do
    sign_in @admin
    assert_difference("Coupon.count", -1) do
      delete coupon_url(@coupon)
    end
    assert_redirected_to coupons_path
  end
end


class UploadsAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      email: "admin-upl-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true,
      confirmed_at: Time.current
    )

    @regular_user = User.create!(
      email: "user-upl-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 0,
      active: true,
      confirmed_at: Time.current
    )
  end

  test "guest cannot presign upload" do
    get "/uploads/presign", params: { filename: "test.jpg" }
    assert_redirected_to new_user_session_path
  end

  test "regular user cannot presign upload" do
    sign_in @regular_user
    get "/uploads/presign", params: { filename: "test.jpg" }
    assert_redirected_to root_path
  end

  test "admin can presign upload for valid file" do
    sign_in @admin
    get "/uploads/presign", params: { filename: "product-image.jpg" }
    assert_response :success
    json = JSON.parse(response.body)
    assert json["upload_url"].present?
  end

  test "rejects dangerous file extensions" do
    sign_in @admin
    %w[test.rb script.exe hack.sh payload.php].each do |dangerous|
      get "/uploads/presign", params: { filename: dangerous }
      assert_response :unprocessable_entity, "Should reject #{dangerous}"
      json = JSON.parse(response.body)
      assert json["error"].present?, "Should have error for #{dangerous}"
    end
  end

  test "accepts valid file extensions" do
    sign_in @admin
    %w[image.jpg photo.png doc.pdf archive.zip video.mp4].each do |valid|
      get "/uploads/presign", params: { filename: valid }
      assert_response :success, "Should accept #{valid}"
    end
  end

  test "sanitizes path traversal in filename" do
    sign_in @admin
    get "/uploads/presign", params: { filename: "../../etc/passwd.jpg" }
    assert_response :success
    json = JSON.parse(response.body)
    # Should NOT contain path traversal
    refute json["upload_url"].include?(".."), "URL should not contain path traversal"
    assert json["upload_url"].include?("passwd.jpg")
  end
end

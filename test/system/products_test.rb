require "application_system_test_case"

class ProductsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      email: "admin-sys-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true
    )
    sign_in @admin

    @product = Product.create!(
      name: "Carte System Test #{SecureRandom.hex(4)}",
      slug: "carte-system-test-#{SecureRandom.hex(4)}",
      sku: "SYS-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 10
    )
  end

  test "visiting the index" do
    visit products_url
    assert_selector "h1", text: "Listă produse"
  end
end

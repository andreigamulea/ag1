require "application_system_test_case"

class AddingProductToCartTest < ApplicationSystemTestCase
  setup do
    @carte = Category.find_or_create_by!(name: "carte") { |c| c.slug = "carte" }
    @fizic = Category.find_or_create_by!(name: "fizic") { |c| c.slug = "fizic" }

    @product = Product.create!(
      name: "Test Book: Ruby on Rails",
      slug: "test-book-ruby-on-rails-#{SecureRandom.hex(4)}",
      sku: "BOOK-ROR-#{SecureRandom.hex(4)}",
      description: "A comprehensive guide to Ruby on Rails development",
      price: 29.99,
      stock: 50,
      stock_status: "in_stock",
      product_type: "physical",
      delivery_method: "shipping",
      status: "active"
    )
    @product.categories << [@carte, @fizic]
  end

  test "should add a product to cart from product page" do
    visit carti_path(@product.slug)

    assert_text @product.name
    click_button "Adauga in cos"

    # Should redirect to cart with product added
    assert_text "Coșul tău", wait: 5
    assert_text @product.name
  end

  test "should display product details" do
    visit carti_path(@product.slug)

    assert_text @product.name
    assert_text @product.description
    assert_text "29.99"
  end
end

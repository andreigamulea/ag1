require "application_system_test_case"

class AddingProductToCartTest < ApplicationSystemTestCase
  setup do
    @product = Product.create!(
      name: "Test Book: Ruby on Rails",
      slug: "test-book-ruby-on-rails",
      sku: "BOOK-ROR-001",
      description: "A comprehensive guide to Ruby on Rails development",
      price: 29.99,
      stock: 50,
      stock_status: "in_stock",
      product_type: "physical",
      delivery_method: "shipping"
    )
  end

  test "should add a product to cart" do
    visit root_path
    
    # Look for the product on the page
    assert_text @product.name
    
    # Click add to cart button
    click_button "Add to cart"
    
    # Verify the product was added to the cart
    assert_text "Product added to cart"
  end

  test "should display product details" do
    visit products_path
    
    # Check if the product is displayed
    assert_text @product.name
    assert_text @product.description
    assert_text "$#{@product.price}"
  end

  test "should update cart quantity" do
    visit root_path
    
    # Add product to cart
    assert_text @product.name
    click_button "Add to cart"
    
    # Navigate to cart
    click_link "Cart"
    
    # Verify the product is in the cart
    assert_text @product.name
    
    # Update quantity
    fill_in "quantity", with: 3
    click_button "Update Cart"
    
    # Verify the quantity was updated
    assert_text "3"
  end
end
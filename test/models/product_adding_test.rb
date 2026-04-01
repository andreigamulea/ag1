require 'test_helper'

class ProductAddingToCartTest < ActiveSupport::TestCase
  # Disable fixtures for this test
  self.use_transactional_tests = true

  def test_01_product_class_exists
    assert defined?(Product), "Product class should be defined"
  end

  def test_02_create_simple_product
    product = Product.new(name: "Book", slug: "book", sku: "BOOK-1", price: 10.0)
    assert product.save, "Should save product: #{product.errors.full_messages.join(', ')}"
  end

  def test_03_product_requires_name
    product = Product.new(slug: "test", sku: "TEST", price: 10.0)
    assert !product.valid?, "Product without name should be invalid"
  end

  def test_04_product_requires_price
    product = Product.new(name: "Book", slug: "book", sku: "BOOK-1")
    assert !product.valid?, "Product without price should be invalid"
  end
end
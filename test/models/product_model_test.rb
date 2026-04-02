require 'test_helper'

class ProductModelTest < ActiveSupport::TestCase
  def setup
    @product = Product.new(
      name: "Test Book: Ruby on Rails",
      slug: "test-book-ruby-on-rails",
      sku: "BOOK-ROR-001",
      price: 29.99
    )
  end

  test "product should be valid with all required attributes" do
    assert @product.valid?
  end

  test "product should be invalid without a name" do
    @product.name = nil
    assert_not @product.valid?
  end

  test "product should be invalid without a price" do
    @product.price = nil
    assert_not @product.valid?
  end

  test "product slug is auto-generated from name" do
    @product.slug = nil
    @product.valid?
    assert_equal @product.name.parameterize, @product.slug
  end

  test "product should be invalid without a sku" do
    @product.sku = nil
    assert_not @product.valid?
  end
end
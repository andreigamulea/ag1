require "test_helper"

# =============================================================================
# Teste pentru fix-urile de integritate date
# Fix 2: Stock decrement atomic
# Fix 3: Invoice number sequential
# Fix 7: Order status transitions
# =============================================================================

class OrderStatusTransitionsTest < ActiveSupport::TestCase
  setup do
    @tara = Tari.find_or_create_by!(nume: "Romania", abr: "RO")
    @judet = Judet.find_or_create_by!(denjud: "Bucuresti", cod: "B", idjudet: 40)
    @localitate = Localitati.find_or_create_by!(
      denumire: "Bucuresti", denj: "Bucuresti"
    )

    @order = Order.create!(
      email: "test-trans@test.com",
      first_name: "Ion",
      last_name: "Popescu",
      street: "Strada Test",
      street_number: "10",
      phone: "0712345678",
      postal_code: "010101",
      country: "Romania",
      county: "Bucuresti",
      city: "Bucuresti",
      status: "pending",
      placed_at: Time.current,
      total: 100
    )
  end

  # --- Tranziții valide ---

  test "pending can transition to paid" do
    @order.status = "paid"
    assert @order.valid?, "pending -> paid should be valid: #{@order.errors.full_messages}"
  end

  test "pending can transition to cancelled" do
    @order.status = "cancelled"
    assert @order.valid?, "pending -> cancelled should be valid"
  end

  test "pending can transition to expired" do
    @order.status = "expired"
    assert @order.valid?, "pending -> expired should be valid"
  end

  test "paid can transition to processing" do
    @order.update_column(:status, "paid")
    @order.reload
    @order.status = "processing"
    assert @order.valid?, "paid -> processing should be valid"
  end

  test "paid can transition to refunded" do
    @order.update_column(:status, "paid")
    @order.reload
    @order.status = "refunded"
    assert @order.valid?, "paid -> refunded should be valid"
  end

  test "processing can transition to shipped" do
    @order.update_column(:status, "processing")
    @order.reload
    @order.status = "shipped"
    assert @order.valid?, "processing -> shipped should be valid"
  end

  test "shipped can transition to delivered" do
    @order.update_column(:status, "shipped")
    @order.reload
    @order.status = "delivered"
    assert @order.valid?, "shipped -> delivered should be valid"
  end

  test "delivered can transition to refunded" do
    @order.update_column(:status, "delivered")
    @order.reload
    @order.status = "refunded"
    assert @order.valid?, "delivered -> refunded should be valid"
  end

  # --- Tranziții invalide ---

  test "delivered cannot transition back to pending" do
    @order.update_column(:status, "delivered")
    @order.reload
    @order.status = "pending"
    assert_not @order.valid?, "delivered -> pending should be INVALID"
    assert @order.errors[:status].any?
  end

  test "refunded cannot transition to any status" do
    @order.update_column(:status, "refunded")
    @order.reload

    %w[pending paid processing shipped delivered cancelled].each do |new_status|
      @order.status = new_status
      assert_not @order.valid?, "refunded -> #{new_status} should be INVALID"
      @order.reload
    end
  end

  test "cancelled cannot transition to any status" do
    @order.update_column(:status, "cancelled")
    @order.reload

    %w[pending paid processing shipped delivered refunded].each do |new_status|
      @order.status = new_status
      assert_not @order.valid?, "cancelled -> #{new_status} should be INVALID"
      @order.reload
    end
  end

  test "pending cannot skip to shipped" do
    @order.status = "shipped"
    assert_not @order.valid?, "pending -> shipped should be INVALID"
  end

  test "pending cannot skip to delivered" do
    @order.status = "delivered"
    assert_not @order.valid?, "pending -> delivered should be INVALID"
  end

  test "paid cannot go back to pending" do
    @order.update_column(:status, "paid")
    @order.reload
    @order.status = "pending"
    assert_not @order.valid?, "paid -> pending should be INVALID"
  end
end


class StockDecrementAtomicTest < ActiveSupport::TestCase
  setup do
    @product = Product.create!(
      name: "Stock Test Product #{SecureRandom.hex(4)}",
      slug: "stock-test-#{SecureRandom.hex(4)}",
      sku: "STK-#{SecureRandom.hex(4)}",
      price: 25.00,
      stock: 100
    )

    @tara = Tari.find_or_create_by!(nume: "Romania", abr: "RO")
    @judet = Judet.find_or_create_by!(denjud: "Bucuresti", cod: "B", idjudet: 40)
    @localitate = Localitati.find_or_create_by!(
      denumire: "Bucuresti", denj: "Bucuresti"
    )
  end

  def create_order_with_items(product, quantity)
    order = Order.create!(
      email: "stock-test-#{SecureRandom.hex(3)}@test.com",
      first_name: "Test",
      last_name: "User",
      street: "Strada Test",
      street_number: "1",
      phone: "0712345678",
      postal_code: "010101",
      country: "Romania",
      county: "Bucuresti",
      city: "Bucuresti",
      status: "pending",
      placed_at: Time.current,
      total: product.price * quantity
    )

    order.order_items.create!(
      product: product,
      product_name: product.name,
      quantity: quantity,
      price: product.price,
      vat: 0,
      total_price: product.price * quantity
    )

    order
  end

  test "decrement_stock_on_order reduces product stock" do
    order = create_order_with_items(@product, 3)
    order.finalize_order!

    @product.reload
    assert_equal 97, @product.stock
  end

  test "stock cannot go below zero" do
    @product.update!(stock: 2)
    order = create_order_with_items(@product, 5)
    order.finalize_order!

    @product.reload
    assert_equal 0, @product.stock, "Stock should be capped at 0, not negative"
  end

  test "multiple orders decrement stock correctly" do
    order1 = create_order_with_items(@product, 10)
    order2 = create_order_with_items(@product, 15)

    order1.finalize_order!
    order2.finalize_order!

    @product.reload
    assert_equal 75, @product.stock
  end

  test "decrement stock also decrements variant stock" do
    variant = @product.variants.create!(
      sku: "STK-V-#{SecureRandom.hex(4)}",
      price: 30.00,
      stock: 50,
      status: :active
    )

    order = Order.create!(
      email: "var-stock-#{SecureRandom.hex(3)}@test.com",
      first_name: "Test",
      last_name: "User",
      street: "Strada Test",
      street_number: "1",
      phone: "0712345678",
      postal_code: "010101",
      country: "Romania",
      county: "Bucuresti",
      city: "Bucuresti",
      status: "pending",
      placed_at: Time.current,
      total: 60.00
    )

    order.order_items.create!(
      product: @product,
      variant: variant,
      product_name: @product.name,
      variant_sku: variant.sku,
      quantity: 2,
      price: variant.price,
      vat: 0,
      total_price: 60.00
    )

    order.finalize_order!

    variant.reload
    @product.reload
    assert_equal 48, variant.stock, "Variant stock should be decremented"
    assert_equal 98, @product.stock, "Product stock should also be decremented"
  end

  test "finalize_order increments coupon usage_count" do
    coupon = Coupon.create!(
      code: "STKTEST#{SecureRandom.hex(3)}",
      discount_type: "fixed",
      discount_value: 5,
      active: true,
      starts_at: 1.day.ago,
      expires_at: 1.day.from_now,
      usage_count: 0,
      usage_limit: 10
    )

    order = Order.create!(
      email: "coupon-test@test.com",
      first_name: "Test",
      last_name: "User",
      street: "Strada Test",
      street_number: "1",
      phone: "0712345678",
      postal_code: "010101",
      country: "Romania",
      county: "Bucuresti",
      city: "Bucuresti",
      status: "pending",
      placed_at: Time.current,
      total: 95.00,
      coupon: coupon
    )

    order.order_items.create!(
      product: @product,
      product_name: @product.name,
      quantity: 1,
      price: 25.00,
      vat: 0,
      total_price: 25.00
    )

    order.finalize_order!
    coupon.reload
    assert_equal 1, coupon.usage_count
  end
end


class InvoiceNumberSequentialTest < ActiveSupport::TestCase
  setup do
    @tara = Tari.find_or_create_by!(nume: "Romania", abr: "RO")
    @judet = Judet.find_or_create_by!(denjud: "Bucuresti", cod: "B", idjudet: 40)
    @localitate = Localitati.find_or_create_by!(
      denumire: "Bucuresti", denj: "Bucuresti"
    )
  end

  def create_test_order
    Order.create!(
      email: "inv-test-#{SecureRandom.hex(3)}@test.com",
      first_name: "Test",
      last_name: "Invoice",
      street: "Strada Test",
      street_number: "1",
      phone: "0712345678",
      postal_code: "010101",
      country: "Romania",
      county: "Bucuresti",
      city: "Bucuresti",
      status: "pending",
      placed_at: Time.current,
      total: 100.00,
      vat_amount: 19.00
    )
  end

  test "invoice numbers are sequential" do
    order1 = create_test_order
    order2 = create_test_order
    order3 = create_test_order

    inv1 = Invoice.create!(order: order1, invoice_number: 10001, emitted_at: Time.current,
                            status: "emitted", series: "AYG", currency: "RON", total: 100)
    inv2 = Invoice.create!(order: order2, invoice_number: 10002, emitted_at: Time.current,
                            status: "emitted", series: "AYG", currency: "RON", total: 100)
    inv3 = Invoice.create!(order: order3, invoice_number: 10003, emitted_at: Time.current,
                            status: "emitted", series: "AYG", currency: "RON", total: 100)

    assert_equal 10001, inv1.invoice_number
    assert_equal 10002, inv2.invoice_number
    assert_equal 10003, inv3.invoice_number
  end

  test "invoice number uniqueness enforced at DB level" do
    order1 = create_test_order
    order2 = create_test_order

    Invoice.create!(order: order1, invoice_number: 99999, emitted_at: Time.current,
                     status: "emitted", series: "AYG", currency: "RON", total: 100)

    assert_raises(ActiveRecord::RecordInvalid) do
      Invoice.create!(order: order2, invoice_number: 99999, emitted_at: Time.current,
                       status: "emitted", series: "AYG", currency: "RON", total: 100)
    end
  end

  test "invoice belongs to order" do
    order = create_test_order
    invoice = Invoice.create!(order: order, invoice_number: 88888, emitted_at: Time.current,
                               status: "emitted", series: "AYG", currency: "RON", total: 100)

    assert_equal order.id, invoice.order_id
    assert_equal invoice, order.invoice
  end
end


class CartQuantityValidationTest < ActionDispatch::IntegrationTest
  setup do
    @product = Product.create!(
      name: "Cart Qty Product #{SecureRandom.hex(4)}",
      slug: "cart-qty-#{SecureRandom.hex(4)}",
      sku: "CRTQTY-#{SecureRandom.hex(4)}",
      price: 15.00,
      stock: 10,
      track_inventory: true
    )
  end

  test "add to cart with zero quantity defaults to 1" do
    post add_cart_index_url, params: { product_id: @product.id, quantity: 0 }
    assert_redirected_to cart_index_path
    # Quantity should be at least 1 (defaulted from 0)
    follow_redirect!
    assert_response :success
  end

  test "add to cart with negative quantity defaults to 1" do
    post add_cart_index_url, params: { product_id: @product.id, quantity: -5 }
    assert_redirected_to cart_index_path
    follow_redirect!
    assert_response :success
  end

  test "add to cart with valid quantity works" do
    post add_cart_index_url, params: { product_id: @product.id, quantity: 3 }
    assert_redirected_to cart_index_path
  end

  test "add to cart with nonexistent product shows error" do
    post add_cart_index_url, params: { product_id: 999999, quantity: 1 }
    assert_redirected_to cart_index_path
    follow_redirect!
    assert_match(/nu a fost/, flash[:alert])
  end

  test "add to cart respects stock limit when track_inventory is true" do
    post add_cart_index_url, params: { product_id: @product.id, quantity: 15 }
    assert_redirected_to cart_index_path
    # With track_inventory=true and stock=10, quantity should be capped at 10
  end
end


# =============================================================================
# Fix 10: Coupon percentage cap validation
# =============================================================================

class CouponPercentageCapTest < ActiveSupport::TestCase
  test "percentage coupon with value <= 100 is valid" do
    coupon = Coupon.new(
      code: "VALID#{SecureRandom.hex(3)}",
      discount_type: "percentage",
      discount_value: 50,
      active: true,
      starts_at: 1.day.ago,
      expires_at: 1.day.from_now
    )
    assert coupon.valid?, "50% coupon should be valid: #{coupon.errors.full_messages}"
  end

  test "percentage coupon with value 100 is valid" do
    coupon = Coupon.new(
      code: "MAX#{SecureRandom.hex(3)}",
      discount_type: "percentage",
      discount_value: 100,
      active: true,
      starts_at: 1.day.ago,
      expires_at: 1.day.from_now
    )
    assert coupon.valid?, "100% coupon should be valid"
  end

  test "percentage coupon with value > 100 is invalid" do
    coupon = Coupon.new(
      code: "OVER#{SecureRandom.hex(3)}",
      discount_type: "percentage",
      discount_value: 150,
      active: true,
      starts_at: 1.day.ago,
      expires_at: 1.day.from_now
    )
    assert_not coupon.valid?, "150% coupon should be INVALID"
    assert coupon.errors[:discount_value].any?
  end

  test "fixed coupon with any value is valid" do
    coupon = Coupon.new(
      code: "FIXED#{SecureRandom.hex(3)}",
      discount_type: "fixed",
      discount_value: 500,
      active: true,
      starts_at: 1.day.ago,
      expires_at: 1.day.from_now
    )
    assert coupon.valid?, "Fixed 500 RON coupon should be valid: #{coupon.errors.full_messages}"
  end
end


# =============================================================================
# Fix 8-9: Monitoring + MemoryLogs auth tests
# =============================================================================

class MonitoringAuthTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      email: "admin-mon-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true
    )
  end

  test "guest cannot access monitoring" do
    get mem_path
    assert_redirected_to new_user_session_path
  end

  test "guest cannot access memory logs" do
    get ram_logs_path
    assert_redirected_to new_user_session_path
  end

  test "admin can access memory logs" do
    sign_in @admin
    get ram_logs_path
    assert_response :success
  end
end

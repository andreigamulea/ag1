require "test_helper"

class Admin::OptionTypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # Create admin user with unique email
    @admin = User.create!(
      email: "admin-#{SecureRandom.hex(8)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true
    )
    sign_in @admin

    # Create option types
    @culoare = OptionType.create!(name: "Culoare", presentation: "Culoare", position: 0)
    @marime = OptionType.create!(name: "Marime", presentation: "Mărime", position: 1)

    # Add option values to Culoare
    @rosu = @culoare.option_values.create!(name: "Roșu", presentation: "Roșu", position: 0)
    @albastru = @culoare.option_values.create!(name: "Albastru", presentation: "Albastru", position: 1)
  end

  teardown do
    # Use delete_all to bypass associations and avoid cascade errors
    Variant.delete_all
    Product.delete_all
    User.delete_all
    OptionValue.delete_all
    OptionType.delete_all
    Order.delete_all
  end

  # INDEX tests
  test "should get index" do
    get admin_option_types_path
    assert_response :success
    assert_select "h1", "Option Types Management"
  end

  test "index should display option types" do
    get admin_option_types_path
    assert_response :success
    assert_match @culoare.name, response.body
    assert_match @marime.name, response.body
  end

  # NEW tests
  test "should get new" do
    get new_admin_option_type_path
    assert_response :success
    assert_select "h1", "New Option Type"
  end

  # CREATE tests
  test "should create option_type" do
    assert_difference("OptionType.count") do
      post admin_option_types_path, params: {
        option_type: {
          name: "Material",
          presentation: "Material",
          position: 2
        }
      }
    end

    assert_redirected_to edit_admin_option_type_path(OptionType.last)
    follow_redirect!
    assert_match "Material", response.body
  end

  test "should not create option_type with invalid params" do
    assert_no_difference("OptionType.count") do
      post admin_option_types_path, params: {
        option_type: { name: "" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should not create duplicate option_type" do
    assert_no_difference("OptionType.count") do
      post admin_option_types_path, params: {
        option_type: {
          name: "Culoare",
          presentation: "Culoare",
          position: 3
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # EDIT tests
  test "should get edit" do
    get edit_admin_option_type_path(@culoare)
    assert_response :success
    assert_select "h1", "Edit Option Type: #{@culoare.name}"
  end

  test "edit should show option values" do
    get edit_admin_option_type_path(@culoare)
    assert_response :success
    assert_match @rosu.name, response.body
    assert_match @albastru.name, response.body
  end

  # UPDATE tests
  test "should update option_type" do
    patch admin_option_type_path(@culoare), params: {
      option_type: { presentation: "Culoare Updated" }
    }

    assert_redirected_to edit_admin_option_type_path(@culoare)
    @culoare.reload
    assert_equal "Culoare Updated", @culoare.presentation
  end

  test "should not update option_type with invalid params" do
    patch admin_option_type_path(@culoare), params: {
      option_type: { name: "" }
    }

    assert_response :unprocessable_entity
    @culoare.reload
    assert_equal "Culoare", @culoare.name
  end

  # DELETE tests
  test "should delete unused option_type" do
    unused = OptionType.create!(name: "Unused", presentation: "Unused", position: 10)

    assert_difference("OptionType.count", -1) do
      delete admin_option_type_path(unused)
    end

    assert_redirected_to admin_option_types_path
  end

  test "should not delete option_type used by products" do
    product = Product.create!(
      name: "Test Product",
      slug: "test-#{Time.now.to_i}",
      sku: "TEST",
      price: 10.0,
      status: "active"
    )
    product.product_option_types.create!(option_type: @culoare)

    assert_no_difference("OptionType.count") do
      delete admin_option_type_path(@culoare)
    end

    assert_redirected_to admin_option_types_path
    assert_match /Cannot delete/, flash[:alert]

    product.destroy
  end

  # AUTHORIZATION tests
  test "should redirect non-admin users" do
    sign_out @admin

    non_admin = User.create!(
      email: "user-#{SecureRandom.hex(8)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 0,
      active: true
    )
    sign_in non_admin

    get admin_option_types_path
    assert_redirected_to root_path

    non_admin.destroy
  end

  test "should redirect unauthenticated users" do
    sign_out @admin

    get admin_option_types_path
    assert_redirected_to new_user_session_path
  end
end

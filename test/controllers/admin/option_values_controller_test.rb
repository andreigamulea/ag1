require "test_helper"

class Admin::OptionValuesControllerTest < ActionDispatch::IntegrationTest
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

    # Create option type
    @culoare = OptionType.create!(name: "Culoare", presentation: "Culoare", position: 0)
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

  # CREATE tests
  test "should create option_value" do
    assert_difference("@culoare.option_values.count") do
      post admin_option_type_option_values_path(@culoare), params: {
        option_value: {
          name: "Verde",
          presentation: "Verde",
          position: 2
        }
      }
    end

    assert_redirected_to edit_admin_option_type_path(@culoare)
    follow_redirect!
    assert_match "Verde", response.body
  end

  test "should auto-assign position when creating" do
    post admin_option_type_option_values_path(@culoare), params: {
      option_value: {
        name: "Negru",
        presentation: "Negru",
        position: 999
      }
    }

    new_value = @culoare.option_values.find_by(name: "Negru")
    # Position should be auto-calculated (max + 1)
    assert new_value.position >= 2
  end

  test "should not create option_value with invalid params" do
    assert_no_difference("@culoare.option_values.count") do
      post admin_option_type_option_values_path(@culoare), params: {
        option_value: { name: "" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should not create duplicate option_value in same option_type" do
    assert_no_difference("@culoare.option_values.count") do
      post admin_option_type_option_values_path(@culoare), params: {
        option_value: {
          name: "Roșu",
          presentation: "Roșu Duplicate",
          position: 10
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # UPDATE tests
  test "should update option_value" do
    patch admin_option_type_option_value_path(@culoare, @rosu), params: {
      option_value: { presentation: "Roșu Intens" }
    }

    assert_redirected_to edit_admin_option_type_path(@culoare)
    @rosu.reload
    assert_equal "Roșu Intens", @rosu.presentation
  end

  test "should not update option_value with invalid params" do
    original_name = @rosu.name

    patch admin_option_type_option_value_path(@culoare, @rosu), params: {
      option_value: { name: "" }
    }

    assert_response :unprocessable_entity
    @rosu.reload
    assert_equal original_name, @rosu.name
  end

  # DELETE tests
  test "should delete unused option_value" do
    assert_difference("@culoare.option_values.count", -1) do
      delete admin_option_type_option_value_path(@culoare, @rosu)
    end

    assert_redirected_to edit_admin_option_type_path(@culoare)
  end

  test "should not delete option_value used by variants" do
    # Create product with variant using this option_value
    product = Product.create!(
      name: "Test Product",
      slug: "test-#{Time.now.to_i}",
      sku: "TEST",
      price: 10.0,
      status: "active"
    )

    variant = product.variants.create!(
      sku: "VAR-#{Time.now.to_i}",
      price: 10.0,
      stock: 5,
      vat_rate: 19.0,
      status: 0
    )
    variant.option_values << @rosu

    assert_no_difference("@culoare.option_values.count") do
      delete admin_option_type_option_value_path(@culoare, @rosu)
    end

    assert_redirected_to edit_admin_option_type_path(@culoare)
    assert_match /Cannot delete/, flash[:alert]

    # Clean up: delete variant first, then product
    variant.delete
    product.delete
  end

  # AUTHORIZATION tests
  test "should redirect non-admin users on create" do
    sign_out @admin

    non_admin = User.create!(
      email: "user-#{SecureRandom.hex(8)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 0,
      active: true
    )
    sign_in non_admin

    post admin_option_type_option_values_path(@culoare), params: {
      option_value: { name: "Test", presentation: "Test", position: 5 }
    }

    assert_redirected_to root_path

    non_admin.destroy
  end

  test "should redirect unauthenticated users on delete" do
    sign_out @admin

    delete admin_option_type_option_value_path(@culoare, @rosu)
    assert_redirected_to new_user_session_path
  end
end

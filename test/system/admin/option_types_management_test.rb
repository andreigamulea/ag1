require "application_system_test_case"

class Admin::OptionTypesManagementTest < ApplicationSystemTestCase
  setup do
    # Create admin user with unique email
    @admin = User.create!(
      email: "admin-#{SecureRandom.hex(8)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true
    )

    # Sign in
    visit new_user_session_path
    fill_in "Email", with: @admin.email
    fill_in "user[password]", with: "password123"
    click_button "Intră în cont"

    # Use unique names with a suffix to avoid collisions with seed data
    @suffix = SecureRandom.hex(4)

    @culoare = OptionType.create!(name: "Culoare-#{@suffix}", presentation: "Culoare", position: 0)
    @culoare.option_values.create!([
      { name: "Roșu-#{@suffix}", presentation: "Roșu", position: 0 },
      { name: "Albastru-#{@suffix}", presentation: "Albastru", position: 1 }
    ])

    @marime = OptionType.create!(name: "Marime-#{@suffix}", presentation: "Mărime", position: 1)
    @marime.option_values.create!([
      { name: "S-#{@suffix}", presentation: "S", position: 0 },
      { name: "M-#{@suffix}", presentation: "M", position: 1 },
      { name: "L-#{@suffix}", presentation: "L", position: 2 }
    ])
  end

  test "visiting the index shows existing option types" do
    visit admin_option_types_path

    assert_selector "h1", text: "Option Types Management"
    assert_text @culoare.name
    assert_text @marime.name
  end

  test "can navigate to new option type form" do
    visit admin_option_types_path

    click_link "New Option Type"

    assert_selector "h1", text: "New Option Type"
    assert_selector "input[name='option_type[name]']"
    assert_selector "input[name='option_type[presentation]']"
    assert_selector "input[name='option_type[position]']"
  end

  test "can navigate to edit option type page" do
    visit admin_option_types_path

    # Click the first Edit link that matches our test option type
    within(".option-type-card", text: @culoare.name) do
      click_link "Edit"
    end

    assert_selector "h1", text: /Edit Option Type:/
    assert_text @culoare.name
  end

  test "edit page shows option values" do
    visit edit_admin_option_type_path(@culoare)

    assert_selector "h1", text: "Edit Option Type: #{@culoare.name}"
    assert_text "Roșu"
    assert_text "Albastru"

    # Check table structure
    within "table" do
      assert_text "Name"
      assert_text "Display"
      assert_text "Position"
    end
  end

  test "edit page has form to add new option value" do
    visit edit_admin_option_type_path(@culoare)

    assert_selector "h3", text: "Add New Option Value"
    within "form[action='#{admin_option_type_option_values_path(@culoare)}']" do
      assert_selector "input[name='option_value[name]']"
      assert_selector "input[name='option_value[presentation]']"
      assert_selector "input[name='option_value[position]']"
    end
  end

  test "can create new option type via UI" do
    material_name = "Material-#{@suffix}"
    visit admin_option_types_path

    click_link "New Option Type"

    within "form[action='#{admin_option_types_path}']" do
      fill_in "option_type[name]", with: material_name
      fill_in "option_type[presentation]", with: "Material"
      fill_in "option_type[position]", with: "2"
      click_button "Create Option Type"
    end

    # Should redirect to edit page
    assert_selector "h1", text: "Edit Option Type: #{material_name}"
  end

  test "can add option value via UI" do
    visit edit_admin_option_type_path(@culoare)

    within "form[action='#{admin_option_type_option_values_path(@culoare)}']" do
      fill_in "option_value[name]", with: "Verde-#{@suffix}"
      fill_in "option_value[presentation]", with: "Verde"
      click_button "Add Value"
    end

    # Verify it appears in the table
    within "table" do
      assert_text "Verde"
    end
  end

  test "navigation from admin panel works" do
    visit admin_path

    assert_text "Panou administrare"

    click_link "Option Types (Culoare, Mărime)"

    assert_current_path admin_option_types_path
    assert_text "Option Types Management"
  end

  test "index shows usage statistics" do
    # Create product using our test Culoare option type
    product = Product.create!(
      name: "Test Product #{@suffix}",
      slug: "test-#{@suffix}-#{Time.now.to_i}",
      sku: "TEST-#{@suffix}",
      price: 10.0,
      status: "active"
    )
    product.product_option_types.create!(option_type: @culoare)

    visit admin_option_types_path

    within(".option-type-card", text: @culoare.name) do
      assert_text "1 products"
    end
  end
end

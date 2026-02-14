require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(
      email: "admin-users-#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      password_confirmation: "password123",
      role: 1,
      active: true
    )
  end

  test "should get index when admin" do
    sign_in @admin
    get users_path
    assert_response :success
  end

  test "should redirect index when not signed in" do
    get users_path
    assert_response :redirect
  end
end

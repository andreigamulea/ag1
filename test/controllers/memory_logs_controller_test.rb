require "test_helper"

class MemoryLogsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get memory_logs_index_url
    assert_response :success
  end
end

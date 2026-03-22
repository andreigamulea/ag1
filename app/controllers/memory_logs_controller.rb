class MemoryLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin

  # Memory logs is admin only
  def is_admin_page?
    true
  end

  def index
  @logs = MemoryLog.order(created_at: :desc).limit(50)
  @memory_logs = MemoryLog.order(created_at: :desc).limit(50)
end
end

class MemoryLogsController < ApplicationController
  # Memory logs is admin only
  def is_admin_page?
    true
  end

  def index
  @logs = MemoryLog.order(created_at: :desc).limit(50)
  @memory_logs = MemoryLog.order(created_at: :desc).limit(50)
end
end

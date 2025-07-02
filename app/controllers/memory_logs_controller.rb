class MemoryLogsController < ApplicationController
    def index
  @logs = MemoryLog.order(created_at: :desc).limit(50)
  @memory_logs = MemoryLog.order(created_at: :desc).limit(50)
end
end

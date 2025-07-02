class AddMemoryUsageToMemoryLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :memory_logs, :used_memory_mb, :float
    add_column :memory_logs, :freed_memory_mb, :float
  end
end

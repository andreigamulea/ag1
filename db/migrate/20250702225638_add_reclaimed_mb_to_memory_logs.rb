class AddReclaimedMbToMemoryLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :memory_logs, :reclaimed_mb, :float
  end
end

class AddNotesToMemoryLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :memory_logs, :notes, :string
  end
end

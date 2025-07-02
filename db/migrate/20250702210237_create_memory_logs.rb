class CreateMemoryLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :memory_logs do |t|
      t.float :used_mb
      t.float :available_mb
      t.string :note

      t.timestamps
    end
  end
end

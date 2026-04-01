class AddAdminPreferencesToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :admin_preferences, :jsonb, default: {}
  end
end

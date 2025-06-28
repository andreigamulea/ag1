class AddRequiresLoginToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :requires_login, :boolean, default: false
  end
end

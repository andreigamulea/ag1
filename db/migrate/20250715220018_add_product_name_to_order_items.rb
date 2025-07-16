class AddProductNameToOrderItems < ActiveRecord::Migration[7.1]
  def change
    add_column :order_items, :product_name, :string
  end
end

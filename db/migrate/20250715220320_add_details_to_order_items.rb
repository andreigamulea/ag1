class AddDetailsToOrderItems < ActiveRecord::Migration[7.1]
  def change
    add_column :order_items, :unit_price, :decimal
    add_column :order_items, :total_price, :decimal
    # add_column :order_items, :product_name, :string # ← deja există, o comentăm
  end
end

class ChangeProductIdInOrderItemsToBeNullable < ActiveRecord::Migration[7.1]
  def change
    change_column_null :order_items, :product_id, true
  end
end

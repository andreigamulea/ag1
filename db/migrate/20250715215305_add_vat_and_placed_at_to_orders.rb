class AddVatAndPlacedAtToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :vat_amount, :decimal
    add_column :orders, :placed_at, :datetime
  end
end

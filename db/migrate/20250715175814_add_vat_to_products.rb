class AddVatToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :vat, :decimal, precision: 4, scale: 2, default: 0.0
  end
end

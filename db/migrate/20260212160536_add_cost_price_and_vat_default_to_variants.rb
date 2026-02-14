class AddCostPriceAndVatDefaultToVariants < ActiveRecord::Migration[7.1]
  def change
    add_column :variants, :cost_price, :decimal, precision: 10, scale: 2
  end
end

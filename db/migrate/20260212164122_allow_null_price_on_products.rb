class AllowNullPriceOnProducts < ActiveRecord::Migration[7.1]
  def change
    change_column_null :products, :price, true
  end
end

class AddPromoActiveToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :promo_active, :boolean, default: false, null: false
  end
end

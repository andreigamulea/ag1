class AddPromoFieldsToVariants < ActiveRecord::Migration[7.1]
  def change
    add_column :variants, :discount_price, :decimal, precision: 10, scale: 2
    add_column :variants, :promo_active, :boolean, default: false, null: false
  end
end

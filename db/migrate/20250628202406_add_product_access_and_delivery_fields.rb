class AddProductAccessAndDeliveryFields < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :delivery_method, :string, default: "shipping"
    add_column :products, :visible_to_guests, :boolean, default: true
    add_column :products, :taxable, :boolean, default: false
    add_column :products, :coupon_applicable, :boolean, default: true
  end
end

class AddPrimaryToProductOptionTypes < ActiveRecord::Migration[7.1]
  def change
    add_column :product_option_types, :primary, :boolean, default: false, null: false
  end
end

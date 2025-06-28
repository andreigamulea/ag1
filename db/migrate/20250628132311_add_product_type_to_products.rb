class AddProductTypeToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :product_type, :string, default: "physical"
  end
end

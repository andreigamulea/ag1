class AddBrandAndViewsCountToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :brand, :string
    add_column :products, :views_count, :integer, default: 0
  end
end

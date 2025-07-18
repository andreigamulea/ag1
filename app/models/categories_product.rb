# app/models/categories_product.rb
class CategoriesProduct < ApplicationRecord
  self.table_name = 'categories_products'  # important!

  belongs_to :product
  belongs_to :category
end

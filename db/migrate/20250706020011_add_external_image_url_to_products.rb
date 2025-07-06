class AddExternalImageUrlToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :external_image_url, :string
  end
end

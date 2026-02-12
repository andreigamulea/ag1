class AddExternalImageUrlToVariants < ActiveRecord::Migration[7.1]
  def change
    add_column :variants, :external_image_url, :string
  end
end

class AddExternalImageUrlsToVariants < ActiveRecord::Migration[7.1]
  def change
    add_column :variants, :external_image_urls, :text, array: true, default: []
  end
end

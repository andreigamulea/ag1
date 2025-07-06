class AddExternalFileUrlsToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :external_file_urls, :text, array: true, default: []
  end
end

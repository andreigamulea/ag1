class AddSeoFieldsToCategories < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :description, :text
    add_column :categories, :meta_title, :string
    add_column :categories, :meta_description, :string
  end
end

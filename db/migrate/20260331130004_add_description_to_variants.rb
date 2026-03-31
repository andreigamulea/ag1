class AddDescriptionToVariants < ActiveRecord::Migration[7.1]
  def change
    add_column :variants, :description_title, :string
    add_column :variants, :description, :text
  end
end

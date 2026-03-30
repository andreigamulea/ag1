class AddDimensionsToVariants < ActiveRecord::Migration[7.1]
  def change
    add_column :variants, :height, :integer
    add_column :variants, :width, :integer
    add_column :variants, :depth, :integer
    add_column :variants, :weight, :integer
  end
end

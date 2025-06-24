class FixAttributesColumnInProducts < ActiveRecord::Migration[7.1]
  def change
    remove_column :products, :attributes, :jsonb
    add_column :products, :custom_attributes, :jsonb, default: {}, null: false
  end
end

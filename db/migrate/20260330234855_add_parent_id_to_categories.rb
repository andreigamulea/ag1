class AddParentIdToCategories < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :parent_id, :bigint, null: true
    add_index :categories, :parent_id
    add_foreign_key :categories, :categories, column: :parent_id, on_delete: :nullify
  end
end

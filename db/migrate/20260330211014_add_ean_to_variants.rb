class AddEanToVariants < ActiveRecord::Migration[7.1]
  def change
    add_column :variants, :ean, :string
    add_index :variants, :ean, unique: true, where: "ean IS NOT NULL AND ean != ''", name: "idx_unique_ean"
  end
end

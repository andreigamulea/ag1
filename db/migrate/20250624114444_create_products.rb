class CreateProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :products do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.string  :description_title
      t.text    :description

      t.decimal :price, precision: 10, scale: 2, null: false
      t.decimal :cost_price, precision: 10, scale: 2
      t.decimal :discount_price, precision: 10, scale: 2

      t.string  :sku, null: false
      t.integer :stock, default: 0
      t.boolean :track_inventory, default: true
      t.string  :stock_status, default: "in_stock"
      t.boolean :sold_individually, default: false

      t.date    :available_on
      t.date    :discontinue_on

      t.decimal :height, precision: 8, scale: 2
      t.decimal :width, precision: 8, scale: 2
      t.decimal :depth, precision: 8, scale: 2
      t.decimal :weight, precision: 8, scale: 2

      t.string  :meta_title
      t.string  :meta_description
      t.string  :meta_keywords

      t.string  :status, default: "active"
      t.boolean :featured, default: false

      t.jsonb   :attributes, default: {}, null: false

      t.timestamps
    end

    add_index :products, :slug, unique: true
  end
end

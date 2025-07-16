class CreateCoupons < ActiveRecord::Migration[7.1]
  def change
    create_table :coupons do |t|
      t.string :code
      t.string :discount_type
      t.decimal :discount_value
      t.boolean :active
      t.datetime :starts_at
      t.datetime :expires_at
      t.integer :usage_limit
      t.integer :usage_count
      t.decimal :minimum_cart_value
      t.integer :minimum_quantity
      t.integer :product_id
      t.boolean :free_shipping

      t.timestamps
    end
  end
end

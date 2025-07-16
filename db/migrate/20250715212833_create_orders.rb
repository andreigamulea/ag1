class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.string :email
      t.string :name
      t.string :phone
      t.text :address
      t.string :city
      t.string :postal_code
      t.string :country
      t.decimal :total
      t.string :status
      t.text :notes

      t.timestamps
    end
  end
end

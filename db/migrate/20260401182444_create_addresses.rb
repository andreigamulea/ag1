class CreateAddresses < ActiveRecord::Migration[7.1]
  def change
    create_table :addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :address_type, default: "shipping", null: false
      t.string  :first_name
      t.string  :last_name
      t.string  :company_name
      t.string  :cui
      t.string  :phone
      t.string  :email
      t.string  :country
      t.string  :county
      t.string  :city
      t.string  :postal_code
      t.string  :street
      t.string  :street_number
      t.text    :block_details
      t.string  :label
      t.boolean :default, default: false, null: false
      t.timestamps
    end

    add_index :addresses, [:user_id, :address_type]
  end
end

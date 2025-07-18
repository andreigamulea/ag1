class AddBillingAndShippingFieldsToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :first_name, :string
    add_column :orders, :last_name, :string
    add_column :orders, :company_name, :string
    add_column :orders, :cui, :string
    add_column :orders, :cnp, :string
    add_column :orders, :county, :string
    add_column :orders, :street, :string
    add_column :orders, :street_number, :string
    add_column :orders, :block_details, :text
    add_column :orders, :shipping_first_name, :string
    add_column :orders, :shipping_last_name, :string
    add_column :orders, :shipping_company_name, :string
    add_column :orders, :shipping_country, :string
    add_column :orders, :shipping_county, :string
    add_column :orders, :shipping_city, :string
    add_column :orders, :shipping_street, :string
    add_column :orders, :shipping_street_number, :string
    add_column :orders, :shipping_block_details, :text
    add_column :orders, :shipping_postal_code, :string
    add_column :orders, :shipping_phone, :string
  end
end

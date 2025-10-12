class AddFieldsToInvoices < ActiveRecord::Migration[7.1]  # Ajustează versiunea Rails (ex: 7.1)
  def change
    add_column :invoices, :series, :string
    add_column :invoices, :due_date, :datetime
    add_column :invoices, :payment_method, :string
    add_column :invoices, :currency, :string, default: 'RON'
  end
end
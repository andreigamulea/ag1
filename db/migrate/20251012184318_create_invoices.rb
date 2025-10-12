class CreateInvoices < ActiveRecord::Migration[7.1]  # Ajustează versiunea Rails
  def change
    create_table :invoices do |t|
      t.references :order, null: false, foreign_key: true
      t.integer :invoice_number
      t.datetime :emitted_at
      t.string :status
      t.decimal :total
      t.decimal :vat_amount
      t.text :notes

      t.timestamps
    end
    add_index :invoices, :invoice_number, unique: true
  end
end
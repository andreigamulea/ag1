class CreateLocalitatis < ActiveRecord::Migration[7.1]
  def change
    create_table :localitatis do |t|
      t.string  :cod
      t.integer :judetid
      t.string  :denumire
      t.string  :denj
      t.string  :abr
      t.string  :cod_vechi

      t.timestamps
    end
  end
end

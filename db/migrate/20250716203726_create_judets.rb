class CreateJudets < ActiveRecord::Migration[7.1]
  def change
    create_table :judets do |t|
      t.string  :oasp
      t.string  :denjud
      t.string  :cod
      t.integer :idjudet
      t.string  :cod_j

      t.timestamps
    end
  end
end

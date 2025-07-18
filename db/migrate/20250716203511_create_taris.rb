class CreateTaris < ActiveRecord::Migration[7.1]
 def change
    create_table :taris do |t|
      t.string :nume
      t.string :abr

      t.timestamps
    end
  end
end

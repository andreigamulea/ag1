class CreateNewsletters < ActiveRecord::Migration[7.1]
  def change
    create_table :newsletters do |t|
      t.string :nume
      t.string :email
      t.boolean :validat

      t.timestamps
    end
  end
end

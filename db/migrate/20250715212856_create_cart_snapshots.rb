class CreateCartSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :cart_snapshots do |t|
      t.references :user, null: false, foreign_key: true
      t.string :email
      t.string :session_id
      t.jsonb :cart_data
      t.string :status

      t.timestamps
    end
  end
end

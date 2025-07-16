class MakeUserIdNullableInCartSnapshots < ActiveRecord::Migration[7.1]
  def change
    change_column_null :cart_snapshots, :user_id, true
  end
end

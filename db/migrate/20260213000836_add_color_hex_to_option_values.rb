class AddColorHexToOptionValues < ActiveRecord::Migration[7.1]
  def change
    add_column :option_values, :color_hex, :string
  end
end

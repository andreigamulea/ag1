class CreateFeeds < ActiveRecord::Migration[7.1]
  def change
    create_table :feeds do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :feed_type, null: false, default: 'rss'
      t.string :format_type, null: false, default: 'xml'
      t.integer :status, null: false, default: 0
      t.string :title
      t.text :description
      t.string :link
      t.string :language, default: 'ro'
      t.string :currency, default: 'RON'
      t.boolean :include_variants, default: false
      t.boolean :include_out_of_stock, default: false
      t.text :category_ids
      t.jsonb :custom_filters, default: {}
      t.integer :products_limit
      t.datetime :last_generated_at

      t.timestamps
    end

    add_index :feeds, :slug, unique: true
    add_index :feeds, :feed_type
    add_index :feeds, :status
  end
end

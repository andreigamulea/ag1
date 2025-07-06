class Product < ApplicationRecord
  #has_many_attached :attached_files
  has_and_belongs_to_many :categories

  enum stock_status: { in_stock: "in_stock", out_of_stock: "out_of_stock" }

  validates :name, :slug, :price, :sku, presence: true

  enum product_type: {
    physical: "physical",
    digital: "digital"
  }

  enum delivery_method: {
    shipping: "shipping",
    produs_digital: "produs digital",
    download: "download",
    external_link: "external_link"
  }
end

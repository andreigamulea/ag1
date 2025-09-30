class Product < ApplicationRecord
  #has_many_attached :attached_files
  has_and_belongs_to_many :categories
  has_many :order_items, dependent: :restrict_with_exception

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

  def price_breakdown
    vat_rate = vat.to_f
    return { brut: price.to_f, net: price.to_f, tva: 0.0 } if vat_rate <= 0

    brut = price.to_f
    net = brut / (1 + vat_rate / 100)
    tva_value = brut - net

    {
      brut: brut.round(2),
      net: net.round(2),
      tva: tva_value.round(2)
    }
  end
end

class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product
  validate :stock_available
  
  def total_price
    price.to_f * quantity
  end

  def net_price
    return price if vat.to_f <= 0
    price / (1 + vat / 100)
  end

  def total_net
    net_price * quantity
  end

  def total_vat
    total_price - total_net
  end

  # app/models/order_item.rb


def stock_available
  if product&.track_inventory && quantity.to_i > product.stock.to_i
    errors.add(:quantity, "depășește stocul disponibil")
  end
end

end

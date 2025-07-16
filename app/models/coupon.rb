class Coupon < ApplicationRecord
  enum discount_type: { fixed: "fixed", percentage: "percentage" }

  belongs_to :product, optional: true

  validates :code, presence: true, uniqueness: true
  validates :discount_type, inclusion: { in: discount_types.keys }
  validates :discount_value, numericality: { greater_than: 0 }
  validates :starts_at, :expires_at, presence: true

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def not_started?
    starts_at.present? && starts_at > Time.current
  end

  def usable?
    active && !expired? && !not_started? &&
      (usage_limit.nil? || usage_count.to_i < usage_limit)
  end

  def conditions_met?(cart:)
    total = cart.sum { |item| item[:price] * item[:quantity] }

    product_condition = product_id.nil? || cart.any? { |item| item[:product_id] == product_id }
    quantity_condition = minimum_quantity.nil? || cart.any? do |item|
      item[:product_id] == product_id && item[:quantity] >= minimum_quantity
    end
    cart_value_condition = minimum_cart_value.nil? || total >= minimum_cart_value

    product_condition && quantity_condition && cart_value_condition
  end

  def apply_to_cart(cart)
    return cart unless usable? && conditions_met?(cart: cart)

    cart.map do |item|
      next item unless applicable_to_product?(item)

      discounted_price = if fixed?
        [item[:price] - discount_value, 0].max
      else
        item[:price] * (1 - discount_value / 100)
      end

      item.merge(price: discounted_price.round(2))
    end
  end

  def applicable_to_product?(item)
    product_id.nil? || item[:product_id] == product_id
  end

  # app/models/coupon.rb
def active?
  self.expires_at.nil? || self.expires_at > Time.current
end

end

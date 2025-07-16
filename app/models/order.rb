class Order < ApplicationRecord
  belongs_to :user, optional: true
  has_many :order_items, dependent: :destroy

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, :address, :city, :country, presence: true
  validates :postal_code, length: { in: 4..10 }, allow_blank: true
  validates :status, presence: true

  enum status: {
    pending: "pending",
    paid: "paid",
    processing: "processing",
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled",
    refunded: "refunded"
  }

  def total_items
    order_items.sum(:quantity)
  end

  def total_vat
    order_items.sum { |item| item.vat.to_f * item.quantity }
  end
end

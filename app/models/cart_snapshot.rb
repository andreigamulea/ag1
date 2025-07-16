class CartSnapshot < ApplicationRecord
  belongs_to :user, optional: true

  validates :session_id, presence: true
  validates :cart_data, presence: true

  enum status: { active: "active", converted: "converted", expired: "expired" }
end

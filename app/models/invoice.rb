class Invoice < ApplicationRecord
  belongs_to :order
  validates :invoice_number, uniqueness: true, presence: true
end

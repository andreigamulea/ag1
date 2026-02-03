# frozen_string_literal: true

class ProductOptionType < ApplicationRecord
  belongs_to :product
  belongs_to :option_type

  validates :option_type_id, uniqueness: { scope: :product_id }

  default_scope { order(:position) }
end

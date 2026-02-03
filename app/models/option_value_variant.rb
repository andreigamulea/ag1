# frozen_string_literal: true

class OptionValueVariant < ApplicationRecord
  belongs_to :variant
  belongs_to :option_value

  validates :option_value_id, uniqueness: { scope: :variant_id }
end

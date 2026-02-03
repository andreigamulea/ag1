# frozen_string_literal: true

class OptionValue < ApplicationRecord
  belongs_to :option_type
  has_many :option_value_variants, dependent: :restrict_with_exception
  has_many :variants, through: :option_value_variants

  validates :name, presence: true
  validates :name, uniqueness: { scope: :option_type_id }

  default_scope { order(:position) }

  # Display name: folosește presentation dacă există, altfel name
  def display_name
    presentation.presence || name
  end
end

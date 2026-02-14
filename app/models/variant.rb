# frozen_string_literal: true

class Variant < ApplicationRecord
  belongs_to :product
  has_many :option_value_variants, dependent: :destroy
  has_many :option_values, through: :option_value_variants
  has_many :order_items, dependent: :nullify
  has_many :external_ids, class_name: 'VariantExternalId', dependent: :destroy

  enum :status, { active: 0, inactive: 1 }, default: :active

  validates :sku, presence: true
  validates :sku, uniqueness: { scope: :product_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  before_save :compute_options_digest

  # Generează digest pentru combinația de opțiuni (pentru unicitate)
  def compute_options_digest
    ids = option_value_variants.map(&:option_value_id).sort
    self.options_digest = ids.any? ? Digest::SHA256.hexdigest(ids.join('-')) : nil
  end

  # Text pentru afișare: "Culoare: Roșu, Mărime: M"
  def options_text
    option_values.includes(:option_type).map do |ov|
      "#{ov.option_type.name}: #{ov.display_name}"
    end.join(', ')
  end

  # Returns the active price: discount_price if promo is active, otherwise regular price
  def effective_price
    if promo_active? && discount_price.present? && discount_price > 0
      discount_price
    else
      price
    end
  end

  # Calculează breakdown-ul de preț cu TVA
  def price_breakdown
    rate = vat_rate.to_f
    return { brut: price.to_f, net: price.to_f, tva: 0.0 } if rate <= 0

    brut = price.to_f
    net = brut / (1 + rate / 100)
    tva_value = brut - net

    {
      brut: brut.round(2),
      net: net.round(2),
      tva: tva_value.round(2)
    }
  end
end

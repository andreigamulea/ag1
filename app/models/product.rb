class Product < ApplicationRecord
  #has_many_attached :attached_files
  has_and_belongs_to_many :categories
  has_many :order_items, dependent: :restrict_with_exception

  # Variant system associations
  has_many :variants, dependent: :restrict_with_exception
  has_many :product_option_types, -> { order(:position) }, dependent: :destroy
  has_many :option_types, through: :product_option_types

  accepts_nested_attributes_for :variants, allow_destroy: true,
    reject_if: proc { |attrs|
      id = attrs['id'] || attrs[:id]
      destroying = ActiveModel::Type::Boolean.new.cast(attrs['_destroy'] || attrs[:_destroy])
      if id.present? || destroying
        false
      else
        option_ids = Array(attrs['option_value_ids'] || attrs[:option_value_ids]).reject(&:blank?)
        sku   = attrs['sku']   || attrs[:sku]
        price = attrs['price'] || attrs[:price]
        stock = attrs['stock'] || attrs[:stock]
        sku.blank? && price.blank? && stock.blank? && option_ids.empty?
      end
    }

  enum stock_status: { in_stock: "in_stock", out_of_stock: "out_of_stock" }

  before_validation :generate_slug

  validates :name, presence: true, length: { minimum: 2 }
  validates :slug, presence: true, uniqueness: true
  validates :sku, presence: true, uniqueness: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }, unless: :has_any_variants?
  validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }, unless: :has_any_variants?
  validates :vat, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :must_have_one_primary_option_type, if: :has_active_variants?
  validate :no_duplicate_variant_options

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

  # Archive product: deactivate all variants, set status to 'archived'.
  # LOCK ORDER: P -> V* (ORDER BY id)
  def archive!
    transaction do
      lock!
      locked_variant_ids = variants.order(:id).lock.pluck(:id)
      Variant.where(id: locked_variant_ids).update_all(status: Variant.statuses[:inactive]) if locked_variant_ids.any?
      update_column(:status, 'archived')
    end
  end

  def archived?
    status == 'archived'
  end

  # Unarchive product: reactivate all variants, set status to 'active'.
  # LOCK ORDER: P -> V* (ORDER BY id)
  def unarchive!
    transaction do
      lock!
      locked_variant_ids = variants.order(:id).lock.pluck(:id)
      Variant.where(id: locked_variant_ids).update_all(status: Variant.statuses[:active]) if locked_variant_ids.any?
      update!(status: 'active')
    end
  end

  def to_param
    slug
  end

  def primary_option_type
    product_option_types.find_by(primary: true)&.option_type
  end

  def primary_product_option_type
    product_option_types.find_by(primary: true)
  end

  private

  def has_active_variants?
    if new_record? || variants.loaded?
      variants.reject(&:marked_for_destruction?).any?(&:active?)
    else
      variants.active.exists?
    end
  end

  def has_any_variants?
    if new_record? || variants.loaded?
      variants.reject(&:marked_for_destruction?).any?
    else
      variants.exists?
    end
  end

  def generate_slug
    self.slug = name.parameterize if slug.blank? && name.present?
  end

  def no_duplicate_variant_options
    active_variants = variants.reject(&:marked_for_destruction?).select(&:active?)
    return if active_variants.size < 2

    digests = active_variants.map do |v|
      ids = v.option_value_variants.map(&:option_value_id).sort
      ids.any? ? Digest::SHA256.hexdigest(ids.join('-')) : nil
    end.compact

    if digests.size != digests.uniq.size
      errors.add(:base, "Nu pot exista două variante active cu aceeași combinație de opțiuni")
    end
  end

  def must_have_one_primary_option_type
    return if product_option_types.empty?

    primary_count = product_option_types.select(&:primary?).count
    if primary_count == 0
      errors.add(:base, "Selectează o opțiune principală pentru variante")
    elsif primary_count > 1
      errors.add(:base, "Doar o singură opțiune poate fi principală")
    end
  end

  public

  # Returns the active price for the customer:
  # discount_price if promo is active, otherwise regular price
  def effective_price
    if promo_active? && discount_price.present? && discount_price > 0
      discount_price
    else
      price
    end
  end

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

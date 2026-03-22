class Order < ApplicationRecord
  belongs_to :user, optional: true
  has_many :order_items, dependent: :destroy
  belongs_to :coupon, optional: true
  has_one :invoice
  attr_accessor :use_different_shipping
  attr_accessor :shipping_cost

  enum status: {
    pending: "pending",
    paid: "paid",
    processing: "processing",
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled",
    refunded: "refunded",
    expired: "expired"
  }

  # === VALIDĂRI FACTURARE ===
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, :street, :street_number, :phone, :postal_code, :country, presence: true
  validates :postal_code, length: { in: 4..10 }, allow_blank: true
  validates :status, presence: true
  validates :cnp, format: { with: /\A\d{13}\z/, message: "trebuie să conțină 13 cifre" }, allow_blank: true

  validate :validate_country_and_location
  validate :validate_shipping_address, if: -> { shipping_address_different? }
  validate :validate_status_transition, if: :status_changed?

  before_validation :ensure_cnp_fallback

  VALID_TRANSITIONS = {
    "pending"    => %w[paid cancelled expired],
    "paid"       => %w[processing cancelled refunded],
    "processing" => %w[shipped cancelled refunded],
    "shipped"    => %w[delivered cancelled refunded],
    "delivered"  => %w[refunded],
    "cancelled"  => %w[],
    "refunded"   => %w[],
    "expired"    => %w[]
  }.freeze


  def finalize_order!
    decrement_stock_on_order
    coupon.increment!(:usage_count) if coupon.present?
    # Adaugă alte acțiuni finale (ex: trimite email)
  end

  def total_items
    order_items.sum(:quantity)
  end

  def total_vat
    order_items.sum { |item| item.vat.to_f * item.quantity }
  end

  def shipping_address_different?
    shipping_first_name.present? || shipping_street.present? || shipping_city.present?
  end



  private

  def ensure_cnp_fallback
    self.cnp = "0000000000000" if cnp.blank?
  end

  def validate_status_transition
    return if status_was.nil? # Allow initial status setting

    old_status = status_was.to_s
    new_status = status.to_s
    allowed = VALID_TRANSITIONS[old_status] || []

    unless allowed.include?(new_status)
      errors.add(:status, "nu poate trece din '#{old_status}' în '#{new_status}'")
    end
  end

  def validate_country_and_location
    return if country.blank?

    valid_countries = Tari.pluck(:nume).map(&:downcase)
    errors.add(:country, 'nu este validă.') unless valid_countries.include?(country.downcase)

    if country.downcase == "romania"
      if county.blank?
        errors.add(:county, 'este obligatoriu pentru România.')
      elsif Judet.where("LOWER(denjud) = ?", county.downcase).none?
        errors.add(:county, 'nu este valid.')
      end

      if city.blank?
        errors.add(:city, 'este obligatorie pentru România.')
      elsif Localitati.where("LOWER(denumire) = ? AND LOWER(denj) = ?", city.downcase, county.downcase).none?
        errors.add(:city, 'nu aparține județului selectat.')
      end
    else
      errors.add(:county, 'este obligatoriu') if county.blank?
      errors.add(:city, 'este obligatorie') if city.blank?
    end
  end

  def validate_shipping_address
    if shipping_country.blank?
      errors.add(:shipping_country, 'este obligatorie')
    else
      valid_countries = Tari.pluck(:nume).map(&:downcase)
      errors.add(:shipping_country, 'nu este validă') unless valid_countries.include?(shipping_country.downcase)
    end

    if shipping_country.downcase == "romania"
      if shipping_county.blank?
        errors.add(:shipping_county, 'este obligatoriu pentru România.')
      elsif Judet.where("LOWER(denjud) = ?", shipping_county.downcase).none?
        errors.add(:shipping_county, 'nu este valid.')
      end

      if shipping_city.blank?
        errors.add(:shipping_city, 'este obligatorie pentru România.')
      elsif Localitati.where("LOWER(denumire) = ? AND LOWER(denj) = ?", shipping_city.downcase, shipping_county.downcase).none?
        errors.add(:shipping_city, 'nu aparține județului selectat.')
      end
    else
      errors.add(:shipping_county, 'este obligatoriu') if shipping_county.blank?
      errors.add(:shipping_city, 'este obligatorie') if shipping_city.blank?
    end

    [:shipping_first_name, :shipping_last_name, :shipping_street, :shipping_street_number, :shipping_phone, :shipping_postal_code].each do |field|
      errors.add(field, 'este obligatoriu') if self.send(field).blank?
    end
  end

  # ⚡ metoda unică pentru scăderea stocului — atomic cu pessimistic locking
  def decrement_stock_on_order
    order_items.includes(:product, :variant).each do |item|
      if item.variant_id.present?
        variant = item.variant
        next unless variant.present?
        variant.with_lock do
          variant.stock = [variant.stock.to_i - item.quantity.to_i, 0].max
          variant.save!(validate: false)
        end
      end

      product = item.product
      next unless product.present?
      product.with_lock do
        product.stock = [product.stock.to_i - item.quantity.to_i, 0].max
        product.save!(validate: false)
      end
    end
  end
end

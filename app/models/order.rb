class Order < ApplicationRecord
  belongs_to :user, optional: true
  has_many :order_items, dependent: :destroy
  belongs_to :coupon, optional: true

  attr_accessor :use_different_shipping
  attr_accessor :shipping_cost


  enum status: {
    pending: "pending",
    paid: "paid",
    processing: "processing",
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled",
    refunded: "refunded"
  }

  # === VALIDĂRI FACTURARE ===
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, :street, :street_number, :phone, :postal_code, :country, presence: true
  validates :postal_code, length: { in: 4..10 }, allow_blank: true
  validates :status, presence: true
  validates :cnp, format: { with: /\A\d{13}\z/, message: "trebuie să conțină 13 cifre" }
  validate  :validate_country_and_location
  validate :validate_shipping_address, if: -> { shipping_address_different? }

  before_validation :ensure_cnp_fallback

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

  def validate_country_and_location
    return if country.blank?

    valid_countries = Tari.pluck(:nume).map(&:downcase)
    errors.add(:country, 'nu este validă.') unless valid_countries.include?(country.downcase)

    if country.downcase == "romania"
      if county.blank?
        errors.add(:county, 'este obligatoriu pentru România.')
      elsif !Judet.exists?(denjud: county)
        errors.add(:county, 'nu este valid.')
      end

      if city.blank?
        errors.add(:city, 'este obligatorie pentru România.')
      elsif !Localitati.exists?(denumire: city, denj: county)
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
      if !Tari.exists?(nume: shipping_country)
        errors.add(:shipping_country, 'nu este validă')
      end
    end

    if shipping_country&.downcase == "romania"
      if shipping_county.blank?
        errors.add(:shipping_county, 'este obligatoriu pentru România.')
      elsif !Judet.exists?(denjud: shipping_county)
        errors.add(:shipping_county, 'nu este valid.')
      end

      if shipping_city.blank?
        errors.add(:shipping_city, 'este obligatorie pentru România.')
      elsif !Localitati.exists?(denumire: shipping_city, denj: shipping_county)
        errors.add(:shipping_city, 'nu aparține județului selectat.')
      end
    else
      errors.add(:shipping_county, 'este obligatoriu') if shipping_county.blank?
      errors.add(:shipping_city, 'este obligatorie') if shipping_city.blank?
    end

    # Câmpuri necesare pentru adresă completă de livrare
    [:shipping_first_name, :shipping_last_name, :shipping_street, :shipping_street_number, :shipping_phone, :shipping_postal_code].each do |field|
      errors.add(field, 'este obligatoriu') if self.send(field).blank?
    end
  end


  
end

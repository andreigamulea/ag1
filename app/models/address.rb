class Address < ApplicationRecord
  belongs_to :user

  validates :first_name, :last_name, :street, :street_number,
            :phone, :country, :county, :city,
            presence: true
  validates :phone, format: { with: /\A\+?[\d\s\-]{6,20}\z/, message: "format invalid (doar cifre, spatii, - si optional + la inceput)" }, allow_blank: true
  validates :address_type, inclusion: { in: %w[shipping billing] }
  validates :email, presence: true, if: -> { address_type == "billing" }

  validate :validate_location_lookup, if: :romanian_address?

  before_validation :normalize_type_specific_fields
  before_save :ensure_single_default, if: -> { default? && will_save_change_to_default? }

  scope :shipping, -> { where(address_type: "shipping") }
  scope :billing,  -> { where(address_type: "billing") }
  scope :default_first, -> { order(default: :desc, updated_at: :desc) }

  def full_address
    [street, "nr. #{street_number}", block_details.presence, city, county, country, postal_code].compact.join(", ")
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def display_title
    "#{full_name} - #{phone}"
  end

  private

  def romanian_address?
    normalized = country.to_s.strip.downcase
    %w[romania românia].include?(normalized)
  end

  def normalize_type_specific_fields
    return unless address_type == "shipping"
    self.email = nil
    self.cui = nil
  end

  def validate_location_lookup
    return if country.blank? || county.blank? || city.blank?
    return unless %w[shipping billing].include?(address_type)
    validator = AddressValidator.new(country, county, city, type: address_type.to_sym)
    return if validator.valid?
    validator.error_messages.each { |msg| errors.add(:base, msg) }
  end

  def ensure_single_default
    self.class.where(user_id: user_id, address_type: address_type, default: true)
              .where.not(id: id)
              .update_all(default: false)
  end
end

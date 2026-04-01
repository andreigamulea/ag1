# app/services/address_validator.rb
# Validează adrese pentru comenzi (țară, județ, localitate)

class AddressValidator
  attr_reader :errors

  def initialize(country, county = nil, city = nil, type: :billing)
    @country = country&.downcase&.strip
    @county = county&.downcase&.strip
    @city = city&.downcase&.strip
    @type = type
    @errors = []
  end

  # Returnează true dacă adresa e validă
  def valid?
    @errors = []

    validate_country
    validate_county if @country == "romania"
    validate_city if @country == "romania"

    @errors.empty?
  end

  # Returnează lista erorilor
  def error_messages
    @errors.dup
  end

  private

  # Validează țara
  def validate_country
    if @country.blank?
      @errors << "#{@type} - țara este obligatorie."
      return
    end

    valid_countries = Tari.pluck(:nume).map(&:downcase)
    unless valid_countries.include?(@country)
      @errors << "#{@type} - țara nu este validă."
    end
  end

  # Validează județul (doar pentru România)
  def validate_county
    if @county.blank?
      @errors << "#{@type} - județul este obligatoriu."
      return
    end

    unless Judet.where("LOWER(denjud) = ?", @county).exists?
      @errors << "#{@type} - județul nu este valid."
    end
  end

  # Validează localitatea (doar pentru România)
  def validate_city
    if @city.blank?
      @errors << "#{@type} - localitatea este obligatorie."
      return
    end

    unless Localitati.where("LOWER(denumire) = ? AND LOWER(denj) = ?", @city, @county).exists?
      @errors << "#{@type} - localitatea nu aparține județului selectat."
    end
  end
end

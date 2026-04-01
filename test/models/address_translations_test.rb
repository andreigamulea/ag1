require "test_helper"

class AddressTranslationsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "trans-test-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  # ── MESAJE EROARE ÎN ROMÂNĂ ──────────────────────────────────

  test "eroare prenume gol e in romana" do
    address = @user.addresses.build(address_type: "shipping", first_name: "")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Prenumele") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Prenumele'"
    assert_includes msg, "obligatoriu"
  end

  test "eroare nume gol e in romana" do
    address = @user.addresses.build(address_type: "shipping", last_name: "")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Numele") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Numele'"
    assert_includes msg, "obligatoriu"
  end

  test "eroare strada goala e in romana" do
    address = @user.addresses.build(address_type: "shipping", street: "")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Strada") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Strada'"
    assert_includes msg, "obligatorie"
  end

  test "eroare numar gol e in romana" do
    address = @user.addresses.build(address_type: "shipping", street_number: "")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Numarul") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Numarul'"
    assert_includes msg, "obligatoriu"
  end

  test "eroare telefon gol e in romana" do
    address = @user.addresses.build(address_type: "shipping", phone: "")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Telefonul") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Telefonul'"
    assert_includes msg, "obligatoriu"
  end

  test "eroare telefon invalid e in romana" do
    address = @user.addresses.build(
      address_type: "shipping", first_name: "Ion", last_name: "P",
      street: "X", street_number: "1", country: "Romania",
      county: "Bucuresti", city: "Bucuresti", phone: "abc"
    )
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Telefonul") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Telefonul'"
    assert_includes msg, "format invalid"
  end

  test "eroare tara goala e in romana" do
    address = @user.addresses.build(address_type: "shipping", country: "")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Tara") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Tara'"
    assert_includes msg, "obligatorie"
  end

  test "eroare judet gol e in romana" do
    address = @user.addresses.build(address_type: "shipping", county: "")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Judetul") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Judetul'"
    assert_includes msg, "obligatoriu"
  end

  test "eroare localitate goala e in romana" do
    address = @user.addresses.build(address_type: "shipping", city: "")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Localitatea") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Localitatea'"
    assert_includes msg, "obligatorie"
  end

  test "eroare email gol pe billing e in romana" do
    address = @user.addresses.build(
      address_type: "billing", first_name: "Ion", last_name: "P",
      street: "X", street_number: "1", country: "Romania",
      county: "Bucuresti", city: "Bucuresti", phone: "0749079619",
      email: ""
    )
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Email") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Email'"
    assert_includes msg, "obligatoriu"
  end

  test "eroare tip adresa invalid e in romana" do
    address = @user.addresses.build(address_type: "invalid")
    address.valid?
    msg = address.errors.full_messages.find { |m| m.include?("Tipul adresei") }
    assert msg.present?, "Eroarea ar trebui sa contina 'Tipul adresei'"
  end

  # ── NICIO EROARE ÎN ENGLEZĂ ──────────────────────────────────

  test "erorile nu contin can't be blank" do
    address = @user.addresses.build(address_type: "shipping")
    address.valid?
    address.errors.full_messages.each do |msg|
      assert_not_includes msg, "can't be blank", "Mesaj netradus: #{msg}"
      assert_not_includes msg, "is invalid", "Mesaj netradus: #{msg}"
      assert_not_includes msg, "is not included", "Mesaj netradus: #{msg}"
    end
  end

  test "erori user nu contin texte in engleza" do
    user = User.new(email: "", password: "")
    user.valid?
    user.errors.full_messages.each do |msg|
      assert_not_includes msg, "can't be blank", "Mesaj netradus: #{msg}"
    end
  end
end

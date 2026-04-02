require "test_helper"

class AddressTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "addr-test-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  # ── VALIDĂRI PREZENȚĂ ────────────────────────────────────────

  test "adresa shipping validă se salvează" do
    address = @user.addresses.build(valid_shipping_attrs)
    assert address.valid?, "Erori: #{address.errors.full_messages.join(', ')}"
    assert address.save
  end

  test "adresa billing validă se salvează" do
    address = @user.addresses.build(valid_billing_attrs)
    assert address.valid?, "Erori: #{address.errors.full_messages.join(', ')}"
    assert address.save
  end

  test "first_name obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(first_name: ""))
    assert_not address.valid?
    assert address.errors[:first_name].any?
  end

  test "last_name obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(last_name: ""))
    assert_not address.valid?
    assert address.errors[:last_name].any?
  end

  test "street obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(street: ""))
    assert_not address.valid?
    assert address.errors[:street].any?
  end

  test "street_number obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(street_number: ""))
    assert_not address.valid?
    assert address.errors[:street_number].any?
  end

  test "phone obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(phone: ""))
    assert_not address.valid?
    assert address.errors[:phone].any?
  end

  test "postal_code nu e obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(postal_code: ""))
    assert address.valid?, "Erori: #{address.errors.full_messages.join(', ')}"
  end

  # ── VALIDARE TELEFON ─────────────────────────────────────────

  test "telefon format valid cu cifre" do
    address = @user.addresses.build(valid_shipping_attrs.merge(phone: "0749079619"))
    assert address.valid?
  end

  test "telefon format valid international" do
    address = @user.addresses.build(valid_shipping_attrs.merge(phone: "+40749079619"))
    assert address.valid?
  end

  test "telefon format valid cu spații" do
    address = @user.addresses.build(valid_shipping_attrs.merge(phone: "+40 749 079 619"))
    assert address.valid?
  end

  test "telefon format valid cu cratime" do
    address = @user.addresses.build(valid_shipping_attrs.merge(phone: "074-907-9619"))
    assert address.valid?
  end

  test "telefon format invalid cu litere" do
    address = @user.addresses.build(valid_shipping_attrs.merge(phone: "abcdefgh"))
    assert_not address.valid?
    assert address.errors[:phone].any?
  end

  test "telefon prea scurt" do
    address = @user.addresses.build(valid_shipping_attrs.merge(phone: "123"))
    assert_not address.valid?
    assert address.errors[:phone].any?
  end

  test "country obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(country: ""))
    assert_not address.valid?
    assert address.errors[:country].any?
  end

  test "county obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(county: ""))
    assert_not address.valid?
    assert address.errors[:county].any?
  end

  test "city obligatoriu" do
    address = @user.addresses.build(valid_shipping_attrs.merge(city: ""))
    assert_not address.valid?
    assert address.errors[:city].any?
  end

  # ── ADDRESS TYPE ─────────────────────────────────────────────

  test "address_type trebuie să fie shipping sau billing" do
    address = @user.addresses.build(valid_shipping_attrs.merge(address_type: "invalid"))
    assert_not address.valid?
    assert address.errors[:address_type].any?
  end

  test "address_type shipping acceptat" do
    address = @user.addresses.build(valid_shipping_attrs.merge(address_type: "shipping"))
    assert address.valid?
  end

  test "address_type billing acceptat" do
    address = @user.addresses.build(valid_billing_attrs.merge(address_type: "billing"))
    assert address.valid?
  end

  # ── EMAIL CONDIȚIONAT ────────────────────────────────────────

  test "email obligatoriu pentru billing" do
    address = @user.addresses.build(valid_billing_attrs.merge(email: ""))
    assert_not address.valid?
    assert address.errors[:email].any?
  end

  test "email nu e obligatoriu pentru shipping" do
    address = @user.addresses.build(valid_shipping_attrs.merge(email: nil))
    assert address.valid?
  end

  # ── NORMALIZE SHIPPING ───────────────────────────────────────

  test "shipping curăță email și cui la salvare" do
    address = @user.addresses.create!(valid_shipping_attrs.merge(email: "test@test.com", cui: "RO123"))
    address.reload
    assert_nil address.email
    assert_nil address.cui
  end

  test "billing păstrează email și cui" do
    address = @user.addresses.create!(valid_billing_attrs.merge(email: "firma@test.com", cui: "RO999"))
    address.reload
    assert_equal "firma@test.com", address.email
    assert_equal "RO999", address.cui
  end

  # ── DEFAULT ──────────────────────────────────────────────────

  test "o singură adresă default per tip" do
    addr1 = @user.addresses.create!(valid_shipping_attrs.merge(default: true))
    addr2 = @user.addresses.create!(valid_shipping_attrs.merge(default: true, street: "Alta strada"))

    addr1.reload
    addr2.reload

    assert_not addr1.default?, "Prima adresă nu mai trebuie să fie default"
    assert addr2.default?, "A doua adresă trebuie să fie default"
  end

  test "default pe shipping nu afectează billing" do
    shipping = @user.addresses.create!(valid_shipping_attrs.merge(default: true))
    billing = @user.addresses.create!(valid_billing_attrs.merge(default: true))

    shipping.reload
    billing.reload

    assert shipping.default?, "Shipping default nu trebuie afectat de billing"
    assert billing.default?, "Billing default trebuie să rămână"
  end

  # ── SCOPES ───────────────────────────────────────────────────

  test "scope shipping returnează doar adrese shipping" do
    @user.addresses.create!(valid_shipping_attrs)
    @user.addresses.create!(valid_billing_attrs)

    assert_equal 1, @user.addresses.shipping.count
    assert_equal "shipping", @user.addresses.shipping.first.address_type
  end

  test "scope billing returnează doar adrese billing" do
    @user.addresses.create!(valid_shipping_attrs)
    @user.addresses.create!(valid_billing_attrs)

    assert_equal 1, @user.addresses.billing.count
    assert_equal "billing", @user.addresses.billing.first.address_type
  end

  test "scope default_first pune adresa default prima" do
    normal = @user.addresses.create!(valid_shipping_attrs.merge(default: false))
    default_addr = @user.addresses.create!(valid_shipping_attrs.merge(default: true, street: "Default St"))

    result = @user.addresses.shipping.default_first
    assert_equal default_addr.id, result.first.id
  end

  # ── METODE ───────────────────────────────────────────────────

  test "full_name returnează prenume și nume" do
    address = @user.addresses.build(valid_shipping_attrs)
    assert_equal "Ion Popescu", address.full_name
  end

  test "display_title returnează nume și telefon" do
    address = @user.addresses.build(valid_shipping_attrs)
    assert_equal "Ion Popescu - 0749079619", address.display_title
  end

  test "full_address conține strada, orașul, județul" do
    address = @user.addresses.build(valid_shipping_attrs)
    result = address.full_address
    assert_includes result, "Str. Ostasilor"
    assert_includes result, "nr. 15"
    assert_includes result, "Bucuresti"
  end

  # ── ASOCIERI USER ────────────────────────────────────────────

  test "user are has_many addresses" do
    @user.addresses.create!(valid_shipping_attrs)
    @user.addresses.create!(valid_billing_attrs)
    assert_equal 2, @user.addresses.count
  end

  test "user shipping_addresses returnează doar shipping" do
    @user.addresses.create!(valid_shipping_attrs)
    @user.addresses.create!(valid_billing_attrs)
    assert_equal 1, @user.shipping_addresses.count
  end

  test "user billing_addresses returnează doar billing" do
    @user.addresses.create!(valid_shipping_attrs)
    @user.addresses.create!(valid_billing_attrs)
    assert_equal 1, @user.billing_addresses.count
  end

  test "ștergerea user-ului șterge și adresele" do
    @user.addresses.create!(valid_shipping_attrs)
    @user.addresses.create!(valid_billing_attrs)
    user_id = @user.id
    @user.destroy
    assert_equal 0, Address.where(user_id: user_id).count
  end

  private

  def valid_shipping_attrs
    {
      address_type: "shipping",
      first_name: "Ion",
      last_name: "Popescu",
      phone: "0749079619",
      country: "Romania",
      county: "Bucuresti",
      city: "Bucuresti",
      postal_code: "010101",
      street: "Str. Ostasilor",
      street_number: "15"
    }
  end

  def valid_billing_attrs
    {
      address_type: "billing",
      first_name: "Ion",
      last_name: "Popescu",
      phone: "0749079619",
      email: "ion@example.com",
      country: "Romania",
      county: "Bucuresti",
      city: "Bucuresti",
      postal_code: "010101",
      street: "Str. Ostasilor",
      street_number: "15"
    }
  end
end

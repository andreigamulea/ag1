FactoryBot.define do
  factory :order do
    email { "test@example.com" }
    first_name { "Test" }
    last_name { "User" }
    phone { "0700000000" }
    street { "Test Street" }
    street_number { "1" }
    postal_code { "010101" }
    country { "Romania" }
    county { "Bucuresti" }
    city { "Bucuresti" }
    status { "pending" }

    # Skip geo validations (depend on Tari/Judet/Localitati tables)
    to_create { |instance| instance.save(validate: false) }
  end
end

# Plan: Pagina "Contul meu" — Dashboard cu sidebar

## Context

Utilizatorul autentificat accesează "Contul meu" din meniu și vede o pagină Devise minimă (doar email + parolă). Vrem o pagină completă cu sidebar lateral și secțiuni: Adrese de livrare, Date facturare, Setări cont, Comenzile mele, Log out — similar cu screenshot-ul de referință.

## Starea actuală a aplicației

### Ce EXISTĂ deja:
- **User model** (`app/models/user.rb`): email, encrypted_password, role, active. Asocieri: `has_many :orders`
- **Order model** (`app/models/order.rb`): conține câmpuri shipping + billing inline (NU tabel separat)
  - Shipping: `shipping_first_name`, `shipping_last_name`, `shipping_street`, `shipping_street_number`, `shipping_block_details`, `shipping_city`, `shipping_county`, `shipping_country`, `shipping_postal_code`, `shipping_phone`, `shipping_company_name`
  - Billing: `first_name`, `last_name`, `street`, `street_number`, `block_details`, `city`, `county`, `country`, `postal_code`, `phone`, `company_name`, `cui`, `cnp`, `email`
- **Orders controller** (`app/controllers/orders_controller.rb`):
  - `new` action (liniile 37-65): pre-populează formularul cu adresa din ULTIMA comandă a userului via `last_order.slice(...)` — copiază toate câmpurile shipping + billing
  - `index` action: admin vede tot (layout admin), user normal vede doar comenzile lui (layout shop via `is_admin_page?` / `is_shop_page?`)
  - `show_items` action: render partial `_order_items.html.erb` — afișează și adresele billing/shipping ale comenzii
  - `invoice` action: generează PDF/XML factură, necesită `authenticate_user!` + `check_order_access`
- **Pagina comenzi** (`app/views/orders/index.html.erb`): format admin cu tabel (ID, Nume, Email, Telefon, Data, Total, Status, Acțiuni). Nu e user-friendly pentru clienți.
- **Pagina edit cont** (`app/views/devise/registrations/edit.html.erb`): email + parolă + dezactivare cont. Folosește layout shop (via `CustomRegistrationsController` care override `is_shop_page?` → true)
- **CustomRegistrationsController** (`app/controllers/custom_registrations_controller.rb`): extinde `Devise::RegistrationsController`, adaugă acțiunea `deactivate` cu verificare parolă. Redirect-urile de deactivate duc la `edit_user_registration_path` — trebuie actualizate la `contul_meu_path(section: "settings")`.
- **AddressValidator service** (`app/services/address_validator.rb`): validează țară/județ/localitate contra tabelelor lookup. Trebuie reutilizat în modelul Address (validate custom cu `AddressValidator`).
- **Autocomplete controller Stimulus** (`app/javascript/controllers/autocomplete_controller.js`): controller funcțional cu targets `input` + `dropdown`, values `endpoint` + `filterId`. Există deja, dar nu acoperă logica în cascadă (țară → județ → localitate) necesară pentru formularul nou de adresă.
- **Autocomplete routes** în OrdersController: `GET /autocomplete_tara`, `GET /autocomplete_judet`, `GET /autocomplete_localitate` — funcționale, interogă tabelele `taris`, `judets`, `localitatis`
- **Lookup tables**: `taris` (nume, abr), `judets` (denjud, cod_j), `localitatis` (denumire, denj) — pentru autocomplete
- **Layout logic** (`app/controllers/application_controller.rb` liniile 13-35): `choose_layout` decide layout pe baza `is_admin_page?` / `is_shop_page?`. Devise pages → shop layout automat. AccountController trebuie să override `is_shop_page?` → true.
- **Header dropdown** (`app/views/layouts/_header.html.erb` liniile 246-272): link-uri curente:
  - `👤 Contul meu` → `edit_user_registration_path` (trebuie schimbat la `contul_meu_path`)
  - `📦 Comenzile mele` → `orders_path` (trebuie schimbat la `contul_meu_path(section: "orders")`)
  - `📄 Facturile mele` → `orders_path` (duplicat cu comenzile — de eliminat sau integrat)
  - `🚪 Logout` → `destroy_user_session_path` (rămâne)
- **Ruta** curentă: `/users/edit` (Devise) → pagina edit cont

### Ce NU EXISTĂ:
- Model `Address` separat
- Controller dedicat pentru "Contul meu" / dashboard
- Pagină cu sidebar + secțiuni
- Pagină "Comenzile mele" user-friendly (cea existentă e format admin)
- Posibilitate de a salva mai multe adrese

---

## Arhitectură propusă

### Abordare: Model Address separat + AccountController

Creăm un model `Address` cu `belongs_to :user` care permite utilizatorului să salveze mai multe adrese de livrare/facturare. La checkout, adresele salvate pot fi selectate (viitor).

---

## Detalii implementare

### 1. Migrație: Tabel `addresses`

```
create_table :addresses do |t|
  t.references :user, null: false, foreign_key: true
  t.string  :address_type, default: "shipping"  # "shipping" sau "billing"
  t.string  :first_name
  t.string  :last_name
  t.string  :company_name
  t.string  :cui                  # doar billing
  t.string  :phone
  t.string  :email                # doar billing
  t.string  :country
  t.string  :county
  t.string  :city
  t.string  :postal_code
  t.string  :street
  t.string  :street_number
  t.text    :block_details
  t.string  :label                # ex: "Acasă", "Birou", "Părinți"
  t.boolean :default, default: false
  t.timestamps
end
```

Câmpurile acoperă toate datele reutilizabile din `Order`, cu mapare semantică 1:1 pentru compatibilitate la checkout, exceptând `CNP`.

### 2. Model `Address` (`app/models/address.rb`)

```ruby
class Address < ApplicationRecord
  belongs_to :user

  validates :first_name, :last_name, :street, :street_number,
            :phone, :postal_code, :country, :county, :city,
            presence: true
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
    normalized = country.to_s.strip.downcase.gsub(/[âî]/, "a" => "a", "î" => "i")
    %w[romania românia].include?(country.to_s.strip.downcase) || normalized == "romania"
  end

  def validate_location_lookup
    return if country.blank? || county.blank? || city.blank?
    return unless %w[shipping billing].include?(address_type)
    validator = AddressValidator.new(country, county, city, type: address_type.to_sym)
    return if validator.valid?
    validator.error_messages.each { |msg| errors.add(:base, msg) }
  end

  def normalize_type_specific_fields
    return unless address_type == "shipping"
    self.email = nil
    self.cui = nil
  end

  def ensure_single_default
    self.class.where(user_id: user_id, address_type: address_type, default: true)
              .where.not(id: id)
              .update_all(default: false)
  end
end
```

### 3. User model — adăugare asociere

```ruby
# app/models/user.rb
has_many :addresses, dependent: :destroy
has_many :shipping_addresses, -> { shipping.default_first }, class_name: "Address"
has_many :billing_addresses,  -> { billing.default_first },  class_name: "Address"
```

### 4. Controller `AccountController` (`app/controllers/account_controller.rb`)

Un controller cu secțiuni, NU routes REST separate. Sidebar-ul navighează între secțiuni via query param `?section=`.

```ruby
class AccountController < ApplicationController
  before_action :authenticate_user!

  # Folosește layout shop (necesar pentru choose_layout din ApplicationController)
  def is_shop_page?
    true
  end

  SECTIONS = %w[addresses billing settings orders].freeze

  # GET /contul-meu
  def show
    @section = SECTIONS.include?(params[:section]) ? params[:section] : "addresses"
    
    case @section
    when "addresses"
      @addresses = current_user.shipping_addresses
    when "billing"
      @addresses = current_user.billing_addresses
    when "settings"
      @resource = current_user
      @minimum_password_length = Devise.password_length.min
    when "orders"
      @orders = current_user.orders
                            .includes(:invoice, order_items: :product)
                            .order(created_at: :desc)
                            .page(params[:page]).per(10)
    end
  end

  private

  def resource
    @resource ||= current_user
  end
  helper_method :resource

  def resource_name
    :user
  end
  helper_method :resource_name

  def devise_mapping
    Devise.mappings[:user]
  end
  helper_method :devise_mapping

  public

  # GET /contul-meu/comenzi/:id
  def order_detail
    @order = current_user.orders
                         .includes(:invoice, order_items: :product)
                         .find(params[:id])
    @section = "orders"
  end
end
```

**Notă**: NU folosim `layout "shop"` direct — folosim metoda `is_shop_page?` care e pattern-ul existent din `ApplicationController#choose_layout` (linia 13). Toate controllerele din aplicație folosesc acest pattern.

### 5. Controller `AddressesController` (`app/controllers/addresses_controller.rb`)

CRUD pentru adrese, cu redirect înapoi la pagina "Contul meu".

```ruby
class AddressesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_address, only: [:edit, :update, :destroy]

  def is_shop_page?
    true
  end

  def new
    type = %w[shipping billing].include?(params[:type]) ? params[:type] : "shipping"
    @address = current_user.addresses.build(address_type: type)
  end

  def create
    @address = current_user.addresses.build(address_params)
    if @address.save
      redirect_to contul_meu_path(section: @address.address_type == "billing" ? "billing" : "addresses"),
                  notice: "Adresa a fost salvată."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @address.update(address_params)
      redirect_to contul_meu_path(section: @address.address_type == "billing" ? "billing" : "addresses"),
                  notice: "Adresa a fost actualizată."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    type = @address.address_type
    @address.destroy
    redirect_to contul_meu_path(section: type == "billing" ? "billing" : "addresses"),
                notice: "Adresa a fost ștearsă."
  end

  private

  def set_address
    @address = current_user.addresses.find(params[:id])
  end

  def address_params
    params.require(:address).permit(
      :address_type, :first_name, :last_name, :company_name, :cui,
      :phone, :email, :country, :county, :city, :postal_code,
      :street, :street_number, :block_details, :label, :default
    )
  end
end
```

### 6. Routes

```ruby
# config/routes.rb
get "contul-meu", to: "account#show", as: :contul_meu
get "contul-meu/comenzi/:id", to: "account#order_detail", as: :contul_meu_order
resources :addresses, except: [:index, :show]
```

### 7. Views

#### `app/views/account/show.html.erb` — Layout principal cu sidebar

Sidebar stânga + conținut dreapta. Sidebar-ul are:
- 📍 Adrese de livrare (`?section=addresses`)
- 🧾 Date facturare (`?section=billing`)
- 🔒 Setări cont (`?section=settings`)
- 📦 Comenzile mele (`?section=orders`)
- 🚪 Log out (`button_to` către `destroy_user_session_path`, method: :delete)

Conținut dreapta: partial care se schimbă în funcție de `@section`:
- `_addresses.html.erb` — grid 2 coloane cu carduri adresă shipping (iconiță pin, editează/șterge, buton +Adaugă). Folosește partial `_address_card.html.erb` pentru fiecare card.
- `_billing.html.erb` — grid identic dar cu carduri billing (firmă/CUI/email). Folosește același partial `_address_card.html.erb` — partial-ul detectează `address_type` și afișează câmpurile corespunzătoare.
- `_settings.html.erb` — view custom pe carduri pentru email/parolă/dezactivare, care postează la rutele Devise standard
- `_orders.html.erb` — lista comenzilor user-friendly (data, total, status badge, link detalii)

#### `app/views/addresses/new.html.erb` și `edit.html.erb`

Formular adresă cu autocomplete (reutilizează logica din checkout):
- Țară (autocomplete din `taris`)
- Județ (autocomplete din `judets`)
- Localitate (autocomplete din `localitatis`, filtrat pe județ)
- Stradă, număr, bloc/scară/etaj/ap
- Cod poștal, telefon
- Label opțional ("Acasă", "Birou")

### 8. Stiluri CSS — `app/assets/stylesheets/pages/_account.css`

Layout cu sidebar:
```css
.account-wrapper { display: flex; max-width: 1200px; margin: 40px auto; gap: 30px; }
.account-sidebar { width: 260px; flex-shrink: 0; }
.account-sidebar a { display: flex; align-items: center; gap: 12px; padding: 14px 18px; }
.account-sidebar a.active { background: #f5f5f5; border-left: 3px solid var(--color-primary); }
.account-content { flex: 1; }
```

Grid carduri adrese:
```css
.address-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 20px; }
.address-card { border: 1px solid #ddd; border-radius: 8px; padding: 20px; }
```

### 9. Meniul header — actualizare link-uri dropdown

Fișier: `app/views/layouts/_header.html.erb` (liniile 258-260)

Înainte:
```erb
<%= link_to "👤 Contul meu", edit_user_registration_path %>
<%= link_to "📦 Comenzile mele", orders_path %>
<%= link_to "📄 Facturile mele", orders_path %>
```

După:
```erb
<%= link_to "👤 Contul meu", contul_meu_path %>
<%= link_to "📦 Comenzile mele", contul_meu_path(section: "orders") %>
```

- Eliminăm "Facturile mele" (duplicat — facturile se descarcă din detaliile comenzii)
- "Contul meu" → `/contul-meu` (dashboard cu sidebar)
- "Comenzile mele" → `/contul-meu?section=orders`

### 10. CustomRegistrationsController — actualizare completă

Fișier: `app/controllers/custom_registrations_controller.rb`

**Override-uri necesare:**
- `edit` → redirect la `contul_meu_path(section: "settings")` (T8)
- `update` → pe succes redirect la dashboard; pe eroare render `account/show` cu `@section = "settings"` (altfel Devise randează view-ul clasic `edit`, nu dashboard-ul)
- `after_update_path_for` → `contul_meu_path(section: "settings")`
- `deactivate` redirect-uri → `contul_meu_path(section: "settings")`

```ruby
def edit
  redirect_to contul_meu_path(section: "settings")
end

def update
  self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
  prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email)
  resource_updated = update_resource(resource, account_update_params)

  if resource_updated
    set_flash_message_for_update(resource, prev_unconfirmed_email)
    bypass_sign_in resource, scope: resource_name if sign_in_after_change_password?
    redirect_to contul_meu_path(section: "settings")
  else
    clean_up_passwords resource
    set_minimum_password_length
    @section = "settings"
    @resource = resource
    @addresses = []  # safe default — show.html.erb nu crapă dacă accesează @addresses
    @orders = []
    render "account/show", status: :unprocessable_entity
  end
end

protected

def after_update_path_for(resource)
  contul_meu_path(section: "settings")
end
```

### 11. Validare adresă — reutilizare AddressValidator

Modelul Address folosește `AddressValidator` prin implementarea definită în secțiunea 2 (`validate_location_lookup`, condiționat doar pentru România, cu guard pe blank și pe `address_type` valid).

### 12. Import adrese din comenzi existente

Importul automat al adreselor din comenzi **NU intră în V1**. Este documentat mai jos ca feature separat pentru iterația 2 (secțiunea D).

### 13. Formularul de adresă — autocomplete cu `address_form_controller.js`

Formularul de adresă nouă/edit (`app/views/addresses/_form.html.erb`) folosește `address_form_controller.js` (Stimulus controller nou, cu logica în cascadă țară → județ → localitate extrasă din checkout). NU folosește `autocomplete_controller.js` existent (prea simplu, fără cascadă).

Rutele autocomplete (`/autocomplete_tara`, `/autocomplete_judet`, `/autocomplete_localitate`) sunt implementate în `OrdersController`, dar pot fi reutilizate și din dashboard, nu doar din formularul de checkout.

### 14. Secțiunea "Setări cont" — design card-uri (NU formularul Devise clasic)

**NU** afișăm formularul Devise cu toate câmpurile vizibile. În schimb, afișăm carduri read-only cu buton "modifică" pe fiecare:

**Layout vizual** (ca în screenshot-ul de referință):
```
Setări cont

┌─────────────────────────────────────────────────────────────────┐
│ @ Adresa de e-mail                                  [modifică] │
│   Adresa de email actuală a contului tău este user@email.com   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 🔒 Parola                                           [modifică] │
│   Este o idee bună să folosești o parolă puternică pe care     │
│   nu o mai folosești și în altă parte                           │
└─────────────────────────────────────────────────────────────────┘

```

**V1: doar Email + Parolă.** Telefonul se amână la iterația 2 (necesită migrație `add_phone_to_users`, permit în Devise strong params, și clarificarea dacă update fără schimbare de parolă cere `current_password`).

**Comportament buton "modifică":**
- **Email**: toggle inline — afișează câmp email + câmp parolă curentă + buton "Salvează". POST la ruta Devise standard `registration_path(:user)`.
- **Parolă**: toggle inline — afișează câmp parolă nouă + confirmare + parolă curentă + buton "Salvează". POST la ruta Devise standard.

**Implementare toggle:**
- Stimulus controller dedicat `settings_toggle_controller.js` — click pe "modifică" ascunde textul readonly și afișează formularul inline. NU reutilizăm `toggle_shipping_controller.js` (este prea cuplat la logica checkout billing/shipping).
- Fiecare card e un `<form>` Devise ascuns implicit, vizibil la click
- Devise `form_for` necesită `@resource` (setat în AccountController ca `current_user`) + `@minimum_password_length`
- Formularul POST-ează la `registration_path(resource_name)` — ruta Devise standard
- După update reușit, Devise redirecționează — trebuie override `after_update_path_for` în `CustomRegistrationsController` pentru a duce la `contul_meu_path(section: "settings")`

**Dezactivare cont:**
- Sub carduri, secțiune separată cu warning + buton — rămâne ca acum
- POST la `deactivate_user_registration_path` (ruta custom din `CustomRegistrationsController`)

---

## Fișiere de creat

| # | Fișier | Tip |
|---|--------|-----|
| 1 | `db/migrate/xxx_create_addresses.rb` | Migrație |
| 2 | `app/models/address.rb` | Model |
| 3 | `app/controllers/account_controller.rb` | Controller |
| 4 | `app/controllers/addresses_controller.rb` | Controller |
| 5 | `app/views/account/show.html.erb` | View principal |
| 6 | `app/views/account/_sidebar.html.erb` | Partial sidebar |
| 7 | `app/views/account/_addresses.html.erb` | Partial adrese livrare |
| 8 | `app/views/account/_billing.html.erb` | Partial date facturare |
| 9 | `app/views/account/_settings.html.erb` | Partial setări (carduri custom + formulare Devise) |
| 10 | `app/views/account/_orders.html.erb` | Partial comenzi |
| 11 | `app/views/addresses/new.html.erb` | Formular adresă nouă |
| 12 | `app/views/addresses/edit.html.erb` | Formular edit adresă |
| 13 | `app/views/addresses/_form.html.erb` | Partial formular adresă |
| 14 | `app/views/account/_address_card.html.erb` | Partial card adresă (comun shipping/billing) |
| 15 | `app/views/account/order_detail.html.erb` | View wrapper detalii comandă (sidebar + noindex) |
| 16 | `app/views/account/_order_detail_content.html.erb` | Partial conținut detalii comandă (3 coloane + produse) |
| 16 | `app/assets/stylesheets/pages/_account.css` | Stiluri |
| 17 | `app/javascript/controllers/address_form_controller.js` | Stimulus controller autocomplete cascadă |
| 18 | `app/javascript/controllers/settings_toggle_controller.js` | Stimulus controller toggle carduri setări |

## Fișiere de modificat

| # | Fișier | Ce se schimbă |
|---|--------|--------------|
| 1 | `app/models/user.rb` | Adaug `has_many :addresses`, `has_many :shipping_addresses`, `has_many :billing_addresses` |
| 2 | `config/routes.rb` | Adaug rute `contul-meu` + `resources :addresses` |
| 3 | `app/views/layouts/_header.html.erb` | Schimb link-uri dropdown: Contul meu → `contul_meu_path`, Comenzile mele → `contul_meu_path(section: "orders")`, elimin Facturile mele |
| 4 | `app/assets/stylesheets/application.css` | Adaug `require pages/_account` |
| 5 | `app/controllers/custom_registrations_controller.rb` | Override `edit` (redirect dashboard), override `update` (error → render account/show), `after_update_path_for`, redirect-uri `deactivate` |

---

## Corelații importante

1. **Câmpurile Address = câmpurile reutilizabile din Order** — mapare 1:1 pentru toate câmpurile EXCEPTÂND CNP (care rămâne exclus intenționat, se completează doar la checkout). `company_name` rămâne disponibil și pentru shipping (ca în checkout). Permite: (a) pre-populare checkout din adresă salvată, (b) import adrese din comenzi existente
2. **Autocomplete** — reutilizăm rutele existente (`/autocomplete_tara`, `/autocomplete_judet`, `/autocomplete_localitate` din `routes.rb` liniile 14-16) și tabelele lookup (`taris`, `judets`, `localitatis`). Pentru formularul de adresă din dashboard, V1 folosește un controller Stimulus nou `address_form_controller.js` (deoarece `autocomplete_controller.js` existent nu acoperă logica în cascadă țară → județ → localitate). Unificarea cu checkout vine în iterația 2.
3. **AddressValidator** — service existent (`app/services/address_validator.rb`) — reutilizat în modelul Address pentru validarea țară/județ/localitate
4. **Layout shop** — AccountController folosește `is_shop_page?` → true (pattern-ul din `ApplicationController#choose_layout`, NU `layout "shop"` direct)
5. **Devise formulare** — secțiunea "Setări" conține formularul Devise care POST-ează la rutele Devise standard (`registration_path`). Necesită `@resource` + `@minimum_password_length` setate în AccountController
6. **CustomRegistrationsController** — `deactivate` action redirecționează la `edit_user_registration_path` → trebuie schimbat la `contul_meu_path`. `after_update_path_for` override pentru redirect post-update
7. **Header dropdown** — 3 link-uri trebuie actualizate, "Facturile mele" eliminat (duplicat)
8. **Comenzi** — `/orders` rămâne funcțional pentru admin (layout admin). Secțiunea "Comenzile mele" din dashboard e view nou user-friendly cu status badges, fără coloanele admin
9. **Checkout pre-populate** — `OrdersController#new` (liniile 37-65) ia adresa din `last_order.slice(...)`. Ulterior va putea lua dintr-o adresă salvată (Address model)

---

## Detalii tehnice omise — completări

### T1. Autocomplete în formularul de adresă — JS inline vs Stimulus

Checkout-ul (`orders/_form.html.erb`) folosește **JS inline** (funcția `setupAutocomplete` scrisă direct în `<script>`, ~120 linii) cu logică specifică: `enableNextFields`, `disableNextFields`, `initializeFields`. Acest JS:
- Dezactivează județul până se selectează țara
- Dezactivează localitatea până se selectează județul  
- Diferențiază România (autocomplete obligatoriu) de alte țări (input liber)
- Setează România ca default

Controller-ul Stimulus `autocomplete_controller.js` există dar e mai simplu — nu are logica de cascade (țară → județ → localitate).

**Decizie**: Extragem logica din checkout-ul inline într-un Stimulus controller dedicat `address_form_controller.js`. Acest controller se va folosi atât în `addresses/_form.html.erb` cât și (ulterior) în `orders/_form.html.erb` — eliminând duplicarea. NU reutilizăm `autocomplete_controller.js` (prea simplu pentru cascadă).

**V1**: `address_form_controller.js` se folosește doar în formularul de adresă din dashboard. Checkout-ul rămâne cu JS-ul inline existent (nu riscăm regresii). Unificarea completă vine în iterația 2.

### T2. Câmpurile formularului de adresă — diferențe shipping vs billing

**Shipping** (din checkout `_form.html.erb` liniile 14-71):
- Nume, Prenume, Companie (opțional), Telefon
- Țară (autocomplete), Județ (autocomplete), Localitate (autocomplete)
- Cod poștal, Stradă, Număr, Bloc/Etaj/Apt (opțional)

**Billing** (din checkout `_form.html.erb` liniile 86-108):
- Totul de mai sus PLUS: CUI (opțional), CNP (opțional, dar NU îl stocăm în Address — rămâne doar pe order), Email

**Formularul de adresă** (`addresses/_form.html.erb`) derivă tipul din `@address.address_type` (NU din `params[:type]` — important pentru edit și reafișare după eroare de validare). Afișează/ascunde câmpuri în funcție de tip:
- `shipping`: cu company_name (opțional, ca în checkout), fără CUI, fără email
- `billing`: cu company_name (opțional), CUI (opțional), email — fără CNP

**Card afișare shipping:**
```
📍 Ion Popescu - 0749079619
   Str. Ostașilor nr. 15, București, București
   editează    șterge
```

**Card afișare billing (persoană fizică):**
```
🧾 Ion Popescu - 0749079619
   ion@email.com
   Str. Ostașilor nr. 15, București, București
   editează    șterge
```

**Card afișare billing (firmă):**
```
🧾 SC Ayus Grup SRL - CUI: RO12345678
   Ion Popescu - 0749079619 • ion@email.com
   Str. Ostașilor nr. 15, București, București
   editează    șterge
```

Dacă `company_name` e completat, cardul afișează firma + CUI pe prima linie. Dacă nu, afișează ca persoană fizică.

### T3. Flash messages — integrare cu dashboard

Sistemul de flash messages implementat în această conversație trebuie să funcționeze pe pagina "Contul meu":
- Layout-ul shop are deja `render 'shared/flash_messages'` — va afișa mesajele de succes/eroare la salvare/editare/ștergere adresă
- AddressesController setează `notice:` la redirect → apare ca flash-success
- Devise update (email/parolă) setează flash automat → apare pe redirect la `contul_meu_path(section: "settings")`

### T4. Paginare — kaminari deja disponibil

Aplicația folosește deja `kaminari` (vizibil în `orders/index.html.erb` linia 51: `<%= paginate @orders %>`).
Secțiunea "Comenzile mele" va folosi `@orders = current_user.orders.page(params[:page]).per(10)` + `<%= paginate @orders %>`.

### T5. Invoices — legătura cu comenzile

`Order has_one :invoice` (din `order.rb`). Nu toate comenzile au factură — doar cele plătite.
În secțiunea "Comenzile mele", butonul "Descarcă factură" apare doar dacă `order.invoice.present?`.
Link: `invoice_order_path(order, format: :pdf)` — ruta existentă cu `check_order_access` (user-ul vede doar facturile lui).

### T6. Status comenzi — enum existent

Din `order.rb` (liniile 9-18):
```ruby
enum status: {
  pending: "pending", paid: "paid", processing: "processing",
  shipped: "shipped", delivered: "delivered", cancelled: "cancelled",
  refunded: "refunded", expired: "expired"
}
```
Badge-urile din secțiunea "Comenzile mele" mapează direct pe acest enum.

### T7. Devise `resource_name` și `resource` — în contextul AccountController

Formularul Devise din secțiunea "Setări cont" folosește `form_for(resource, as: resource_name, url: registration_path(resource_name))`. Variabilele `resource` și `resource_name` sunt definite de Devise doar în Devise controllers.

**Soluție**: În AccountController, definim helper methods:
```ruby
# app/controllers/account_controller.rb
private

def resource
  @resource ||= current_user
end
helper_method :resource

def resource_name
  :user
end
helper_method :resource_name

def devise_mapping
  Devise.mappings[:user]
end
helper_method :devise_mapping
```

Fără asta, formularul Devise din partial `_settings.html.erb` va da eroare `undefined method resource`.

### T8. Redirect vechi `/users/edit` → dashboard nou

Ruta Devise `/users/edit` (`edit_user_registration_path`) rămâne funcțională. Dacă cineva o accesează direct (bookmark, link vechi), trebuie redirect la `contul_meu_path(section: "settings")`.

**Soluție**: Override `edit` în `CustomRegistrationsController`:
```ruby
def edit
  redirect_to contul_meu_path(section: "settings")
end
```

### T9. Noindex pe paginile de cont

Paginile Devise au deja `<%= render 'shared/noindex' %>`. Pagina "Contul meu" trebuie să aibă la fel — nu vrem ca Google să indexeze adresele utilizatorilor.

Adăugăm `<%= render 'shared/noindex' %>` în `account/show.html.erb`.

### T10. Adrese non-România — validare condiționată

`AddressValidator` validează județ/localitate doar pentru România. Pentru alte țări, județ și localitate sunt input liber (fără autocomplete, fără validare contra tabelelor lookup).

Modelul Address trebuie să reflecte asta:
- `country == "Romania"` → validare cu `AddressValidator` (județ + localitate din tabele)
- Alt country → `county` și `city` sunt presence only, fără lookup

### T11. CNP — nu se stochează în Address

CNP-ul apare în checkout (`orders/_form.html.erb` linia 104) dar NU se stochează în Address (date sensibile). La checkout, când pre-populăm din adresă salvată billing, CNP-ul rămâne gol — user-ul îl completează la fiecare comandă. E intenționat.

### T12. Sidebar logout — `button_to` cu `method: :delete`

Logout-ul din sidebar trebuie să fie `button_to` (nu `link_to`) cu `method: :delete`, identic cu cel din header dropdown:
```erb
<%= button_to "🚪 Log out", destroy_user_session_path, method: :delete %>
```
`link_to` cu `method: :delete` nu funcționează corect cu Turbo (necesită UJS care am scos).

### T13. `toggle_shipping_controller.js` — existent, reutilizabil

Stimulus controller existent (`app/javascript/controllers/toggle_shipping_controller.js`) — folosit în checkout pentru a arăta/ascunde câmpurile billing. Poate fi reutilizat în formularul de adresă dacă avem toggle shipping/billing, sau în secțiunea "Setări cont" pentru toggle-ul inline al formularelor de editare (email/parolă).

---

## Propuneri suplimentare

### A. Telefon pe User — ITERAȚIA 2

Amânat. Necesită: migrație `add_phone_to_users`, permit în Devise strong params, clarificare `current_password` requirement. La pre-populare checkout, va fi fallback:
```ruby
@order.phone = current_user.phone if @order.phone.blank? && current_user.phone.present?
```
(Nu suprascrie valoarea din `last_order`, doar completează dacă lipsește.)

### B. Comenzile mele — design cu carduri (nu tabel admin)

Secțiunea "Comenzile mele" din dashboard NU e tabelul admin existent. E un view nou cu carduri per comandă:

```
┌──────────────────────────────────────────────────────────┐
│ Comanda #1234 • 15 martie 2026         [Badge: Plătită] │
│                                                          │
│  📦 Carte Ayurveda × 2                     49.99 lei    │
│  📦 Supliment Bio × 1                     89.00 lei    │
│                                                          │
│  Total: 188.98 lei    [Detalii]  [Descarcă factură PDF] │
└──────────────────────────────────────────────────────────┘
```

**Status badges:**
- `pending` → gri "În așteptare"
- `paid` → verde "Plătită"
- `processing` → albastru "Se procesează"
- `shipped` → portocaliu "Expediată"
- `delivered` → verde închis "Livrată"
- `cancelled` → roșu "Anulată"
- `refunded` → gri "Rambursată"

**Click pe "Detalii"** — navighează la pagină separată de detalii comandă (stil eMAG):

```
Comenzile mele » Detalii Comandă

Comanda nr. 1234
┌─────────────────────────────────────────────────────────┐
│ Plasată pe:    20 martie 2026, 18:40                    │
│ Total:         188.98 Lei                               │
└─────────────────────────────────────────────────────────┘

┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ Modalitate       │ │ Date facturare   │ │ Modalitate plată │
│ livrare          │ │                  │ │                  │
│                  │ │ Pentru:          │ │ Plata online cu  │
│ Pentru:          │ │ Ion Popescu      │ │ Card bancar      │
│ Ion Popescu      │ │ 0749079619       │ │                  │
│ 0749079619       │ │                  │ │ Plata acceptată  │
│                  │ │ Adresa:          │ │                  │
│ Adresa:          │ │ Str. X nr. 15   │ │ Total: 188.98 Lei│
│ Str. X nr. 15   │ │ București        │ │                  │
│ București        │ │                  │ │ [Factură PDF]    │
└──────────────────┘ └──────────────────┘ └──────────────────┘

📦 Carte Ayurveda × 2                         49.99 lei
📦 Supliment Bio × 1                          89.00 lei
─────────────────────────────────────────────────────────
Total produse:                                188.98 Lei
Cost livrare:                                  20.00 Lei
Total:                                        208.98 Lei
```

**Implementare:**
- Rută nouă: `GET /contul-meu/comenzi/:id` → `AccountController#order_detail`
- Breadcrumb: "Comenzile mele" (link `contul_meu_path(section: "orders")`) » "Detalii Comandă"
- 3 coloane: Livrare / Facturare / Plată (ca în screenshot-ul eMAG)
- Dacă adresele sunt identice, coloana Livrare arată "Aceeași adresă ca facturarea"
- Buton "Factură PDF" doar dacă `order.invoice.present?`
- Acces controlat: user-ul vede doar comenzile lui (`current_user.orders.find(params[:id])`)

**Fișiere view:** 
- `app/views/account/order_detail.html.erb` — view real (wrapper cu sidebar + noindex), Rails îl caută implicit pentru action-ul `order_detail`
- `app/views/account/_order_detail.html.erb` — partial cu conținutul detaliilor (3 coloane + produse + totaluri)

**Paginare:** 10 comenzi/pagină cu kaminari (deja folosit în aplicație).

### C. Adresă implicită (default)

- Câmpul `default: boolean` există deja în migrația propusă
- Adresa marcată ca "implicită" apare prima și are un badge vizual (steluță sau text "Adresă principală")
- La checkout, adresa implicită e pre-selectată automat (viitor)
- Când user-ul setează o adresă ca implicită, celelalte de același tip devin `default: false` — implementat în model cu `before_save :ensure_single_default, if: -> { default? && will_save_change_to_default? }` (vezi secțiunea 2)

### D. Import automat adrese din comenzi existente

La prima vizită pe "Contul meu", dacă user-ul are comenzi dar 0 adrese salvate, afișăm un banner:

```
┌─────────────────────────────────────────────────────────────────┐
│ 💡 Am găsit adrese din comenzile tale anterioare.               │
│    Vrei să le salvezi pentru a le reutiliza?                    │
│                                            [Salvează]  [Nu acum] │
└─────────────────────────────────────────────────────────────────┘
```

**Logica de import** (în AccountController):

1. Extrage TOATE adresele unice din `current_user.orders` — unice pe combinația `shipping_street + shipping_street_number + shipping_city + shipping_county` (ignoră diferențe minore de spațiu/capitalizare)
2. Același lucru pentru billing: unice pe `street + street_number + city + county`
3. Afișează fiecare adresă găsită ca un card cu checkbox bifat implicit + buton "Salvează selectate":

```
┌─────────────────────────────────────────────────────────────────┐
│ 💡 Am găsit adrese din comenzile tale anterioare.               │
│    Selectează pe care vrei să le salvezi:                       │
│                                                                 │
│  ☑ Ion Popescu - 0749079619                                    │
│    Str. Ostașilor nr. 15, București, București                  │
│    (folosită în 3 comenzi, ultima: 15 mar 2026)                │
│                                                                 │
│  ☑ Andrei Gamulea - 0740892806                                 │
│    Str. Mecanicului nr. 18, Vaduri, Neamț                      │
│    (folosită în 1 comandă, ultima: 2 feb 2026)                 │
│                                                                 │
│  ☐ Maria Ionescu - 0722383337                                  │
│    str. Aluminiului 17, Brașov, Brașov                         │
│    (folosită în 1 comandă, ultima: 10 ian 2026)                │
│                                                                 │
│                          [Salvează selectate]  [Nu acum, mersi] │
└─────────────────────────────────────────────────────────────────┘
```

4. User-ul debifează ce nu vrea, apoi "Salvează selectate" creează Address-uri doar pentru cele bifate
5. Prima adresă salvată (cea mai recent folosită) devine `default: true`
6. Afișăm și de câte ori a fost folosită fiecare adresă + data ultimei comenzi — ajută user-ul să decidă care merită salvate

**Detecție adrese unice:**
```ruby
# În AccountController sau un service dedicat
def extract_unique_addresses_from_orders(user, type: :shipping)
  orders = user.orders.order(placed_at: :desc)
  
  if type == :shipping
    fields = %w[shipping_first_name shipping_last_name shipping_company_name
                shipping_street shipping_street_number shipping_block_details
                shipping_city shipping_county shipping_country shipping_postal_code shipping_phone]
  else
    fields = %w[first_name last_name company_name street street_number block_details
                city county country postal_code phone cui email]
  end
  
  seen = {}
  orders.each do |order|
    # Cheia de unicitate: stradă + număr + oraș + județ (normalizate)
    key_field = type == :shipping ? "shipping_street" : "street"
    nr_field  = type == :shipping ? "shipping_street_number" : "street_number"
    city_field = type == :shipping ? "shipping_city" : "city"
    county_field = type == :shipping ? "shipping_county" : "county"
    
    country_field = type == :shipping ? "shipping_country" : "country"
    key = [order[key_field], order[nr_field], order[city_field], order[county_field], order[country_field]]
            .map { |v| v.to_s.strip.downcase }.join("|")
    next if key.blank? || key == "|||"
    
    if seen[key]
      seen[key][:count] += 1
    else
      seen[key] = {
        data: order.slice(*fields),
        count: 1,
        last_used: order.placed_at || order.created_at
      }
    end
  end
  
  seen.values.sort_by { |v| v[:last_used] }.reverse
end
```

**Implementare import (POST action):**
- AccountController primește un array de candidate keys selectate (fiecare candidat poate agrega mai multe comenzi)
- Creează Address-uri din datele acelor candidați, după maparea explicită din câmpurile `Order` (`shipping_*` / billing inline) către schema normalizată `Address` (`first_name`, `street`, `phone`, etc.)
- Ordonare pe `placed_at` (câmpul folosit în `OrdersController#new` linia 38 pentru ultima comandă)
- Redirect la pagina "Contul meu" cu notice "X adrese au fost salvate"

**Condiție de afișare banner:**
- `current_user.addresses.empty? && current_user.orders.exists?`
- Fără flag pe User — dacă user-ul apasă "Nu acum", banner-ul apare din nou la următoarea vizită PÂNĂ când salvează cel puțin o adresă sau apasă "Nu acum" (salvăm dismiss în session: `session[:dismiss_address_import] = true`)

### E. Responsive — sidebar → tabs pe mobil

Sub 768px:
- Sidebar-ul devine o bară orizontală de tabs deasupra conținutului
- Tab-urile scroll horizontal dacă nu încap
- Grid-ul de adrese devine 1 coloană

```css
@media (max-width: 768px) {
  .account-wrapper {
    flex-direction: column;
  }
  .account-sidebar {
    width: 100%;
    display: flex;
    overflow-x: auto;
    border-bottom: 1px solid #ddd;
    gap: 0;
  }
  .account-sidebar a {
    white-space: nowrap;
    border-bottom: 2px solid transparent;
    border-left: none;
  }
  .account-sidebar a.active {
    border-bottom-color: var(--color-primary);
    border-left: none;
  }
  .address-grid {
    grid-template-columns: 1fr;
  }
}
```

---

## Migrații necesare (V1)

| # | Migrație | Descriere |
|---|----------|-----------|
| 1 | `create_addresses` | Tabel addresses cu toate câmpurile |

**Iterația 2:** `add_phone_to_users` (telefon pe User + card în Setări cont)

---

## Ordine de implementare (V1)

1. Migrație `create_addresses` + `rails db:migrate`
2. Model Address (cu validare condiționată RO/non-RO, callback default robust)
3. User model (asocieri `has_many :addresses`, `:shipping_addresses`, `:billing_addresses`)
4. Routes (`contul-meu`, `resources :addresses`)
5. AccountController (cu allowlist secțiuni, helper Devise, `includes` pe orders)
6. AddressesController (CRUD cu `is_shop_page?`)
7. Views: sidebar → secțiuni (addresses grid, billing grid, settings carduri Email+Parolă, orders carduri cu badges)
8. Stimulus controller `address_form_controller.js` (extras din logica checkout)
9. Formularul de adresă (`addresses/_form.html.erb` cu autocomplete cascadă)
10. CSS (`pages/_account.css` cu responsive)
11. Header link-uri + CustomRegistrationsController redirect-uri + redirect `/users/edit`
12. Test manual

**Iterația 2 (features separate):**
- Import automat adrese din comenzi (banner cu selecție multiplă)
- Telefon pe User (migrație + card Setări cont)
- Unificare autocomplete checkout + address form (un singur Stimulus controller)

## Verificare

- Navighează la `/contul-meu` → sidebar vizibil cu toate secțiunile
- Click "Adrese de livrare" → grid gol cu buton "+ Adaugă adresa"
- Adaugă adresă → formular cu autocomplete funcțional → salvează → apare în grid
- Editează/Șterge adresă → funcționează
- Click "Setări cont" → cardurile custom pentru email/parolă/dezactivare se afișează corect, submit-ul postează la rutele Devise standard
- Click "Comenzile mele" → lista comenzilor utilizatorului
- Click "Log out" → delogare

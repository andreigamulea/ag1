# Suita de Teste Automate - Magazin E-commerce

Teste de sistem (browser) care simulează experiența reală a utilizatorului.
**165 teste** care acoperă tot fluxul magazinului: navigare, autentificare, coș, cupoane, checkout, admin, securitate.

---

## Cerințe

### Software necesar

| Software   | Versiune   | Notă                                      |
|------------|------------|--------------------------------------------|
| Ruby       | 3.3.x      | Verifică cu `ruby -v`                     |
| Rails      | 7.1.x      | Verifică cu `rails -v`                    |
| PostgreSQL | 14+        | Trebuie să ruleze pe `localhost:5432`      |
| Chrome     | 120+       | Browser-ul Selenium. Trebuie instalat.     |
| Bundler    | 2.x        | `gem install bundler` dacă lipsește        |

### Configurare bază de date

Baza de date de test (`ag1_test`) trebuie să existe. Configurația din `config/database.yml`:

```yaml
test:
  adapter: postgresql
  encoding: unicode
  database: ag1_test
  pool: 5
  username: postgres
  password: "1"
```

**Dacă ai credențiale diferite**, modifică `config/database.yml` secțiunea `test:`.

### Pregătire inițială (o singură dată)

```bash
# 1. Instalează gem-urile
bundle install

# 2. Creează baza de date de test și rulează migrările
rails db:create RAILS_ENV=test
rails db:migrate RAILS_ENV=test

# 3. (Opțional) Încarcă datele seed în test
rails db:seed RAILS_ENV=test
```

---

## Cum rulez testele

### Toată suita (165 teste, ~2-3 minute)

```bash
rails test test/system/suite/
```

### Cu output detaliat (vezi fiecare test)

```bash
rails test test/system/suite/ --verbose
```

### Un singur fișier de teste

```bash
rails test test/system/suite/authentication_test.rb
```

### Un singur test specific (după numărul liniei)

```bash
rails test test/system/suite/authentication_test.rb:10
```

### Rezultatul așteptat

```
165 runs, ~389 assertions, 0 failures, 0 errors, 0 skips
```

---

## Structura fișierelor

```
test/system/suite/
├── suite_test_helper.rb          # Clasa de bază + toate helper-ele
├── README.md                     # Acest fișier
│
│  ── NAVIGARE & PAGINI ──
├── navigation_test.rb            # 7 teste  - pagini publice, link-uri, footer
├── edge_cases_test.rb            # 7 teste  - 404, pagini legale, reziliență
│
│  ── AUTENTIFICARE ──
├── authentication_test.rb        # 12 teste - login, signup, logout, validări
├── authorization_test.rb         # 12 teste - acces admin vs user vs vizitator
├── account_management_test.rb    # 9 teste  - editare profil, parolă, dezactivare
│
│  ── CATALOG & COȘ ──
├── product_browsing_test.rb      # 10 teste - catalog, detalii produs, căutare
├── cart_management_test.rb       # 14 teste - adăugare, cantitate, ștergere, badge
├── cart_stock_test.rb            # 9 teste  - track_inventory, limită stoc, +/-
│
│  ── CUPOANE ──
├── coupon_test.rb                # 9 teste  - aplicare, ștergere, validări de bază
├── coupon_advanced_test.rb       # 14 teste - expirat, inactiv, minimum, product-specific
│
│  ── CHECKOUT & COMENZI ──
├── checkout_test.rb              # 8 teste  - formular, validări, billing diferit
├── shipping_test.rb              # 5 teste  - transport 20 RON, gratuit, free_shipping
├── order_management_test.rb      # 10 teste - istoric, admin, detalii AJAX, pre-populare
│
│  ── ADMIN ──
├── admin_panel_test.rb           # 14 teste - dashboard, CRUD useri/cupoane/produse
│
│  ── FLUXURI COMPLETE ──
├── full_flow_test.rb             # 3 teste  - călătoria completă a clientului
├── newsletter_test.rb            # 2 teste  - abonare newsletter
```

---

## Ce testează fiecare fișier

### navigation_test.rb (7 teste)
- Pagina principală se încarcă cu titlul corect
- Navigarea prin meniu (Acasă, Cărți, Contact)
- Footer-ul conține link-urile legale
- Logo-ul este prezent

### authentication_test.rb (12 teste)
- Crearea unui cont nou cu email valid
- Login cu credențiale corecte/greșite
- Logout funcționează
- Validări: email invalid, parolă scurtă, parole diferite, email deja folosit
- Butonul show/hide parolă
- Contul dezactivat nu se poate autentifica
- Link parolă uitată și link înregistrare

### authorization_test.rb (12 teste)
- User normal **NU** poate accesa: `/admin`, `/users`, `/users/new`
- Vizitator neautentificat este redirecționat la login din: `/admin`, `/users`, `/orders`
- Paginile publice sunt accesibile: catalog, produs, contact
- Admin poate accesa dashboard-ul și lista de utilizatori
- User vede doar comenzile proprii

### account_management_test.rb (9 teste)
- Accesare pagina de editare profil
- Schimbare parolă cu/fără parola curentă
- Dezactivare cont cu parola corectă/greșită
- User dezactivat nu se poate autentifica
- Admin reactivează un cont dezactivat
- Signup cu email deja existent
- Redirect la pagina anterioară după login

### product_browsing_test.rb (10 teste)
- Catalogul `/carti` afișează produsele
- Pagina de detalii produs conține: titlu, preț, descriere, buton adăugare
- Cantitatea se poate modifica cu +/-
- Produse din alte categorii nu apar pe `/carti`

### cart_management_test.rb (14 teste)
- Adăugare produs din catalog și din pagina de produs
- Adăugare cu cantitate specifică
- Adăugare mai multe produse diferite
- Coșul afișează produsele adăugate cu subtotal
- Actualizarea cantității și ștergerea unui produs
- Butoanele +/- modifică cantitatea
- Badge-ul din header se actualizează
- Link "Finalizează comanda" duce la checkout
- Link "Continuă cumpărăturile" este prezent

### cart_stock_test.rb (9 teste)
- `track_inventory=false` + stoc 0: produsul nu se poate adăuga (bug de routing documentat)
- `track_inventory=false`: cantitatea e limitată la stocul maxim
- `track_inventory=true` + stoc 0: produsul **SE POATE** adăuga
- Actualizare cantitate la 0 șterge produsul din coș
- Adăugarea aceluiași produs de 2 ori cumulează cantitatea
- Coșul persistă după navigare pe alte pagini
- Butoanele +/- funcționează
- Subtotalul se recalculează corect

### coupon_test.rb (9 teste)
- Aplicarea unui cupon procentual și fix valid
- Reducerea apare în sumarul coșului
- Cupon expirat/inactiv nu se aplică
- Cupon inexistent afișează eroare
- Cupon cu valoare minimă coș nesatisfăcută
- Ștergerea unui cupon aplicat
- Câmpul de cupon are atributul `required`

### coupon_advanced_test.rb (14 teste)
- Cupon care nu a început încă
- Cupon cu `usage_limit` atins
- Cupon cu `minimum_quantity` (sub/peste minim)
- Cupon cu `product_id` specific (produsul corect/greșit în coș)
- Cupon procentual vs fix: discount calculat corect
- Cupon `free_shipping`: transportul devine gratuit
- Eliminarea cuponului din coș

### checkout_test.rb (8 teste)
- Pagina de checkout afișează rezumatul comenzii
- Formularul de livrare conține toate câmpurile
- Câmpuri HTML5 `required` prezente
- Toggle adresă de facturare diferită funcționează
- Câmpul de note opțional
- Validarea cu date incomplete
- Checkout-ul cu coșul gol nu dă erori

### shipping_test.rb (5 teste)
- Produs fizic sub 200 RON: transport 20 RON
- Produs fizic peste 200 RON: transport gratuit
- Cupon `free_shipping`: transport gratuit (verificat pe pagina coșului)
- Checkout afișează Subtotal, Transport, Total
- Total corect cu mai multe produse

### order_management_test.rb (10 teste)
- User autentificat vede pagina de istoric comenzi
- User vede doar comenzile proprii
- Admin vede toate comenzile
- Pagina de istoric afișează status
- Admin vede detaliile unei comenzi (AJAX)
- Checkout pre-completează datele din ultima comandă
- Checkout cu billing diferit de shipping
- Validare email invalid și cod poștal prea scurt
- Checkout fără produse în coș

### admin_panel_test.rb (14 teste)
- Dashboard cu link-urile de navigare
- Lista de utilizatori vizibilă
- Formularul de creare utilizator se încarcă
- Editare rol utilizator (Client → Manager)
- Ștergere utilizator (nu pe sine)
- Reactivare utilizator dezactivat
- Lista de cupoane, creare, editare, ștergere cupon
- Lista de produse, creare, ștergere produs

### full_flow_test.rb (3 teste)
- **Călătoria completă**: vizită → cont → catalog → coș → cupon → checkout
- Clientul care doar navighează fără a cumpăra
- Clientul care își face cont, adaugă produse, pleacă, revine

### newsletter_test.rb (2 teste)
- Abonare la newsletter cu email valid
- Validare email newsletter

---

## Helper-ele disponibile (suite_test_helper.rb)

### Crearea datelor de test

```ruby
# Creează un user (role: 0=Client, 1=Admin, 2=Manager)
user = create_test_user(email: "user@test.com", password: "pass123", role: 0, active: true)

# Creează un admin
admin = create_admin_user(email: "admin@test.com", password: "pass123")

# Creează un produs vizibil pe /carti (cu categoriile 'carte' + 'fizic')
product = create_test_product(name: "Carte", price: 50.00, stock: 20)

# Creează un cupon
coupon = create_test_coupon(
  code: "REDUCERE10",
  discount_type: "percentage",   # sau "fixed"
  discount_value: 10,
  active: true,
  starts_at: 1.day.ago,
  expires_at: 30.days.from_now,
  usage_limit: 100,
  minimum_cart_value: nil,       # valoare minimă coș (RON)
  minimum_quantity: nil,         # cantitate minimă în coș
  product_id: nil,               # cupon doar pentru un anumit produs
  free_shipping: false           # transport gratuit
)

# Creează date de locație (necesare pentru comenzi)
create_location_data  # => Romania, Bucuresti, Bucuresti

# Creează o comandă programatic (fără browser)
order = create_test_order(user: user, product: product, status: "paid")
```

### Acțiuni în browser

```ruby
# Autentificare
sign_up(email: "nou@test.com", password: "parola123")
sign_in(email: "existent@test.com", password: "parola123")
sign_out
sign_in_as_admin(email: "admin@test.com", password: "pass123")  # creează + loghează

# Coș
add_product_to_cart(product)   # vizitează pagina produsului și adaugă
go_to_cart                      # navighează la /cart
go_to_checkout                  # navighează la /orders/new

# Formulare checkout
fill_shipping_address(last_name: "Ionescu", first_name: "Maria", ...)
fill_billing_address(email: "maria@test.com", last_name: "Ionescu", ...)
```

---

## Cum să adaugi un test nou

### 1. Creează fișierul (sau adaugă într-unul existent)

```ruby
# test/system/suite/noul_meu_test.rb
require_relative "suite_test_helper"

class NoulMeuTest < SuiteTestCase
  setup do
    # Creează datele necesare
    @product = create_test_product(name: "Produs Test", price: 30.00)
  end

  test "descriere clară a testului" do
    visit carti_path(@product.slug)
    assert_text "Produs Test"
    click_button "Adaugă în coș"
    go_to_cart
    assert_text "Produs Test"
  end
end
```

### 2. Reguli importante

- **Moștenește din `SuiteTestCase`**, nu din `ApplicationSystemTestCase`
- **Nu folosi fixtures**. Creează datele cu helper-ele de mai sus.
- **Adaugă `wait:` explicit** după acțiuni care cauzează navigare:
  ```ruby
  sign_in(email: "user@test.com", password: "pass123")
  assert_selector "#account-toggle", wait: 10   # așteptăm login-ul
  ```
- **Verifică încărcarea paginii** înainte de a interacționa:
  ```ruby
  go_to_checkout
  assert_text "Rezumat comandă", wait: 5         # așteptăm pagina
  ```
- **După `add_product_to_cart`**, verifică adăugarea:
  ```ruby
  add_product_to_cart(product)
  assert_text product.name, wait: 5               # confirmare
  ```
- **Operațiile de delete** necesită JS direct (dialogurile `confirm` nu funcționează fiabil):
  ```ruby
  page.execute_script(<<~JS)
    var meta = document.querySelector('meta[name="csrf-token"]');
    var csrfToken = meta ? meta.content : '';
    fetch('/resursa/ID', {
      method: 'DELETE',
      headers: { 'X-CSRF-Token': csrfToken, 'Accept': 'text/html' },
      credentials: 'same-origin'
    }).then(function(r) { window.location.href = '/redirect'; });
  JS
  ```
- **CSS `text-transform: uppercase`** afectează textul vizibil. Folosește textul așa cum apare pe ecran:
  ```ruby
  assert_text "ADMINISTRARE COMENZI"   # corect (CSS uppercase)
  # NU: assert_text "Administrare Comenzi"  (textul din HTML)
  ```

---

## Probleme cunoscute în aplicație (documentate de teste)

| Problemă | Locație | Impact pe teste |
|----------|---------|-----------------|
| `redirect_to carti_path` fără `:slug` | `cart_controller.rb:24` | Produse cu stoc 0 + `track_inventory=false` cauzează `ActionController::UrlGenerationError` |
| `POST /users` routing conflict | Devise vs UsersController | Admin nu poate crea useri prin formular (Devise interceptează ruta) |
| `edit_user_path` nu există | `users/show.html.erb:22` | Pagina de detalii utilizator dă eroare (ar trebui `admin_edit_user_path`) |
| CouponsController fără autorizare | `coupons_controller.rb` | Orice user autentificat poate accesa CRUD cupoane |
| ProductsController fără autorizare | `products_controller.rb` | Orice user autentificat poate accesa CRUD produse |
| Checkout nu verifică `free_shipping` | `orders_controller.rb:542-552` | Cuponul free_shipping funcționează doar pe pagina coșului |
| 2 câmpuri `user[current_password]` | `devise/registrations/edit.html.erb` | Pagina de editare profil are câmpul duplicat (formular edit + dezactivare) |

---

## Troubleshooting

### Chrome nu se deschide
```
Selenium::WebDriver::Error::WebDriverError: Unable to find chromedriver
```
**Soluție**: Instalează Chrome și chromedriver. Pe Windows, chromedriver se descarcă automat prin gem-ul `selenium-webdriver`.

### Baza de date nu există
```
ActiveRecord::NoDatabaseError: FATAL: database "ag1_test" does not exist
```
**Soluție**: `rails db:create RAILS_ENV=test && rails db:migrate RAILS_ENV=test`

### Teste care eșuează intermitent (flaky)
Dacă 1-2 teste eșuează aleatoriu dar trec la a doua rulare, este o problemă de timing. Cauze posibile:
- Chrome încărcat (prea multe tab-uri deschise)
- PC lent (wait-urile de 5-10 secunde nu sunt suficiente)
- **Soluție**: Rulează din nou. Dacă persistă, crește `wait:` în testul respectiv.

### "Internal Server Error" în teste
Aplicația folosește `config.action_dispatch.show_exceptions = :rescuable`. Excepțiile neînregistrate se propagă direct în teste, ceea ce e util pentru a detecta bug-uri.

### Testele durează prea mult
Suita completă durează ~2-3 minute. Dacă durează mai mult:
- Verifică că nu ai alt proces care blochează portul PostgreSQL
- Verifică că Chrome nu e supraîncărcat
- Rulează un subset: `rails test test/system/suite/authentication_test.rb`

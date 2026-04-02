# Modificări: Mesaje flash la autentificare (login)

**Data:** 2026-04-02  
**Problema:** La logare cu credențiale incorecte (email/parolă greșită) nu apărea niciun mesaj de eroare pentru utilizator.

---

## Modificarea 1: Activarea controller-ului custom pentru sesiuni Devise

### Ce s-a modificat
S-a adăugat linia `sessions: 'custom_sessions'` în configurarea rutelor Devise.

### De ce
Fișierul `app/controllers/custom_sessions_controller.rb` exista deja în proiect și conținea logica de afișare a mesajelor flash la autentificare eșuată (linia 10: `flash[:alert] = I18n.t("devise.failure.not_found_in_database")`). Însă acest controller **nu era înregistrat în rute**, deci Devise folosea controller-ul său implicit care nu setează mesaje flash vizibile la login eșuat.

### Unde
Fișier: `config/routes.rb`, linia 71-74

### Cum
**Înainte:**
```ruby
devise_for :users, controllers: {
  registrations: 'custom_registrations',
  omniauth_callbacks: 'omniauth_callbacks'
}
```

**După:**
```ruby
devise_for :users, controllers: {
  registrations: 'custom_registrations',
  omniauth_callbacks: 'omniauth_callbacks',
  sessions: 'custom_sessions'
}
```

---

## Modificarea 2: Eliminarea mesajelor flash duplicate pe pagina de login

### Ce s-a modificat
S-a adăugat un mecanism `content_for` care permite view-urilor individuale să semnalizeze layout-urilor că mesajele flash sunt deja afișate local, astfel încât layout-ul să nu le mai randeze și el.

### De ce
După activarea controller-ului custom (Modificarea 1), mesajele flash apăreau **de două ori** pe pagina de login:
1. O dată în layout (sus, deasupra formularului)
2. O dată în formularul de login (în interiorul formularului, linia 33)

Utilizatorul a cerut eliminarea mesajelor duplicate și păstrarea doar a celor din formular (cele de jos).

**Notă:** Pagina de login folosește layout-ul `shop.html.erb` (nu `application.html.erb`), deoarece `application_controller.rb` rutează toate paginile Devise către layout-ul shop prin metoda `is_shop_page?` care returnează `true` pentru `devise_controller?`.

### Unde și cum

**Fișier 1: `app/views/devise/sessions/new.html.erb`** — prima linie

Se adaugă un flag `content_for` care semnalizează layout-ului să nu randeze flash messages:

**Înainte:**
```erb
<%= render 'shared/noindex' %>
```

**După:**
```erb
<% content_for :skip_layout_flash, true %>
<%= render 'shared/noindex' %>
```

---

**Fișier 2: `app/views/layouts/shop.html.erb`** — linia 67

Layout-ul shop (folosit de pagina de login) verifică flag-ul înainte de a randa flash messages:

**Înainte:**
```erb
<div class="shop-container">
  <%= render 'shared/flash_messages' %>
  <div class="shop-content">
```

**După:**
```erb
<div class="shop-container">
  <%= render 'shared/flash_messages' unless content_for?(:skip_layout_flash) %>
  <div class="shop-content">
```

---

**Fișier 3: `app/views/layouts/application.html.erb`** — linia 67

Aceeași condiție aplicată și în layout-ul application (pentru consistență):

**Înainte:**
```erb
<div class="default-container">
  <%= render 'shared/flash_messages' %>
  <%= yield %>
</div>
```

**După:**
```erb
<div class="default-container">
  <%= render 'shared/flash_messages' unless content_for?(:skip_layout_flash) %>
  <%= yield %>
</div>
```

### Cum funcționează
1. View-ul de login (`sessions/new.html.erb`) setează `content_for :skip_layout_flash`
2. Rails randează view-ul **înainte** de layout, deci flag-ul e disponibil când layout-ul se randează
3. Layout-urile `shop.html.erb` și `application.html.erb` verifică `content_for?(:skip_layout_flash)` și sar peste randarea flash messages dacă flag-ul e prezent
4. Mesajele flash apar doar o singură dată — cea din interiorul formularului de login

---

## Fișiere implicate (nemodificate, doar referință)

- `app/controllers/custom_sessions_controller.rb` — controller-ul custom care setează flash-ul de eroare (exista deja, nu a fost modificat)
- `app/controllers/application_controller.rb` — conține metoda `choose_layout` care rutează paginile Devise către layout-ul `shop` (nu a fost modificat)
- `app/views/shared/_flash_messages.html.erb` — partial-ul care randează mesajele flash (nu a fost modificat)
- `config/locales/devise.en.yml` — conține textele mesajelor de eroare Devise (nu a fost modificat)

---

# Modificări: Aliniere vizuală pe pagina de login

**Data:** 2026-04-02

---

## Modificarea 3: Aliniere iconițe beneficii cont

### Ce s-a modificat
S-a adăugat lățime fixă și centrare text pe iconițele din secțiunea "De ce sa ai cont?" de pe pagina de login/înregistrare.

### De ce
Emoji-urile (📦, 📍, 🎁, ⏱) au dimensiuni diferite în funcție de font/browser, ceea ce făcea ca textul de lângă ele să nu fie aliniat uniform pe verticală.

### Unde
Fișier: `app/assets/stylesheets/pages/_auth.css`, clasa `.benefit-icon`

### Cum
**Înainte:**
```css
.benefit-icon {
  font-size: 1.3rem;
  flex-shrink: 0;
  margin-top: 1px;
}
```

**După:**
```css
.benefit-icon {
  font-size: 1.3rem;
  flex-shrink: 0;
  width: 2rem;
  text-align: center;
  margin-top: 1px;
}
```

---

## Modificarea 4: Aliniere link-uri Devise (Autentificare, Crează cont, etc.)

### Ce s-a modificat
S-a adăugat `flex: 1` și `text-align: center` pe link-urile din secțiunea de link-uri Devise de sub formularul de login.

### De ce
Link-urile ("Autentificare", "Nu ai cont? Crează un cont nou!", "Ai uitat parola?", "Nu ai primit instrucțiunile de confirmare?") erau afișate cu `justify-content: space-between`, dar textele au lungimi foarte diferite, ceea ce le făcea să pară dezordonate și nealiniate.

### Unde
Fișier: `app/assets/stylesheets/pages/_auth.css`, selectorul `#login-page .devise-links a` (și echivalentele pentru signup-page, forgot-password-page)

### Cum
**Înainte:**
```css
#login-page .devise-links a,
#signup-page .devise-links a,
#forgot-password-page .devise-links a {
  color: var(--color-primary);
  font-weight: bold;
  text-decoration: none;
  position: relative;
  transition: color var(--transition-fast);
}
```

**După:**
```css
#login-page .devise-links a,
#signup-page .devise-links a,
#forgot-password-page .devise-links a {
  color: var(--color-primary);
  font-weight: bold;
  text-decoration: none;
  position: relative;
  transition: color var(--transition-fast);
  flex: 1;
  text-align: center;
}
```

---

## Modificarea 5: Micșorare buton Google login

### Ce s-a modificat
S-a limitat lățimea butonului "Continuă cu Google" și s-a centrat.

### De ce
Butonul ocupa toată lățimea formularului (`width: 100%`), ceea ce îl făcea disproporționat de mare față de conținutul său.

### Unde
Fișier: `app/assets/stylesheets/pages/_auth.css`, clasa `.google-btn`

### Cum
**Înainte:**
```css
.google-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  width: 100%;
  padding: 12px 24px;
  ...
}
```

**După:**
```css
.google-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  max-width: 300px;
  margin: 0 auto;
  padding: 10px 24px;
  ...
}
```

Modificări: `width: 100%` → `max-width: 300px`, adăugat `margin: 0 auto` pentru centrare, `padding` micșorat de la `12px` la `10px`.

---

## Modificarea 6: Confirmare la logout

### Ce s-a modificat
S-a adăugat un dialog de confirmare (`data-turbo-confirm`) pe toate butoanele de logout din aplicație.

### De ce
Best practice UX — previne delogarea accidentală (click greșit, mai ales pe mobil unde butoanele sunt apropiate).

### Unde și cum

Confirmare adăugată în **3 fișiere** — toate butoanele `button_to destroy_user_session_path`:

**Fișier 1: `app/views/account/_sidebar.html.erb`** — linia 26

**Înainte:**
```erb
<%= button_to destroy_user_session_path, method: :delete,
    class: "account-sidebar-link sidebar-logout" do %>
```

**După:**
```erb
<%= button_to destroy_user_session_path, method: :delete,
    class: "account-sidebar-link sidebar-logout",
    form: { data: { turbo_confirm: "Ești sigur că vrei să te deloghezi?" } } do %>
```

---

**Fișier 2: `app/views/layouts/_header.html.erb`** — linia 267

**Înainte:**
```erb
<%= button_to "🚪 Logout", destroy_user_session_path,
    method: :delete,
    form: { style: "margin: 0;" } %>
```

**După:**
```erb
<%= button_to "🚪 Logout", destroy_user_session_path,
    method: :delete,
    form: { style: "margin: 0;", data: { turbo_confirm: "Ești sigur că vrei să te deloghezi?" } } %>
```

---

**Fișier 3: `app/views/layouts/_footer.html.erb`** — linia 17

**Înainte:**
```erb
<%= button_to "Ieși din cont", destroy_user_session_path,
    method: :delete,
    id: "logout_link",
    form: { style: "display: inline;" } %>
```

**După:**
```erb
<%= button_to "Ieși din cont", destroy_user_session_path,
    method: :delete,
    id: "logout_link",
    form: { style: "display: inline;", data: { turbo_confirm: "Ești sigur că vrei să te deloghezi?" } } %>
```

### Cum funcționează
Atributul `data-turbo-confirm` pe `<form>` face ca Turbo (Rails 7) să afișeze un dialog nativ de confirmare înainte de a trimite cererea de logout. Dacă utilizatorul apasă "Cancel", logout-ul nu se execută.

---

## Modificarea 7: Redirect pe prima pagină după logout

### Ce s-a modificat
După logout, utilizatorul este redirecționat mereu pe pagina principală (`root_path`) în loc de pagina anterioară.

### De ce
Anterior, redirect-ul era pe `request.referer` (pagina de unde venea utilizatorul), ceea ce putea duce pe pagini care necesită autentificare, cauzând o redirecționare suplimentară sau o eroare.

### Unde
Fișier: `app/controllers/application_controller.rb`, metoda `after_sign_out_path_for`

### Cum
**Înainte:**
```ruby
def after_sign_out_path_for(_resource_or_scope)
  request.referer || root_path
end
```

**După:**
```ruby
def after_sign_out_path_for(_resource_or_scope)
  root_path
end
```

---

## Modificarea 8: Combinare metode duplicate `after_sign_in_path_for`

### Ce s-a modificat
S-au combinat cele două metode `after_sign_in_path_for` (definite la linia 236 și 253) într-una singură care face ambele operații.

### De ce
Metoda era definită de **două ori** în `application_controller.rb`:
1. Prima (linia 236) — asocia `CartSnapshot`-urile anonime cu utilizatorul la login
2. A doua (linia 253) — redirecționa utilizatorul la ultima pagină vizitată

Ruby suprascrie prima definiție cu a doua, deci **CartSnapshot-urile anonime nu se legau niciodată de user la login** — un bug existent.

### Verificări făcute
- `CartSnapshot` e folosit în `cart_controller.rb` (save_snapshot, clear) — nu e afectat
- `stored_location_for` e alimentat de `store_user_location!` via `before_action` — funcționează normal
- `OmniauthCallbacksController` folosește `sign_in_and_redirect` care apelează indirect `after_sign_in_path_for` — funcționează normal
- Niciun alt controller nu suprascrie metoda

### Unde
Fișier: `app/controllers/application_controller.rb`, liniile 236-255

### Cum
**Înainte (două metode separate, a doua o suprascria pe prima):**
```ruby
# Devise: după login, atașează snapshot-ul la user
def after_sign_in_path_for(resource)
  CartSnapshot.where(session_id: session.id.to_s, user_id: nil).update_all(user_id: resource.id)
  super
end

# ✅ După login, redirecționează către ultima locație memorată
def after_sign_in_path_for(resource_or_scope)
  stored_location_for(resource_or_scope) || super
end
```

**După (o singură metodă care face ambele operații):**
```ruby
# După login: atașează cart snapshot-ul anonim la user + redirect la ultima pagină vizitată
def after_sign_in_path_for(resource)
  CartSnapshot.where(session_id: session.id.to_s, user_id: nil).update_all(user_id: resource.id)
  stored_location_for(resource) || super
end
```

---

## Modificarea 9: Aliniere iconițe sidebar cont

### Ce s-a modificat
S-a adăugat lățime fixă și centrare text pe iconițele din sidebar-ul "Contul meu" (Adrese de livrare, Date facturare, Setari cont, Comenzile mele, Log out).

### De ce
Emoji-urile (📍, 📃, 🔒, 📦, 🚪) au dimensiuni diferite, ceea ce făcea textul de lângă ele nealiniat.

### Unde
Fișier: `app/assets/stylesheets/pages/_account.css`, clasa `.sidebar-icon`

### Cum
**Înainte:**
```css
.sidebar-icon {
  font-size: 1.2rem;
  flex-shrink: 0;
}
```

**După:**
```css
.sidebar-icon {
  font-size: 1.2rem;
  flex-shrink: 0;
  width: 2rem;
  text-align: center;
}
```

---

## Modificarea 10: Îmbunătățire contrast pagina Detalii Comandă

### Ce s-a modificat
S-au îmbunătățit stilurile paginii de detalii comandă pentru a crea o ierarhie vizuală mai clară între secțiuni.

### De ce
Pagina avea un aspect uniform și neseparat — totul era pe nuanțe foarte similare de gri, fără contrast clar între secțiuni. Titlurile, bordurile și totalurile se pierdeau vizual.

### Unde
Fișier: `app/assets/stylesheets/pages/_account.css`

### Cum

**1. Titluri secțiuni coloane (`.order-detail-col h4`) — Modalitate livrare, Date facturare, Modalitate plata:**

**Înainte:**
```css
.order-detail-col h4 {
  font-size: var(--font-size-base);
  color: var(--color-gray-800);
  margin: 0 0 var(--spacing-md) 0;
  padding-bottom: var(--spacing-sm);
  border-bottom: 1px solid var(--color-gray-200);
}
```

**După:**
```css
.order-detail-col h4 {
  font-size: var(--font-size-base);
  color: var(--color-primary);
  background: var(--color-gray-100);
  margin: 0 0 var(--spacing-md) 0;
  padding: var(--spacing-sm) var(--spacing-md);
  border-radius: var(--radius-md);
  border-left: 3px solid var(--color-primary);
}
```

---

**2. Titlu secțiune produse (`.order-detail-products-title`) — Produse comandate:**

**Înainte:**
```css
.order-detail-products-title {
  font-size: var(--font-size-base);
  font-weight: 600;
  color: var(--color-gray-800);
  margin-bottom: var(--spacing-sm);
}
```

**După:**
```css
.order-detail-products-title {
  font-size: var(--font-size-base);
  font-weight: 600;
  color: var(--color-primary);
  background: var(--color-gray-100);
  padding: var(--spacing-sm) var(--spacing-md);
  border-radius: var(--radius-md);
  border-left: 3px solid var(--color-primary);
  margin-bottom: var(--spacing-sm);
}
```

---

**3. Summary comandă (`.order-detail-summary`) — border adăugat:**

**Înainte:**
```css
.order-detail-summary {
  background: var(--color-gray-100);
  border-radius: var(--radius-lg);
  padding: var(--spacing-lg);
  margin-bottom: var(--spacing-xl);
}
```

**După:**
```css
.order-detail-summary {
  background: var(--color-gray-100);
  border: 1px solid var(--color-gray-300);
  border-radius: var(--radius-lg);
  padding: var(--spacing-lg);
  margin-bottom: var(--spacing-xl);
}
```

---

**4. Label-uri summary (`.order-detail-row span:first-child`) — bold + lățime mărită:**

**Înainte:**
```css
.order-detail-row span:first-child {
  min-width: 100px;
  color: var(--color-gray-600);
}
```

**După:**
```css
.order-detail-row span:first-child {
  min-width: 120px;
  color: var(--color-gray-600);
  font-weight: 600;
}
```

---

**5. Totaluri (`.order-detail-totals`) — border adăugat:**

**Înainte:**
```css
.order-detail-totals {
  background: var(--color-gray-100);
  border-radius: var(--radius-lg);
  padding: var(--spacing-lg);
  margin-bottom: var(--spacing-xl);
}
```

**După:**
```css
.order-detail-totals {
  background: var(--color-gray-100);
  border: 1px solid var(--color-gray-300);
  border-radius: var(--radius-lg);
  padding: var(--spacing-lg);
  margin-bottom: var(--spacing-xl);
}
```

---

**6. Total final (`.order-detail-total-final`) — linie primară + bold:**

**Înainte:**
```css
.order-detail-total-final {
  border-top: 2px solid var(--color-gray-300);
  padding-top: var(--spacing-sm);
  margin-top: var(--spacing-sm);
  font-size: var(--font-size-lg);
}
```

**După:**
```css
.order-detail-total-final {
  border-top: 2px solid var(--color-primary);
  padding-top: var(--spacing-sm);
  margin-top: var(--spacing-sm);
  font-size: var(--font-size-lg);
  font-weight: 700;
}
```

---

# Modificări: e-Factura ANAF (UBL 2.1 CIUS-RO)

**Data:** 2026-04-02  
**Funcționalitate:** Export XML în format UBL 2.1 CIUS-RO compatibil cu e-Factura ANAF, pe lângă formatul SAGA existent.

---

## Modificarea 11: Template XML e-Factura (fișier nou)

### Ce s-a creat
Fișier nou `app/views/orders/invoice_efactura.xml.builder` — template XML în format UBL 2.1 CIUS-RO.

### De ce
Formatul SAGA XML existent (`invoice.xml.builder`) nu e compatibil cu sistemul e-Factura ANAF. Pentru conformitate B2B (obligatorie) și B2C (opțională), e necesar formatul UBL 2.1 cu specificația CIUS-RO.

### Unde
Fișier nou: `app/views/orders/invoice_efactura.xml.builder`

### Ce conține
- Namespace-uri UBL 2.1 standard (`urn:oasis:names:specification:ubl:...`)
- `CustomizationID` CIUS-RO: `urn:cen.eu:en16931:2017#compliant#urn:efactura.mfinante.ro:CIUS-RO:1.0.1`
- `AccountingSupplierParty` — date furnizor AYUS GRUP SRL (CIF, adresă, IBAN)
- `AccountingCustomerParty` — date client din comandă (suportă PJ cu CUI și PF cu CNP)
- `PaymentMeans` — cod 48 (card bancar)
- `TaxTotal` cu `TaxSubtotal` grupate pe cote TVA
- `LegalMonetaryTotal` — subtotal, TVA, total
- `AllowanceCharge` — discount global (dacă există)
- `InvoiceLine` — linii produse + transport (cu preț net, cantitate, cota TVA)

---

## Modificarea 12: Rută și acțiune controller e-Factura

### Ce s-a modificat
S-a adăugat rută și acțiune controller pentru descărcarea e-Factura XML.

### De ce
Template-ul XML are nevoie de o rută accesibilă și de o acțiune care să-l randeze și să-l trimită ca fișier descărcabil.

### Unde și cum

**Fișier 1: `config/routes.rb`** — linia 51

**Înainte:**
```ruby
member do
  get :show_items
  get :invoice
end
```

**După:**
```ruby
member do
  get :show_items
  get :invoice
  get :invoice_efactura
end
```

---

**Fișier 2: `app/controllers/orders_controller.rb`** — before_actions (linia 3-5)

**Înainte:**
```ruby
before_action :authenticate_user!, only: [:index, :show_items, :invoice]
before_action :set_order, only: [:show_items, :invoice]
before_action :check_order_access, only: [:show_items, :invoice]
```

**După:**
```ruby
before_action :authenticate_user!, only: [:index, :show_items, :invoice, :invoice_efactura]
before_action :set_order, only: [:show_items, :invoice, :invoice_efactura]
before_action :check_order_access, only: [:show_items, :invoice, :invoice_efactura]
```

---

**Fișier 3: `app/controllers/orders_controller.rb`** — acțiune nouă adăugată după metoda `invoice`

```ruby
def invoice_efactura
  @invoice = @order.invoice

  if @invoice.nil?
    flash[:alert] = "Factură disponibilă doar pentru ordine plătite."
    redirect_to orders_path and return
  end

  xml = render_to_string(
    template: 'orders/invoice_efactura',
    formats: [:xml],
    handlers: [:builder],
    locals: { order: @order, invoice: @invoice }
  )

  filename = "eFactura_#{@invoice.invoice_number}_din_#{@invoice.emitted_at.strftime('%d.%m.%Y')}.xml"

  send_data xml,
            filename: filename,
            type: 'application/xml',
            disposition: 'attachment'
end
```

---

## Modificarea 13: Buton descărcare e-Factura în pagina detalii comandă

### Ce s-a modificat
S-a adăugat un buton verde "Descarca e-Factura (ANAF)" lângă butoanele existente de descărcare PDF și XML SAGA.

### Unde și cum

**Fișier 1: `app/views/account/_order_detail_content.html.erb`** — linia 77

**Înainte:**
```erb
<%= link_to "Descarca XML", invoice_order_path(order, format: :xml), class: "btn-order-invoice btn-order-invoice-xml" %>
```

**După:**
```erb
<%= link_to "Descarca XML (SAGA)", invoice_order_path(order, format: :xml), class: "btn-order-invoice btn-order-invoice-xml" %>
<%= link_to "Descarca e-Factura (ANAF)", invoice_efactura_order_path(order), class: "btn-order-invoice btn-order-invoice-anaf" %>
```

Butonul XML existent a fost redenumit din "Descarca XML" în "Descarca XML (SAGA)" pentru claritate.

---

**Fișier 2: `app/assets/stylesheets/pages/_account.css`** — stiluri noi adăugate după `.btn-order-invoice-xml:hover`

```css
.btn-order-invoice-anaf {
  border-color: #2e7d32;
  color: #2e7d32;
}

.btn-order-invoice-anaf:hover {
  background: #2e7d32;
  color: var(--color-white);
}
```

---

## Modificarea 14: Fix `layout: false` pe acțiunea `invoice_efactura`

### Ce s-a modificat
S-a adăugat `layout: false` la `render_to_string` în acțiunea `invoice_efactura`.

### De ce
Rails încerca să aplice layout-ul HTML (`application.html.erb`) pe un răspuns XML, cauzând eroarea `ActionView::MissingTemplate` — nu există layout în format `.xml.builder`.

### Unde
Fișier: `app/controllers/orders_controller.rb`, metoda `invoice_efactura`

### Cum
**Înainte:**
```ruby
xml = render_to_string(
  template: 'orders/invoice_efactura',
  formats: [:xml],
  handlers: [:builder],
  locals: { order: @order, invoice: @invoice }
)
```

**După:**
```ruby
xml = render_to_string(
  template: 'orders/invoice_efactura',
  formats: [:xml],
  handlers: [:builder],
  layout: false,
  locals: { order: @order, invoice: @invoice }
)
```

---

## Modificarea 15: Corectări validare ANAF pe template-ul e-Factura

### Ce s-a modificat
S-au corectat mai multe erori de validare CIUS-RO raportate de validatorul ANAF.

### De ce
Template-ul inițial nu trecea validarea ANAF din cauza unor incompatibilități cu specificația UBL 2.1 CIUS-RO.

### Unde
Fișier: `app/views/orders/invoice_efactura.xml.builder`

### Corectări aplicate

**1. Ordinea elementelor `Contact` (eroare SAX)**

Ordinea elementelor în UBL e strictă. `Telephone` trebuie înaintea `ElectronicMail`.

**Înainte:**
```ruby
xml.cac :Contact do
  xml.cbc :ElectronicMail, @order.email
  xml.cbc :Telephone, @order.phone.presence || ""
end
```

**După:**
```ruby
xml.cac :Contact do
  xml.cbc :Telephone, @order.phone.presence || ""
  xml.cbc :ElectronicMail, @order.email
end
```

---

**2. CityName furnizor — regula BR-RO-100**

Pentru București cu `CountrySubentity = "RO-B"`, ANAF cere `CityName` codificat ca `SECTORx`.

**Înainte:**
```ruby
xml.cbc :CityName, "Bucuresti"
```

**După:**
```ruby
xml.cbc :CityName, "SECTOR5"
```

---

**3. Categoria TVA dinamică — regulile BR-S-05, BR-O-02, BR-E-05, BR-48**

Inițial toate liniile aveau categoria "S" (Standard) hardcodată. Produsele cu TVA = 0 necesită altă categorie. "O" (Not subject) nu merge dacă firma e plătitoare de TVA (BR-O-02). Categoria corectă e "E" (Exempt).

De asemenea, `Percent` trebuie prezent mereu (inclusiv cu valoarea 0 pentru Exempt — regula BR-E-05 și BR-48).

**Înainte:**
```ruby
# Hardcodat pe toate liniile, TaxSubtotal, AllowanceCharge:
xml.cbc :ID, "S"
xml.cbc :Percent, rate.to_s
```

**După:**
```ruby
# Helper la începutul fișierului:
vat_category = ->(rate) { rate.to_i > 0 ? "S" : "E" }

# Folosit pe toate liniile, TaxSubtotal, AllowanceCharge:
xml.cbc :ID, vat_category.call(rate)
xml.cbc :Percent, rate.to_s  # mereu prezent, inclusiv "0" pentru Exempt

# TaxExemptionReason adăugat pentru categoria E:
if cat_id == "E"
  xml.cbc :TaxExemptionReason, "Scutit de TVA"
end
```

### Reguli ANAF rezolvate
| Regulă | Descriere | Soluție |
|--------|-----------|---------|
| SAX error | Ordine greșită Contact | Telephone înaintea ElectronicMail |
| BR-RO-100 | CityName București | "SECTOR5" în loc de "Bucuresti" |
| BR-S-05 | Cota TVA > 0 pentru "S" | Categoria "E" pentru cota 0 |
| BR-O-02 | "O" interzice VAT ID | Folosit "E" în loc de "O" |
| BR-E-05 | "E" necesită Percent = 0 | Percent prezent mereu |
| BR-48 | TaxSubtotal necesită Percent | Percent prezent mereu |

---

## Modificarea 16: Butoane descărcare factură în lista comenzi (admin + cont utilizator)

### Ce s-a modificat
S-au clarificat și completat butoanele de descărcare factură în lista de comenzi — atât în pagina admin (`/orders`) cât și în pagina utilizatorului ("Comenzile mele").

### De ce
1. Butonul "XML" era generic — nu se înțelegea care format XML
2. Butonul e-Factura (ANAF) lipsea din ambele liste de comenzi
3. Pe pagina admin, butoanele nu erau aliniate (form-ul generat de `button_to` era block)

### Unde și cum

**Fișier 1: `app/views/orders/index.html.erb`** (pagina admin) — linia 60-61

**Înainte:**
```erb
<%= link_to "PDF", invoice_order_path(order, format: :pdf), class: "table-button primary" %>
<%= link_to "XML", invoice_order_path(order, format: :xml), class: "table-button neutral" %>
```

**După:**
```erb
<%= link_to "PDF", invoice_order_path(order, format: :pdf), class: "table-button primary" %>
<%= link_to "SAGA", invoice_order_path(order, format: :xml), class: "table-button neutral" %>
<%= link_to "ANAF", invoice_efactura_order_path(order), class: "table-button success" %>
```

---

**Fișier 2: `app/views/account/_orders.html.erb`** (pagina utilizator) — linia 87-88

**Înainte:**
```erb
<%= link_to "Factura PDF", invoice_order_path(order, format: :pdf), class: "btn-order-action" %>
<%= link_to "XML", invoice_order_path(order, format: :xml), class: "btn-order-action" %>
```

**După:**
```erb
<%= link_to "Factura PDF", invoice_order_path(order, format: :pdf), class: "btn-order-action" %>
<%= link_to "XML (SAGA)", invoice_order_path(order, format: :xml), class: "btn-order-action" %>
<%= link_to "e-Factura", invoice_efactura_order_path(order), class: "btn-order-action btn-order-action-anaf" %>
```

---

**Fișier 3: `app/assets/stylesheets/pages/_admin.css`** — `.table-actions` (aliniere butoane admin)

**Înainte:**
```css
.table-actions {
  white-space: nowrap;
}
```

**După:**
```css
.table-actions {
  white-space: nowrap;
  display: flex;
  gap: 4px;
  align-items: center;
  flex-wrap: wrap;
}

.table-actions form {
  display: inline;
}
```

---

**Fișier 4: `app/assets/stylesheets/pages/_account.css`** — stiluri noi pentru butoanele verzi

```css
.btn-order-action-anaf {
  border-color: #2e7d32;
  color: #2e7d32;
}

.btn-order-action-anaf:hover {
  background: #2e7d32;
  color: var(--color-white);
}
```

---

## Modificarea 17: Reformatare pagină "Produse Comandă" (admin)

### Ce s-a modificat
S-a refăcut complet partial-ul `_order_items.html.erb` (pagina afișată la click pe butonul "Produse" din admin) și s-au adăugat stiluri CSS dedicate.

### De ce
Pagina avea inline styles, tabel fără clase CSS, date de facturare/livrare pe o singură linie neformatată — aspect dezordonat și greu de citit.

### Unde și cum

**Fișier 1: `app/views/orders/_order_items.html.erb`** — rescris complet

Modificări principale:
- Eliminat toate inline styles (`style="..."`)
- Adăugat clase CSS semantice (`order-items-card`, `order-items-table`, `order-items-section`, etc.)
- Tabel cu `thead`, `tbody`, `tfoot` și clase pentru aliniere (`text-center`, `text-right`)
- Secțiunea de facturare — card cu border-left primar și badge "FACTURARE"
- Secțiunea de livrare — card roșu (adresă diferită) sau verde (adresă unică)
- Datele afișate vertical (câte un câmp pe linie) în loc de toate pe un singur rând
- Ascuns CNP-ul implicit `0000000000000`

---

**Fișier 2: `app/assets/stylesheets/pages/_admin.css`** — stiluri noi adăugate la final

Clase noi adăugate:
- `.order-items-card` — container card cu border, padding, shadow
- `.order-items-title` — titlu roșu cu border-bottom primar
- `.order-items-table` — tabel formatat cu thead gri, borders, aliniere
- `.order-items-section` — secțiuni facturare/livrare cu border-left colorat
- `.order-items-badge` — badge-uri colorate (roșu facturare, roșu livrare diferită, verde adresă unică)
- `.order-items-details` — layout vertical pentru date
- `.order-items-actions` — container buton "Înapoi la Lista"

---

**Fișier 3: `app/views/orders/index.html.erb`** — linia 77

Eliminat inline style restrictiv pe containerul de produse.

**Înainte:**
```erb
<div id="order-items-container" style="max-width: 1380px; margin: 20px auto; padding: 0 20px;"></div>
```

**După:**
```erb
<div id="order-items-container"></div>
```

---

## Modificarea 18: Fix căutare produse admin (Turbo compatibility)

### Ce s-a modificat
S-a înlocuit `DOMContentLoaded` cu `turbo:load` pentru inițializarea search-ului și sortării pe pagina de produse admin.

### De ce
În Rails 7 cu Turbo Drive, navigarea între pagini nu declanșează `DOMContentLoaded` (se declanșează doar la prima încărcare a paginii). Evenimentul corect este `turbo:load` care se declanșează la fiecare navigare, inclusiv prin Turbo.

### Unde
Fișier: `app/views/products/index.html.erb`, linia 57

### Cum
**Înainte:**
```javascript
document.addEventListener("DOMContentLoaded", function() {
```

**După:**
```javascript
document.addEventListener("turbo:load", function() {
```

---

## Modificarea 19: Reformatare pagină editare/creare cupon (admin)

### Ce s-a modificat
S-au refăcut complet view-urile și formularul pentru cupoane admin (edit și new) și s-au adăugat stiluri CSS dedicate.

### De ce
Formularul de editare/creare cupon nu avea nicio stilizare — câmpuri fără clase CSS, fără grupare logică, fără placeholder-uri. Aspectul era neformatat și greu de utilizat.

### Unde și cum

**Fișier 1: `app/views/coupons/_form.html.erb`** — rescris complet

Modificări principale:
- Adăugat clase CSS pe formular (`coupon-admin-form`) și pe toate câmpurile (`input-style`)
- Câmpuri grupate în 3 secțiuni logice: "Detalii cupon", "Valabilitate", "Condiții"
- `datetime_select` înlocuit cu `datetime_local_field` (input nativ mai curat)
- Adăugat placeholder-uri pe câmpuri (ex: "Nelimitat", "Toate produsele", "0.00")
- Tip și Valoare reducere pe același rând (`coupon-field-row`)
- Checkbox-urile stilizate cu label alăturat
- Buton submit cu text dinamic ("Crează cupon" / "Salvează modificările")
- Adăugat buton "Anulează" cu link la lista de cupoane

---

**Fișier 2: `app/views/coupons/edit.html.erb`** — refăcut

**Înainte:**
```erb
<%= render 'shared/noindex' %>
<h1>Editare cupon</h1>
<%= render "form", coupon: @coupon %>
```

**După:**
```erb
<%= render 'shared/noindex' %>
<div class="coupon-edit-page">
  <h1 class="admin-title">Editare cupon</h1>
  <%= render "form", coupon: @coupon %>
</div>
```

---

**Fișier 3: `app/views/coupons/new.html.erb`** — refăcut identic cu edit

---

**Fișier 4: `app/assets/stylesheets/pages/_admin.css`** — stiluri noi adăugate la final

Clase noi:
- `.coupon-edit-page` — container centrat, max-width 900px
- `.coupon-admin-form` — card cu border, padding, shadow
- `.coupon-form-grid` — grid layout pentru secțiuni
- `.coupon-form-section` — secțiune cu fundal gri, border-left primar
- `.coupon-section-title` — titlu secțiune roșu cu border-bottom
- `.coupon-field` — container câmp cu label block, margin
- `.coupon-field .input-style` — input stilizat cu focus state
- `.coupon-field-row` — grid 2 coloane pentru câmpuri pe același rând
- `.coupon-checkbox` — checkbox cu label aliniat orizontal
- `.coupon-form-actions` — container butoane submit + anulează
- Responsive: `@media (max-width: 600px)` — grid pe o coloană

---

## Modificarea 20: Reformatare pagină feeduri produse (admin)

### Ce s-a modificat
S-a refăcut view-ul `admin/feeds/index.html.erb` — eliminat toate inline styles și înlocuit cu clase CSS dedicate. Legenda tipuri feeduri transformată din tabel într-un grid card-based.

### De ce
Pagina avea inline styles peste tot (`style="display:inline-block;margin:0;"`, `style="padding: 40px; ..."`, etc.), tabelul de legendă era greu de citit, și stilul era inconsistent cu restul admin-ului.

### Unde și cum

**Fișier 1: `app/views/admin/feeds/index.html.erb`** — rescris complet

Modificări principale:
- Eliminat toate atributele `style="..."` (inline styles)
- Legenda tipuri feeduri — transformată din `<table>` într-un grid de carduri (`.feeds-legend-grid`)
- Butoanele de acțiuni — `form: { style: "display:inline-block;margin:0;" }` înlocuit cu `form: { class: "inline-form" }`
- Secțiunea "Nu există feeduri" — div cu clase CSS în loc de inline styles
- Adăugat diacritice pe texte (Editează, Dezactivează, Șterge, Acțiuni)

---

**Fișier 2: `app/assets/stylesheets/pages/_admin.css`** — stiluri noi adăugate la final

Clase noi:
- `.feeds-legend` — container card cu border, padding
- `.feeds-legend-title` — titlu roșu cu border-bottom
- `.feeds-legend-grid` — grid responsive auto-fill, min 250px
- `.feeds-legend-item` — card individual cu badge + text
- `.feeds-actions-bar` — container buton "+ Adaugă feed"
- `.feeds-date` / `.feeds-no-date` — stiluri dată generare
- `.feeds-empty` — secțiune "Nu există feeduri" stilizată
- `.inline-form` — clasă reutilizabilă pentru `form { display: inline-block; margin: 0; }`

---

# Modificări: Pagina Cărți — "Încarcă mai multe" (Load More)

**Data:** 2026-04-02  
**Funcționalitate:** Înlocuire paginare clasică cu buton "Încarcă mai multe" + fallback `<noscript>` pentru paginare Kaminari clasică.

---

## Modificarea 21: Buton "Încarcă mai multe" pe pagina Cărți

### Ce s-a modificat
S-a implementat un sistem de "load more" pe pagina de cărți care încarcă produse suplimentare fără refresh de pagină, cu fallback la paginare clasică dacă JavaScript nu e disponibil.

### De ce
Experiență de browsing mai fluidă — utilizatorul nu trebuie să dea click pe numere de pagini, vede mai mult conținut natural. Butonul "Încarcă mai multe" (în loc de infinite scroll automat) dă control utilizatorului.

### Cum funcționează
1. Pagina se încarcă normal cu primele 20 produse + buton "Încarcă mai multe"
2. La click pe buton → Stimulus controller face fetch pe `/carti?page=2` cu header `X-Load-More`
3. Controller-ul detectează headerul → returnează doar partial-ul `_product_page` (fără layout)
4. Stimulus parsează HTML-ul, extrage `.product-card` și le adaugă la `#products-grid`
5. Actualizează URL-ul paginii următoare. Dacă nu mai sunt pagini → butonul dispare
6. MutationObserver-ul existent re-egalizează automat înălțimea cardurilor noi
7. Fără JS → `<noscript>` afișează paginarea Kaminari clasică

### Fișiere create

**1. `app/views/carti/_product_card.html.erb`** (nou)

Partial extras din `index.html.erb` — conține markup-ul complet al unui card de produs (cu variante și fără variante). Primește locals: `product`, `product_variants`.

---

**2. `app/views/carti/_product_page.html.erb`** (nou)

Partial returnat la cereri AJAX load-more. Conține cardurile de produse + metadata pentru pagina următoare (`data-next-page-url`, `data-has-next`).

---

**3. `app/javascript/controllers/load_more_controller.js`** (nou)

Stimulus controller cu:
- `static targets`: `button`, `buttonContainer`, `spinner`
- `static values`: `url` (String), `hasNext` (Boolean)
- Metodă `load()`: fetch cu header `X-Load-More`, parsare HTML, append carduri la grid, actualizare buton/spinner

Auto-registrat prin `eagerLoadControllersFrom` existent — fără configurare suplimentară.

### Fișiere modificate

**4. `app/views/carti/index.html.erb`** — rescris

Modificări:
- Bucla de produse folosește `<%= render "carti/product_card" %>` în loc de markup inline
- `id="products-grid"` adăugat pe `.product-grid`
- `<%= paginate @products %>` înlocuit cu wrapper load-more + `<noscript>` fallback
- `DOMContentLoaded` schimbat cu `turbo:load`

---

**5. `app/controllers/carti_controller.rb`** — adăugat randare condiționată

La finalul metodei `index`, adăugat:
```ruby
if request.headers["X-Load-More"].present?
  render partial: "carti/product_page", layout: false
end
```

---

**6. `app/assets/stylesheets/pages/_products.css`** — stiluri noi

Clase adăugate:
- `.load-more-container` — container centrat
- `.load-more-btn` — buton cu border primar, hover cu fundal primar + transform
- `.load-more-spinner` — indicator de încărcare cu animație CSS rotate
- `@keyframes load-more-spin` — animație spinner
- `.carti-pagination` — stil fallback paginare clasică

### Notă: textul butonului
Textul butonului a fost schimbat din "Încarcă mai multe" în **"Vezi mai multe"** la cererea utilizatorului.

---

## Adăugare produse de test (pentru verificare load more)

### De ce
Pagina de cărți avea doar ~15 produse (sub 20/pagină), deci butonul "Vezi mai multe" nu apărea. Au fost create 30 de produse de test pentru a avea mai mult de o pagină.

### Cum se reproduc

Creează fișierul `tmp/seed_test.rb` în directorul aplicației Rails cu conținutul:

```ruby
STDOUT.sync = true
c5 = Category.find(5)  # categoria 'carte'
c4 = Category.find(4)  # categoria 'fizic'
30.times do |i|
  p = Product.create!(
    name: "Carte Ayurveda Test #{i + 1}",
    sku: "TLOAD-#{i + 1}",
    slug: "carte-test-load-#{i + 1}",
    price: rand(20..99),
    stock: rand(10..100),
    status: 'active',
    track_inventory: true,
    custom_attributes: { 'autor' => 'Dr. Test' }
  )
  p.categories << c5
  p.categories << c4
end
puts "Total: #{Product.count}"
```

Execută cu:
```bash
bundle exec rails runner tmp/seed_test.rb
```

**Notă:** ID-urile categoriilor (4 și 5) pot diferi pe alt environment. Verifică cu:
```bash
bundle exec rails runner "Category.pluck(:id, :name).each { |c| puts c.inspect }"
```

### Adăugare imagini pe produsele de test

Produsele de test nu au imagini proprii — li se atribuie ciclic imaginile existente din baza de date:

```bash
bundle exec rails runner "
imgs = Product.where.not(external_image_url: [nil, '']).pluck(:external_image_url)
Product.where('sku LIKE ?', 'TLOAD-%').each_with_index do |p, i|
  p.update_column(:external_image_url, imgs[i % imgs.size])
end
puts 'Done'
"
```

### Ștergere produse de test
```bash
bundle exec rails runner "Product.where('sku LIKE ?', 'TLOAD-%').destroy_all; puts Product.count"
```

---

## Modificarea 22: Link pe produse în rezumatul comenzii

### Ce s-a modificat
Numele produselor din rezumatul comenzii (pagina de plasare comandă) sunt acum clickable — link către pagina produsului, deschis într-un tab nou.

### De ce
Utilizatorul poate vrea să verifice detaliile unui produs din coș înainte de a finaliza comanda.

### Unde
Fișier: `app/views/orders/_cart_summary.html.erb`, linia 19

### Cum
**Înainte:**
```erb
<td>
  <%= product.name %>
  <% if variant %>
    <br><small style="color: #666;"><%= variant.options_text %></small>
  <% end %>
</td>
```

**După:**
```erb
<td>
  <%= link_to product.name, carti_path(product.slug.presence || product.id), target: "_blank" %>
  <% if variant %>
    <br><small style="color: #666;"><%= variant.options_text %></small>
  <% end %>
</td>
```

---

## Modificarea 23: Fix vizibilitate link produs pe hover în rezumat comandă

### Ce s-a modificat
S-au adăugat stiluri CSS pentru link-urile din tabelul rezumatului comenzii, inclusiv pe hover rând.

### De ce
După adăugarea link-ului pe numele produsului (Modificarea 22), la hover pe rândul tabelului (fundal portocaliu) link-ul devenea invizibil — nu avea o culoare contrastantă pe fundalul accent.

### Unde
Fișier: `app/assets/stylesheets/pages/_checkout.css`, după linia 76

### Cum
**Adăugat:**
```css
.checkout-wrapper .cart-summary table td a {
  color: var(--color-gray-800);
  text-decoration: none;
  font-weight: 600;
}

.checkout-wrapper .cart-summary table td a:hover {
  text-decoration: underline;
}

.checkout-wrapper .cart-summary table tbody tr:hover a {
  color: var(--color-primary);
}
```

Link-ul e vizibil în toate stările: gri închis normal, underline la hover link, roșu primar pe fundal portocaliu la hover rând.

---

# Corectări necesare pentru rularea testelor

**Data:** 2026-04-02  
**Problema:** Testele nu pot rula din cauza a 2 probleme: crash bcrypt pe Windows și useri neconfirmați după adăugarea Devise confirmable.

---

## Modificarea 24: Upgrade bcrypt (fix Segmentation fault pe Windows)

### Ce s-a modificat
S-a upgradat gem-ul `bcrypt` de la 3.1.20 la 3.1.22.

### De ce
`bcrypt 3.1.20` crash-a cu Segmentation fault pe Ruby 3.3 / Windows la orice operație de hashing parolă. Niciun test care creează un User nu putea rula.

### Cum
```bash
cd ag1 && bundle update bcrypt
```

Gemfile.lock se actualizează automat de la `bcrypt (3.1.20)` la `bcrypt (3.1.22)`.

---

## Modificarea 25: Adăugare `default_url_options` în test environment

### Ce s-a modificat
S-a adăugat configurarea host-ului pentru Action Mailer în environment-ul de test.

### De ce
Devise confirmable trimite email de confirmare la `User.create!`. Fără `default_url_options[:host]`, template-ul de email crash-a cu "Missing host to link to!".

### Unde
Fișier: `config/environments/test.rb`

### Cum
**Adăugat după linia `config.action_mailer.delivery_method = :test`:**
```ruby
config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }
```

---

## Fix-uri necesare pentru testele existente (neaplicate încă)

După adăugarea modulului Devise `:confirmable` pe modelul User, toți userii creați în teste trebuie să aibă `confirmed_at: Time.current` pentru a trece de autentificare. Fără asta, Devise îi consideră neconfirmați și îi redirecționează la `/users/sign_in`.

### Cauza
Migration-ul `20260402110055_add_confirmable_to_users.rb` a adăugat coloana `confirmed_at`. Userii existenți din producție au fost confirmați automat prin `User.update_all(confirmed_at: Time.current)`, dar testele creează useri noi care nu au `confirmed_at` setat.

### Fix global recomandat

**Opțiunea 1 (cea mai simplă):** Adaugă `confirmed_at: Time.current` la fiecare `User.create!()` din teste.

**Opțiunea 2 (centralizată):** Adaugă în `test/test_helper.rb`:
```ruby
# Dezactivează confirmarea în teste
class User
  before_create :auto_confirm_in_tests

  private

  def auto_confirm_in_tests
    self.confirmed_at ||= Time.current if Rails.env.test?
  end
end
```

### Lista fișierelor de corectat (cu Opțiunea 1)

Adaugă `confirmed_at: Time.current` la fiecare `User.create!()`:

| Fișier | Linie(i) | Ce se adaugă |
|--------|----------|--------------|
| `test/system/suite/suite_test_helper.rb` | 21-32, 34-39 | `confirmed_at: Time.current` în `create_test_user()` și `create_admin_user()` — **rezolvă toate system testele** |
| `test/controllers/security_fixes_test.rb` | 14-20, 22-28, 166-172, 174-180, 266-272, 274-280 | `confirmed_at: Time.current` pe toți userii (6 locuri) |
| `test/controllers/products_controller_variants_test.rb` | 7-13 | `confirmed_at: Time.current` pe @admin |
| `test/integration/product_variants_integration_test.rb` | 11-17 | `confirmed_at: Time.current` pe @admin |
| `test/controllers/admin/option_types_controller_test.rb` | 8-14 | `confirmed_at: Time.current` pe @admin |
| `test/controllers/admin/option_values_controller_test.rb` | 8-14 | `confirmed_at: Time.current` pe @admin |
| `test/controllers/products_controller_test.rb` | 7-13 | `confirmed_at: Time.current` pe @admin |
| `test/controllers/users_controller_test.rb` | 7-13 | `confirmed_at: Time.current` pe @admin |
| `test/models/address_test.rb` | 5-9 | `confirmed_at: Time.current` pe @user |
| `test/models/address_translations_test.rb` | 5-9 | `confirmed_at: Time.current` pe @user |

### Exemplu fix per fișier

**Înainte:**
```ruby
@admin = User.create!(
  email: "admin@test.com",
  password: "password123",
  password_confirmation: "password123",
  role: 1,
  active: true
)
```

**După:**
```ruby
@admin = User.create!(
  email: "admin@test.com",
  password: "password123",
  password_confirmation: "password123",
  role: 1,
  active: true,
  confirmed_at: Time.current
)
```

### Fix suplimentar: test slug auto-generation

**Fișier:** `test/models/product_model_test.rb`, linia 27-30

**Problema:** Testul verifică că un produs fără slug e invalid, dar modelul auto-generează slug-ul din nume prin `before_validation :generate_slug`.

**Fix:** Înlocuiește testul cu unul care verifică auto-generarea:

**Înainte:**
```ruby
test "product should be invalid without a slug" do
  @product.slug = nil
  assert_not @product.valid?
end
```

**După:**
```ruby
test "product slug is auto-generated from name" do
  @product.slug = nil
  @product.valid?
  assert_equal @product.name.parameterize, @product.slug
end
```

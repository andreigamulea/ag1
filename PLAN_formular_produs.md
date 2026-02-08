# PLAN: Formular Produs Unificat (cu/fara variante)

## Obiectiv
Un singur `_form.html.erb` cu toggle "Are variante?" care:
- Cand NU are variante: functioneaza exact ca acum (carti, produse simple)
- Cand ARE variante: ascunde pret/stoc de pe produs, afiseaza sectiunea de variante cu buton "+"

## Principii
- Upload Bunny (imagini + fisiere) se pastreaza exact cum e — nu se modifica
- Produsele existente (carti) nu sunt afectate
- Variantele din feed-uri coexista cu cele adaugate manual
- Coloana `variant_id` pe `order_items` exista deja in DB — se activeaza in cos/checkout

---

## PASUL 1: Model + Controller setup

### 1A. Model — `accepts_nested_attributes_for`

**Fisier:** `app/models/product.rb`

```ruby
BOOL_CASTER = ActiveModel::Type::Boolean.new unless const_defined?(:BOOL_CASTER, false)

accepts_nested_attributes_for :variants, allow_destroy: true,
  reject_if: proc { |attrs|
    # Nu respinge daca e un record existent (are id) sau daca e marcat pt stergere
    # Fallback attrs['x'] || attrs[:x] — compatibilitate cu chei simbol (script/import Ruby)
    id = attrs['id'] || attrs[:id]
    destroying = BOOL_CASTER.cast(attrs['_destroy'] || attrs[:_destroy])
    if id.present? || destroying
      false
    else
      # Varianta "complet goala" = toate campurile blank (inclusiv option_value_ids)
      option_ids = Array(attrs['option_value_ids'] || attrs[:option_value_ids]).reject(&:blank?)
      sku = attrs['sku'] || attrs[:sku]
      price = attrs['price'] || attrs[:price]
      stock = attrs['stock'] || attrs[:stock]
      vat_rate = attrs['vat_rate'] || attrs[:vat_rate]
      sku.blank? &&
        price.blank? &&
        stock.blank? &&
        vat_rate.blank? &&
        option_ids.empty?
    end
  }

# Validare conditionala: price obligatoriu DOAR daca nu are variante active
validates :price, presence: true, unless: :has_active_variants?

private

def has_active_variants?
  if variants.loaded?
    # Asocierea e in memorie (nested attrs / re-render) — tine cont de marked_for_destruction?
    variants.reject(&:marked_for_destruction?).any?(&:active?)
  else
    # Asocierea nu e incarcata — query eficient, fara load complet
    variants.active.exists?
  end
end
```

**De ce `reject_if` verifica TOATE campurile (nu doar sku + price):**
- Variante noi complet goale (fara SKU, pret, stoc, TVA, optiuni) → se ignora (nu se creaza)
- Variante existente (au `id`) → se pot actualiza/sterge mereu (ramura `false`)
- Variante marcate `_destroy: true` → se proceseaza mereu (ramura `false`, altfel stergerea nu functioneaza)
- **De ce si `option_value_ids`:** daca user selecteaza optiuni dar n-apuca sa puna SKU/price,
  `reject_if` vechi (doar sku+price blank) ar arunca varianta → selectiile se pierd la re-render cu erori
  → test "Selectie optiuni → se pastreaza dupa re-render" ar pica
- `Array(attrs['option_value_ids']).reject(&:blank?)` — selecturile trimit `""` pt neales, le filtram
- Nu se verifica `status` (poate fi default "active" din enum) — daca doar status e setat, nu e suficient pt a pastra
- **reject_if NU creeaza "junk" variants:** chiar daca `reject_if` lasa sa treaca o varianta "doar cu optiuni",
  `Variant` are `validates :price, presence: true` + `validates :sku, presence: true` (deja in model)
  → varianta fara price/sku pica la validare → nu se salveaza → user vede eroare pe form
  → selectiile de optiuni se pastreaza (asta e scopul: nu pierzi ce ai ales)

**De ce `attrs['x'] || attrs[:x]` (fallback simbol/string) si `BOOL_CASTER` constanta:**
- Nested attrs din formulare vin mereu cu chei string (`attrs['id']`, `attrs['_destroy']`)
- Dar daca cineva construieste atributele din Ruby (script, import, seed, test):
  `product.variants_attributes = [{id: 1, _destroy: true}]` → chei SIMBOL
- `attrs['id']` pe hash cu chei simbol returneaza `nil` → proc-ul trateaza varianta ca "noua"
  → nu o sterge (ignora `_destroy`) sau o respinge gresit
- `attrs['id'] || attrs[:id]` acopera ambele cazuri fara a schimba logica
- `BOOL_CASTER = ActiveModel::Type::Boolean.new unless const_defined?(:BOOL_CASTER, false)` — hoisted in constanta de model:
  - Fara constanta: se creeaza un obiect `Boolean.new` pentru FIECARE varianta la FIECARE submit
  - Cu constanta: un singur obiect, reutilizat → zero alocari extra
  - `Boolean` e stateless (nu tine stare interna) → safe ca constanta
  - `unless const_defined?(:BOOL_CASTER, false)` — guard pentru dev reload:
    - In development, Rails reincarca modelele la fiecare request (autoload/zeitwerk)
    - Fara guard: `BOOL_CASTER = ...` se executa la fiecare reload → warning `already initialized constant`
    - Warning-ul polueaza log-urile si poate ascunde alte probleme reale
    - `const_defined?` verifica daca constanta exista deja → skip re-definire → zero warnings
    - In production (eager load o singura data): guard-ul nu schimba nimic (constanta nu exista inca)
  - **Scope:** constanta trebuie sa fie in interiorul `class Product < ApplicationRecord`, nu la top-level
    - La top-level: devine constanta globala (`Object::BOOL_CASTER`), vizibila din orice fisier
    - In clasa: devine `Product::BOOL_CASTER`, scoped corect, nu polueza namespace-ul global
    - `const_defined?(:BOOL_CASTER, false)` — `false` = nu cauta in ancestors (nu urcă pe `Object`)
    - Fara `false`: daca cineva defineste `BOOL_CASTER` pe `Object` sau pe `ApplicationRecord`, `const_defined?` returneaza `true` → skip → crash `NameError` cand accesezi `Product::BOOL_CASTER`
    - Cu `false`: cauta DOAR in `Product` → guard 100% corect
    - `const_defined?` cauta in scope-ul curent (clasa) — daca e la top-level, cauta pe `Object`

**De ce `if/else` si NU `next false` in `reject_if` proc:**
- `reject_if` primeste un `Proc` (creat cu `proc { }`)
- `next` in Ruby e valid DOAR in blocuri (`{ }` / `do..end` pasate la iteratori), NU in `Proc` objects
- `proc { next false }` la executie ridica `LocalJumpError: unexpected return`
- `lambda { next false }` ar functiona, dar Rails asteapta `Proc`, nu `Lambda`
- **Solutie:** `if/else` returneaza natural ultima expresie evaluata → `false` din ramura `if`, sau rezultatul blank-check din ramura `else`
- Bug-ul apare DOAR la submit (cand Rails evalueaza proc-ul pe fiecare varianta), nu la page load → greu de prins fara test

**De ce `validates :price, unless: :has_active_variants?`:**
- La create cu toggle ON: user pune pret pe variante, NU pe produs → `product.price` e blank
- Fara `unless`: `validates :price, presence: true` pica → formularul nu se salveaza
- Cu `unless`: daca produsul are variante **active** (care nu sunt marcate pt stergere), `price` pe Product nu e obligatoriu
- Produse fara variante (carti): `has_active_variants?` returneaza `false` → `price` ramane obligatoriu (ca inainte)
- **De ce `active?` si nu doar `any?`:** daca produsul are DOAR variante inactive, in shop/cart
  se comporta ca produs simplu (`product.variants.active.exists?` = false → nu cere variant_id).
  Dar daca `product.price` e nil → crash/pret gresit. `active?` aliniaza validarea cu runtime-ul.
- **De ce `variants.loaded?` branch:**
  - Cu nested attrs (create/update cu variante): asocierea e in memorie → `reject(&:marked_for_destruction?)`
    tine cont de variantele marcate pt stergere (nu incarcate din DB)
  - Fara nested attrs (ex: validare in console, alte contexte): `variants.active.exists?` face un singur
    `SELECT 1` → eficient, fara a incarca toate variantele
  - `marked_for_destruction?` exista doar pe obiecte incarcate → branch-ul `exists?` nu pierde informatie
- `reject(&:marked_for_destruction?)` previne edge case: user sterge toate variantele si trimite fara pret
  → variantele marcate `_destroy` nu conteaza → `has_active_variants?` = false → `price` e obligatoriu
- Daca ai validari similare pe `stock` pe Product, aplica acelasi pattern

### 1B. Controller — `product_params` + `before_action`

**Fisier:** `app/controllers/products_controller.rb`

Adauga in `product_params`:
```ruby
variants_attributes: [:id, :sku, :price, :stock, :status, :vat_rate, :_destroy,
                       option_value_ids: []]
```

**`before_action` si `helper_method`:**
```ruby
before_action :load_option_types, only: %i[new edit create update]
helper_method :preload_variants

private

def load_option_types
  @option_types = OptionType.includes(:option_values).all
end
```

**De ce `before_action` si nu in fiecare metoda:**
- La `create` cand validarile pica si faci `render :new`, `@option_types` trebuie sa existe
- La `update` cand validarile pica si faci `render :edit`, la fel
- Daca `@option_types` e nil la re-render → crash in view (`undefined method 'each' for nil`)
- `before_action` garanteaza ca variabila exista in TOATE cele 4 cazuri (new, edit, create fail, update fail)

### 1C. Controller — helper `preload_variants`

```ruby
private

def preload_variants(product)
  variants = product.variants.to_a
  persisted = variants.select(&:persisted?)
  if persisted.any?
    preloader = ActiveRecord::Associations::Preloader.new
    preloader.preload(persisted, :option_values) if Variant.reflect_on_association(:option_values)
    preloader.preload(persisted, :order_items)   if Variant.reflect_on_association(:order_items)
    preloader.preload(persisted, :external_ids)  if Variant.reflect_on_association(:external_ids)
  end
  variants
end
```

**De ce `helper_method :preload_variants`:**
- `preload_variants` e apelat din view (`_form.html.erb`) nu din controller action
- Metodele `private` din controller NU sunt accesibile din view context
- `helper_method` expune metoda catre view fara a o face publica in controller
- Fara asta: `undefined method 'preload_variants'` in view

**De ce `product.variants.to_a` si nu `product.variants.includes(...)`:**
- Dupa submit invalid, `form.object.variants` poate contine variante nesalvate (construite din params)
- `includes(...)` returneaza un ActiveRecord::Relation = face query in DB = pierde variantele nesalvate
- `.to_a` converteste la array = pastreaza si variantele nesalvate din memorie
- `Preloader.new.preload(persisted, ...)` face eager loading DOAR pe cele persistate (eficient)
- Rezultat: tabelul afiseaza si variantele noi (nesalvate) dupa re-render cu erori

**De ce `reflect_on_association` pe TOATE asociatiile (nu doar `external_ids`):**
- `preloader.preload(persisted, :option_values)` crapa daca asociatia nu exista (redenumire, alt branch)
- Guard doar pe `external_ids` lasa `option_values` si `order_items` neprotejate
- `reflect_on_association` verifica daca asociatia exista pe model INAINTE de a face query
- Daca exista → preload (previne N+1). Daca nu → skip (view-ul functioneaza cu N+1, dar nu crapa)
- In branch-ul curent toate 3 asociatiile exista → guard-ul nu schimba nimic (pur defensiv)

---

## PASUL 2: Toggle in formular

**Fisier:** `app/views/products/_form.html.erb`

Dupa sectiunea "Inventar si Stoc", adauga:

```erb
<!-- Toggle variante -->
<div class="form-section">
  <div class="section-header primary">
    Variante
  </div>
  <div class="section-body">
    <div class="checkbox-field">
      <%= hidden_field_tag "toggle-variants", "0", id: nil %>
      <% tv = Array(params["toggle-variants"]).last %>
      <% checked =
           if tv.nil?
             form.object.variants.active.any?
           else
             tv == "1"
           end
      %>
      <%= check_box_tag "toggle-variants", "1", checked, id: "toggle-variants" %>
      <%= label_tag "toggle-variants", "Acest produs are variante" %>
    </div>
    <% if form.object.persisted? && form.object.variants.active.any? && !checked %>
      <p class="form-hint warning" id="variants-active-warning">
        Produsul are variante active. Debifarea doar ascunde tabelul.
        Pentru dezactivare, setează toate variantele ca Inactive.
      </p>
    <% end %>
  </div>
</div>
```

**De ce `variants.active.any?` (nu `variants.any?`) pentru toggle default:**
- `variants.any?` include si variante inactive → toggle ON
- Dar `validates :price, unless: :has_active_variants?` verifica doar **active** variants
- Mismatch: toggle ON ascunde campul price, dar validarea cere price (nu sunt active variants)
  → formularul nu se poate salva fara a da toggle OFF manual
- `variants.active.any?` aliniaza default-ul cu logica de validare:
  - Doar inactive → toggle OFF → price vizibil → user il completeaza → save OK
  - Cel putin una active → toggle ON → price ascuns → validarea trece → save OK

**De ce `check_box_tag` si NU `form.check_box :has_variants`:**
- `has_variants` nu exista ca atribut pe Product (nici coloana, nici attr_accessor)
- `form.check_box :has_variants` ar cauza `undefined method 'has_variants'` pe view
- Parametrul `product[has_variants]` ar ajunge in controller ca "Unpermitted parameter"
- `check_box_tag` e pur UI — controleaza JS-ul
- Starea initiala: `form.object.variants.active.any?` (daca are variante **active**, e checked)

**De ce `form.object` si nu `product`:**
- `_form.html.erb` primeste `form` ca builder. `product` poate exista ca local variable
  dar nu e garantat in toate contextele (ex: re-render dupa erori)
- `form.object` e mereu disponibil — e obiectul legat de builder
- Previne `NameError: undefined local variable or method 'product'`

**De ce `id: nil` pe hidden field:**
- `hidden_field_tag "toggle-variants"` genereaza implicit `id="toggle-variants"` pe hidden input
- `check_box_tag ... id: "toggle-variants"` creeaza ACELASI id pe checkbox
- Doua elemente cu acelasi id → `document.getElementById("toggle-variants")` poate returna hidden input, nu checkbox
  → toggle JS nu functioneaza. `label_tag` poate targeta hidden input → click pe label nu bifeaza checkbox
- `id: nil` elimina id-ul de pe hidden field → un singur element cu `id="toggle-variants"` (checkbox-ul)
- `name` ramane "toggle-variants" pe ambele → params functioneaza identic

**De ce `hidden_field_tag` + `Array(params["toggle-variants"]).last`:**
- Checkbox-urile HTML NU trimit nimic cand sunt unchecked (nu "0", literalmente nimic)
- Fara hidden field: user debifeza toggle → submit invalid → `params["toggle-variants"]` e nil
  → `form.object.variants.active.any?` decide → daca produsul are variante active, toggle revine ON = inconsistent
- Cu hidden field: unchecked trimite "0", checked trimite ["0", "1"] (hidden + checkbox)
- `Array(...).last` ia ultima valoare: "0" (unchecked) sau "1" (checked)
- `tv.nil?` = prima incarcare (fara submit) → foloseste `form.object.variants.active.any?` (stare din DB, doar active)
- `tv == "1"` / `tv == "0"` = dupa submit → respecta intentia user-ului

---

## PASUL 3: Conditionalitate UI (JS)

Cand toggle "Are variante" e ON:
- **Ascunde:** sectiunea "Preturi si Taxe" (price, cost_price, discount_price, vat) de pe Product
- **Ascunde:** sectiunea "Inventar si Stoc" (stock, stock_status, track_inventory)
- **Readonly/disabled vizual:** inputurile din sectiunile ascunse
- **Arata:** sectiunea "Variante" cu tabelul de variante si butonul "+"

Cand toggle e OFF:
- **Arata:** "Preturi si Taxe" si "Inventar si Stoc" (ca acum)
- **Editabil:** inputurile redevin editabile
- **Ascunde:** sectiunea "Variante"

**De ce readonly pe `input[text/number]`/`textarea`, pointerEvents pe `select`/`checkbox`/`radio`:**
- `readonly` pe input text/number/textarea: input-ul SE trimite dar nu se poate edita
  → validarile `validates :price, presence: true` de pe Product trec
- `readonly` pe `<select>` NU FUNCTIONEAZA — e ignorat de browsere
- `readonly` pe `<input type="checkbox/radio">` e LA FEL IGNORAT — user poate bifa/debifa liber
- `disabled` pe select/checkbox/radio: elementul NU se trimite → validarile pot pica
- Solutie: `pointerEvents = "none"` + `tabIndex = -1` pe select, checkbox si radio
  → nu se poate interactiona (nici click, nici Tab+Space), dar SE trimite valoarea → validarile trec
- Checkbox-uri afectate: `track_inventory` din sectiunea stoc (daca e bifat, trebuie sa ramana trimis)
- `display: none` singur nu e suficient — input-urile ascunse tot se trimit
  si pot fi editate prin DevTools
- `setVisible` salveaza display-ul original in `data-orig-display` si restaureaza la show
  → nu forteaza `"block"` pe sectiuni care pot fi `flex`/`grid` (previne regresii la CSS changes)

**De ce `bindLockGuards` cu capture-phase listener (nu doar `pointerEvents`):**
- `pointerEvents: none` pe checkbox/radio blocheaza click-ul **direct** pe element
- Dar daca checkbox-ul are un `<label for="...">`, click pe label NU trece prin checkbox
  → browser-ul declanseaza toggle-ul intern, ocolind `pointerEvents` complet
- `bindLockGuards` ataseaza un listener in **capture phase** pe sectiune
  → intercepteaza click/keydown INAINTE sa ajunga la target
  → daca `section.dataset.locked === "1"`, face `preventDefault()` + `stopPropagation()`
  → nici click direct, nici click pe label, nici Tab+Space nu mai pot schimba valoarea
- Guard `lockGuardBound` previne dubla atasare (acelasi pattern ca `changeBound`)
- `dataset.locked` e setat/sters in `updateSections()` → sincronizat cu toggle-ul

**De ce salvare/restaurare `tabindex` original (nu `removeAttribute` direct):**
- Daca un select avea `tabindex="2"` si facem toggle ON → `tabIndex = -1` → toggle OFF →
  `removeAttribute("tabindex")` → pierdut permanent `tabindex="2"`
- Solutie: la lock, salvam tabindex original in `data-orig-tabindex` (doar o data)
- La unlock, restauram valoarea originala (sau `removeAttribute` daca nu exista initial)
- Nu afecteaza datele, doar pastreaza accesibilitatea/UX in limitele initiale

**De ce `turbo:load` si nu `DOMContentLoaded`:**
- Rails 7 foloseste Turbo Drive — navigarile interne nu refac pagina complet
- `DOMContentLoaded` se executa DOAR la primul page load (full refresh)
- La navigare Turbo (ex: click pe "Editeaza" din lista produse), `DOMContentLoaded` nu se mai
  executa → toggle-ul si butoanele +/- nu functioneaza
- `turbo:load` se executa la FIECARE navigare (si Turbo si full refresh)
- Guard `if (!toggle) return` previne erori pe pagini care nu au formularul

**Implementare:** vanilla JS (fara Stimulus, consistent cu restul formularului):

```javascript
document.addEventListener("turbo:load", () => {
  const toggle = document.getElementById("toggle-variants");
  if (!toggle) return;

  const priceSection = document.getElementById("section-prices");
  const stockSection = document.getElementById("section-stock");
  const variantsSection = document.getElementById("section-variants");
  if (!priceSection || !stockSection || !variantsSection) return;

  function setReadonly(section, locked) {
    section.querySelectorAll("input, textarea").forEach(el => {
      const type = (el.getAttribute("type") || "").toLowerCase();
      if (type === "checkbox" || type === "radio") {
        // readonly e ignorat de browsere pe checkbox/radio — folosim pointerEvents (ca pe select)
        el.style.pointerEvents = locked ? "none" : "";
        if (locked) {
          if (!el.dataset.origTabindex) {
            el.dataset.origTabindex = el.hasAttribute("tabindex") ? el.getAttribute("tabindex") : "__none__";
          }
          el.tabIndex = -1;
        } else {
          if (el.dataset.origTabindex === "__none__") el.removeAttribute("tabindex");
          else if (el.dataset.origTabindex) el.setAttribute("tabindex", el.dataset.origTabindex);
          delete el.dataset.origTabindex;
        }
      } else {
        el.readOnly = locked;
      }
    });
    section.querySelectorAll("select").forEach(el => {
      el.style.pointerEvents = locked ? "none" : "";
      if (locked) {
        // Salveaza tabindex original (doar o data) pt a-l restaura la unlock
        if (!el.dataset.origTabindex) {
          el.dataset.origTabindex = el.hasAttribute("tabindex") ? el.getAttribute("tabindex") : "__none__";
        }
        el.tabIndex = -1;
      } else {
        if (el.dataset.origTabindex === "__none__") el.removeAttribute("tabindex");
        else if (el.dataset.origTabindex) el.setAttribute("tabindex", el.dataset.origTabindex);
        delete el.dataset.origTabindex;
      }
    });
  }

  // Lock guard: previne click pe <label> care ocoleste pointerEvents pe checkbox/radio
  function bindLockGuards(section) {
    if (section.dataset.lockGuardBound) return;
    section.dataset.lockGuardBound = "1";

    function blockIfLocked(e) {
      if (section.dataset.locked !== "1") return;
      const t = e.target;
      if (t.closest("input[type=checkbox], input[type=radio], select, label")) {
        e.preventDefault();
        e.stopPropagation();
      }
    }

    section.addEventListener("click", blockIfLocked, true);   // capture phase
    section.addEventListener("keydown", blockIfLocked, true);  // capture phase
  }

  // Salveaza display-ul original (doar o data) pt a-l restaura corect
  // (evita sa forteze "block" pe sectiuni care pot fi "flex"/"grid")
  [priceSection, stockSection, variantsSection].forEach(el => {
    if (!el.dataset.origDisplay) {
      const d = el.style.display;
      el.dataset.origDisplay = (d && d !== "none") ? d : "";
    }
  });

  function setVisible(el, visible) {
    el.style.display = visible ? (el.dataset.origDisplay || "") : "none";
  }

  function updateSections() {
    if (toggle.checked) {
      setVisible(priceSection, false);
      setVisible(stockSection, false);
      setVisible(variantsSection, true);
      setReadonly(priceSection, true);
      setReadonly(stockSection, true);
      priceSection.dataset.locked = "1";
      stockSection.dataset.locked = "1";
    } else {
      setVisible(priceSection, true);
      setVisible(stockSection, true);
      setVisible(variantsSection, false);
      setReadonly(priceSection, false);
      setReadonly(stockSection, false);
      delete priceSection.dataset.locked;
      delete stockSection.dataset.locked;
    }
    bindLockGuards(priceSection);
    bindLockGuards(stockSection);
  }

  // Guard: Turbo back/forward cache poate reutiliza DOM-ul → listenerul vechi ramane,
  // iar turbo:load mai ataseaza inca unul. changeBound previne dubla atasare.
  if (!toggle.dataset.changeBound) {
    toggle.dataset.changeBound = "1";
    toggle.addEventListener("change", updateSections);
  }
  updateSections(); // stare initiala
});
```

**De ce guard `changeBound` pe toggle:**
- La navigare Turbo normala (replace body), elementul toggle e nou → listenerul vechi dispare → OK
- Dar la **back/forward din Turbo cache**, DOM-ul poate fi reutilizat → listenerul vechi ramane
- `turbo:load` ruleaza din nou si mai ataseaza inca un listener → `updateSections()` ruleaza de 2-3 ori la un singur change
- Rezultat vizibil: flicker (show/hide repetat) sau executii multiple in console
- Guard `data-change-bound` = handler-ul se ataseaza o singura data per element
- `updateSections()` (fara guard) SE executa mereu — seteaza starea initiala corecta la fiecare navigare

**De ce guard `if (!priceSection || !stockSection || !variantsSection) return`:**
- Daca ID-urile lipsesc din view (uitat sa le adauge, typo), `setReadonly(null, ...)` ar crapa
- Fara guard: JS-ul esueaza complet → nicio functionalitate (toggle, +, x) nu mai merge
- Cu guard: JS-ul se opreste graceful, restul paginii functioneaza

**ID-uri necesare pe sectiunile din _form.html.erb:**
- Sectiunea "Preturi si Taxe": `id="section-prices"`
- Sectiunea "Inventar si Stoc": `id="section-stock"`
- Acestea trebuie adaugate pe div-urile `.form-section` existente

---

## PASUL 4: Sectiunea Variante (tabel + buton "+")

**In `_form.html.erb`:**

```erb
<% option_types = (@option_types || []) %>
<% option_types_json = option_types.map { |ot|
     { id: ot.id, name: ot.name, values: ot.option_values.map { |ov|
       { id: ov.id, name: ov.display_name }
     }}
   }.to_json %>

<div class="form-section" id="section-variants" style="display: none;"
     data-variant-statuses="<%= Variant.statuses.keys.join(',') %>"
     data-option-types="<%= ERB::Util.html_escape(option_types_json) %>">
  <div class="section-header info">
    Variante Produs
  </div>
  <div class="section-body">
    <table class="variants-table" id="variants-table">
      <thead>
        <tr>
          <th>SKU</th>
          <th>Pret (RON)</th>
          <th>Stoc</th>
          <th>TVA %</th>
          <th>Status</th>
          <th>Optiuni</th>
          <th>Sursa</th>
          <th></th>
        </tr>
      </thead>
      <tbody id="variants-body">
        <% variants = respond_to?(:preload_variants) ? preload_variants(form.object) : form.object.variants.to_a %>
        <% variants.each.with_index do |variant, i| %>
          <%= render "products/variant_fields", form: form, variant: variant, option_types: option_types %>
        <% end %>
      </tbody>
    </table>

    <button type="button" id="add-variant-btn" class="btn btn-secondary">
      + Adauga varianta
    </button>
  </div>
</div>
```

**De ce `(@option_types || [])` normalizat in variabila locala:**
- `@option_types` e setat de `before_action :load_option_types` in `ProductsController`
- Daca `_form` e randat din alt controller fara acel `before_action`, `@option_types` e nil
  → `nil.map` → crash cu `undefined method 'map' for nil`
- `|| []` normalizeaza: nil devine array gol → `map` returneaza `[]` → JSON `"[]"` → JS primeste array gol
- Variabila locala `option_types` e folosita si la `render "products/variant_fields"` → consistenta

**De ce `render "products/variant_fields"` (nu `render "variant_fields"`):**
- `render "variant_fields"` cauta partial-ul relativ la view-ul curent (`views/products/`)
- Daca `_form` e randat din alt controller (ex: admin), Rails cauta `views/admin/_variant_fields.html.erb` → crash
- `render "products/variant_fields"` e path absolut → functioneaza din orice controller

**De ce `ERB::Util.html_escape` (nu `json_escape`) pe `data-option-types`:**
- `to_json` poate genera caractere speciale (`"`, `<`, `>`, `&`) care rup atributul HTML
- Exemplu: option type cu numele `A"4` → JSON contine `"` → rupe `data-option-types="..."`
- `ERB::Util.json_escape` in Rails nu garanteaza escaparea `"` in context de atribut HTML — poate produce "attribute break"
- `ERB::Util.html_escape` (sau `h()`) escapeaza corect `"` → `&quot;`, `<` → `&lt;`, `&` → `&amp;`
- Browserul decodifica automat entitatile HTML in `dataset` → `JSON.parse(section.dataset.optionTypes)` functioneaza corect
- Rezultat: atributul HTML e valid si JSON-ul ajunge intact in JS

**De ce `respond_to?(:preload_variants)` cu fallback:**
- `preload_variants` e definit ca `helper_method` in `ProductsController` (Pas 1C)
- Daca `_form.html.erb` e randat dintr-un ALT controller (ex: viitor `Admin::ProductsController`),
  `preload_variants` nu exista → crash cu `undefined method`
- `respond_to?` verifica daca helper-ul e disponibil in contextul curent
- Fallback: `form.object.variants.to_a` — functioneaza mereu, doar fara eager loading (acceptabil pt cazuri rare)
- In `ProductsController` (cazul normal): `respond_to?` returneaza `true` → se foloseste `preload_variants` cu eager loading

**De ce `includes(:option_values, :external_ids, :order_items)` (preloaded in helper):**
- Fara preload, fiecare rand de varianta face 3 query-uri extra:
  - `variant.option_values.any?` → 1 query
  - `variant.external_ids.any?` → 1 query (pt badge "feed"/"manual")
  - `variant.order_items.any?` → 1 query (pt lacat vs buton "x")
- Cu 20 variante = 60 query-uri extra. Preloader le reduce la 3 total.

**De ce `data-variant-statuses` si `data-option-types`:**
- Butonul "+" creeaza randuri noi din JS (nu din server)
- JS-ul are nevoie de lista de status-uri si option types ca sa genereze select-urile
- Daca le hardcodam in JS (`<option value="active">`) si enum-ul se schimba, avem divergenta
- `data-*` attributes = sursa de adevar vine din Ruby, JS doar citeste

---

## PASUL 5: Partial `_variant_fields.html.erb`

**Fisier NOU:** `app/views/products/_variant_fields.html.erb`

```erb
<%= form.fields_for :variants, variant do |vf| %>
  <% feed = variant.respond_to?(:external_ids) && variant.external_ids.any? %>
  <tr class="variant-row" data-variant-id="<%= variant.id %>">
    <td>
      <%= vf.hidden_field :id if variant.persisted? %>
      <%= vf.text_field :sku, placeholder: "SKU", size: 15 %>
    </td>
    <td>
      <%= vf.number_field :price, step: 0.01, placeholder: "0.00", size: 8 %>
    </td>
    <td>
      <%= vf.number_field :stock, placeholder: "0", size: 5 %>
    </td>
    <td>
      <%= vf.number_field :vat_rate, step: 0.01, placeholder: "19", size: 5 %>
    </td>
    <td>
      <%= vf.select :status, Variant.statuses.keys.map { |s| [s.humanize, s] } %>
    </td>
    <td>
      <% feed_with_options = feed && variant.respond_to?(:option_values) && variant.option_values.any? %>
      <% if feed_with_options %>
        <span class="variant-options-text"><%= variant.options_text %></span>
      <% else %>
        <% selected_ids = (variant.respond_to?(:option_value_ids) ? variant.option_value_ids : []).map(&:to_s) %>
        <% option_types.each do |ot| %>
          <select name="<%= "#{vf.object_name}[option_value_ids][]" %>">
            <option value="">-- <%= ot.name %> --</option>
            <% ot.option_values.each do |ov| %>
              <option value="<%= ov.id %>"
                <%= "selected" if selected_ids.include?(ov.id.to_s) %>>
                <%= ov.display_name %>
              </option>
            <% end %>
          </select>
        <% end %>
      <% end %>
    </td>
    <td>
      <% if variant.persisted? && feed %>
        <span class="badge badge-feed" title="Sincronizat din feed. Modificarile pot fi suprascrise.">feed</span>
      <% elsif variant.persisted? %>
        <span class="badge badge-manual">manual</span>
      <% else %>
        <span class="badge badge-new">nou</span>
      <% end %>
    </td>
    <td>
      <% has_orders = variant.persisted? && variant.respond_to?(:order_items) && variant.order_items.any? %>
      <% if has_orders %>
        <!-- Nu permite stergere — are comenzi -->
        <span title="Varianta are comenzi asociate">&#128274;</span>
      <% else %>
        <%= vf.hidden_field :_destroy, value: "0", id: nil %>
        <button type="button" class="remove-btn remove-variant"
                title="Sterge varianta">x</button>
      <% end %>
    </td>
  </tr>
<% end %>
```

**De ce `vf.hidden_field :id` IN INTERIORUL `<td>` (nu inainte de `<tr>`):**
- Fara `:id` in params, Rails trateaza fiecare varianta ca "record nou" la update
- Rezultat: la fiecare save se creeaza DUPLICATE in loc de update
- `vf.hidden_field :id` transmite ID-ul variantei existente → Rails stie sa faca UPDATE
- Doar pentru `variant.persisted?` — variantele noi nu au inca id
- **Plasat in `<td>`, nu inainte de `<tr>`:** un `<input>` direct in `<tbody>` (frate al `<tr>`)
  e HTML invalid — browserele pot rearanja DOM-ul imprevizibil, iar JS-ul cu
  `closest(".variant-row")` / `querySelector` devine instabil

**De ce `vf.object_name` pentru option_value_ids:**
- `fields_for` genereaza propriul index intern: `product[variants_attributes][0]`, `[1]`, etc.
- Daca scriem manual `product[variants_attributes][<%= variant.id %>]`, indexul nu corespunde
  cu ce asteapta `fields_for`
- La re-render dupa erori de validare, indecii se pot schimba → selectiile se pierd
- `vf.object_name` returneaza mereu prefixul corect, indiferent de index

**De ce `feed_with_options` (nu `has_option_values` pe orice varianta persistata):**
- Varianta veche (`has_option_values = variant.persisted? && option_values.any?`) facea optiunile readonly
  pentru TOATE variantele persistate care aveau optiuni — inclusiv cele create manual in admin
- Rezultat: admin-ul nu mai putea modifica optiunile pe o varianta manuala dupa primul save
- Varianta noua: `feed_with_options = feed && option_values.any?`
  - `feed = variant.external_ids.any?` (varianta vine din feed/import)
  - Doar variantele din feed au optiunile afisate readonly (text) — admin-ul nu ar trebui sa le editeze
    (feed-ul le suprascrie oricum la urmatorul sync)
  - Variantele manuale (create in admin) au mereu select-uri editabile — chiar daca sunt persistate
- `feed` e calculat inainte de `<tr>` si reutilizat si la badge-ul "Sursa" (nu se repeta query-ul)
- **Nota:** feed variants NU trimit `option_value_ids[]` (nu au select-uri) — Rails NU sterge
  asocierile existente doar pentru ca cheia lipseste din params. Daca in viitor se adauga logica
  de "reset to []" pe lipsa cheii, va trebui adaugate hidden fields cu option_value_ids[] pentru feed.
  Momentan nu e necesar.

**De ce `respond_to?` pe TOATE asociatiile din partial (guard defensiv complet):**
- `respond_to?(:external_ids)` si `respond_to?(:order_items)` — guard pe badge feed si lacat
- `respond_to?(:option_values)` — guard pe afisarea `options_text` (variante feed)
- `respond_to?(:option_value_ids)` — guard pe select-uri optiuni (variante noi/nepersistate)
- Fara guard pe `option_values`: daca asociatia nu exista → `undefined method 'option_values'` la fiecare rand
- Fara guard pe `option_value_ids`: `variant.option_value_ids` → `NoMethodError` → select-urile nu se mai randeaza
- `selected_ids = (...).map(&:to_s)` + `ov.id.to_s` — normalizare int/string:
  - La prima incarcare (din DB): `option_value_ids` = array de Integer (`[3, 7]`)
  - Dupa re-render cu erori de validare (din params): `option_value_ids` = array de String (`["3", "7"]`)
  - `[3].include?(3)` = true, dar `["3"].include?(3)` = **false** → selectia se pierde la re-render
  - `.map(&:to_s)` + `.to_s` normalizeaza ambele surse la string → comparatie corecta mereu
  - Fallback pe `[]` daca `option_value_ids` nu exista → select-uri fara pre-selectie (graceful degradation)
- Aliniat cu `reflect_on_association` din `preload_variants` (Pas 1C) — acelasi principiu, nivel diferit
- In practica, toate asociatiile exista (sunt in Variant model), dar e mai safe asa — portabilitate deplina

---

## PASUL 6: JS pentru butonul "+" si "x"

```javascript
document.addEventListener("turbo:load", () => {
  const section = document.getElementById("section-variants");
  if (!section) return;

  const addBtn = document.getElementById("add-variant-btn");
  const tbody = document.getElementById("variants-body");
  if (!addBtn || !tbody) return;

  let variantIndex = document.querySelectorAll(".variant-row").length;

  // Citeste option types si statuses din data attributes (sursa de adevar = Ruby)
  const statuses = (section.dataset.variantStatuses || "active,inactive").split(",").map(s => s.trim()).filter(Boolean);
  let optionTypes = [];
  try {
    optionTypes = JSON.parse(section.dataset.optionTypes || "[]");
  } catch(e) {}

  // Guard: nu atasa handler-ul "+" de mai multe ori la navigari Turbo repetate
  if (!section.dataset.addBound) {
    section.dataset.addBound = "1";
    addBtn.addEventListener("click", () => {
      // Cheie unica: timestamp + index — previne coliziuni la click rapid (Date.now() are rezolutie ms)
      const key = `${Date.now()}_${variantIndex}`;
      const row = buildVariantRow(key, statuses, optionTypes);
      tbody.insertAdjacentHTML("beforeend", row);
      variantIndex++;
    });
  }

  // Sterge variant — bind pe section (nu pe document) pt a evita duplicari la turbo:load
  if (!section.dataset.removeBound) {
    section.dataset.removeBound = "1";
    section.addEventListener("click", (e) => {
      const btn = e.target.closest(".remove-variant");
      if (btn) {
        const row = btn.closest(".variant-row");
        if (!row) return;
        const idField = row.querySelector("input[name$='[id]']");
        const hasId = idField && idField.value && idField.value.trim() !== "";
        const destroyInput = row.querySelector("input[name*='_destroy']");

        if (destroyInput && hasId) {
          // Varianta persistata (are id in DB) — marcheaza pt stergere, ascunde randul
          destroyInput.value = "1";
          row.style.display = "none";
        } else {
          // Varianta noua (nesalvata, fara id) — sterge randul din DOM
          row.remove();
        }
      }
    });
  }

  // Escape HTML pt a preveni injection in template-urile JS
  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function buildVariantRow(timestamp, statuses, optionTypes) {
    const prefix = `product[variants_attributes][${timestamp}]`;

    const statusOptions = statuses.map(s =>
      `<option value="${escapeHtml(s)}">${escapeHtml(s.charAt(0).toUpperCase() + s.slice(1))}</option>`
    ).join("");

    const optSelects = optionTypes.map(ot => {
      const opts = ot.values.map(ov =>
        `<option value="${ov.id}">${escapeHtml(ov.name)}</option>`
      ).join("");
      return `<select name="${prefix}[option_value_ids][]">
        <option value="">-- ${escapeHtml(ot.name)} --</option>${opts}</select>`;
    }).join(" ");

    return `<tr class="variant-row">
      <td><input type="text" name="${prefix}[sku]" placeholder="SKU" size="15"></td>
      <td><input type="number" name="${prefix}[price]" step="0.01" placeholder="0.00" size="8"></td>
      <td><input type="number" name="${prefix}[stock]" placeholder="0" size="5"></td>
      <td><input type="number" name="${prefix}[vat_rate]" step="0.01" placeholder="19" size="5"></td>
      <td><select name="${prefix}[status]">${statusOptions}</select></td>
      <td>${optSelects}</td>
      <td><span class="badge badge-new">nou</span></td>
      <td><button type="button" class="remove-btn remove-variant">x</button></td>
    </tr>`;
  }
});
```

**De ce guard `addBound` pe butonul "+":**
- Fara guard, `addBtn.addEventListener("click", ...)` se ataseaza la FIECARE `turbo:load`
- Dupa 3 navigari: un click pe "+" adauga 3 randuri in loc de 1
- Guard `data-add-bound` = handler-ul se ataseaza o singura data
- Acelasi pattern ca `removeBound` pentru handler-ul "x"

**De ce `section.addEventListener` si nu `document.addEventListener`:**
- `document.addEventListener("click", ...)` in interiorul `turbo:load` se executa la FIECARE
  navigare Turbo → dupa 5 navigari, click-ul de "x" se executa de 5 ori
- Rezultat: varianta pare ca se sterge, dar handler-ul inca ruleaza de mai multe ori
  (sau mai rau, _destroy se seteaza si deseteaza)
- `section.addEventListener` + guard `removeBound` asigura ca handler-ul se ataseaza O SINGURA DATA

**De ce `e.target.closest(".remove-variant")` (nu `e.target.classList.contains`):**
- `classList.contains` functioneaza DOAR daca `e.target` e chiar butonul cu clasa `.remove-variant`
- Daca butonul contine un child (ex: `<span>`, icon SVG), click-ul pe child are `e.target = span`
  → `span.classList.contains("remove-variant")` = false → click-ul nu face nimic
- `closest(".remove-variant")` cauta in sus de la target → gaseste butonul chiar daca click-ul e pe child
- Cu butonul actual (`<button>x</button>`, text simplu), comportamentul e identic
- Dar daca in viitor inlocuiesti "x" cu un icon/SVG, handler-ul continua sa functioneze

**De ce `if (!row) return` dupa `btn.closest(".variant-row")`:**
- `closest()` cauta in sus in DOM un element care matchuieste selectorul
- Daca butonul "x" e (prin eroare) in afara unui `.variant-row`, `closest()` returneaza `null`
- Fara guard: `null.querySelector(...)` → `TypeError: Cannot read properties of null`
  → handler-ul crapa, click-ul nu face nimic, fara mesaj de eroare vizibil pt user
- Cu guard: `return` iese din handler → niciun efect, dar JS-ul nu crapa
- Scenarii posibile: DOM manipulat de extensie browser, structura HTML modificata gresit, race condition la remove rapid

**De ce `hasId` (nu doar `destroyInput`) la remove:**
- Partial-ul randeaza `_destroy` hidden field si pentru variante nesalvate (server-rendered dupa submit invalid)
- Fara check pe id: varianta noua cu `_destroy` e doar ascunsa (nu eliminata din DOM)
  → se trimite la submit cu `_destroy=1` → `reject_if` o ignora oricum, dar UX-ul e inconsistent
  (user crede ca a sters-o, dar randul e doar hidden)
- Cu `hasId`: variante persistate (au `input[name$='[id]']` cu valoare) → `_destroy=1` + hide
- Variante noi (fara id, sau id gol) → `row.remove()` = eliminare reala din DOM
- Consistent cu testul: "x pe varianta noua → sterge randul din DOM"

**De ce `escapeHtml`:**
- Numele option types/values vin din DB (pot fi editate de admin sau importate din feed)
- Daca un nume contine `<script>` sau `"`, template string-ul JS devine injection vector
- `escapeHtml` neutralizeaza caracterele speciale → HTML-ul generat e safe
- Chiar daca admin-controlled, e o practica buna — previne surprize la import feed

**Nota consolidare JS:** Pas 3 (toggle) si Pas 6 (+/x buttons) au fiecare propriul `turbo:load` listener.
Daca se doreste consolidare, se pot muta intr-un singur fisier cu un singur `turbo:load` care apeleaza
doua functii init (`initToggle()` + `initVariantsTable()`). Nu e obligatoriu — ambele au guards proprii
(`changeBound`, `addBound`, `removeBound`) care previn dubla atasare, dar consolidarea reduce riscul
de drift si faciliteaza intretinerea.

---

## PASUL 7: CSS pentru tabel variante

**Fisier:** `app/assets/stylesheets/pages/_admin.css`

```css
.variants-table {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: 1rem;
}
.variants-table th, .variants-table td {
  padding: 8px;
  border-bottom: 1px solid #e5e7eb;
  text-align: left;
  font-size: 0.875rem;
}
.variants-table th {
  font-weight: 600;
  color: #6b7280;
  text-transform: uppercase;
  font-size: 0.75rem;
}
.badge-feed { background: #dbeafe; color: #1e40af; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; }
.badge-manual { background: #dcfce7; color: #166534; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; }
.badge-new { background: #fef3c7; color: #92400e; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; }
.form-hint.warning { color: #92400e; background: #fef3c7; padding: 8px 12px; border-radius: 4px; font-size: 0.85rem; margin-top: 8px; }
```

---

## PASUL 8: Adaptare Cart (cos)

**Fisier:** `app/controllers/cart_controller.rb` (metoda `add`)

Logica:
```ruby
def add
  product = Product.find(params[:product_id])
  variant_id = params[:variant_id]

  # Validare quantity la intrare (nu doar cleanup in load_cart)
  quantity = params[:quantity].to_i
  if quantity <= 0
    redirect_back fallback_location: carti_path, alert: "Cantitate invalida."
    return
  end

  # Daca produsul are variante active, variant_id e obligatoriu
  # variant_id.blank? PRIMUL → short-circuit: skip exists? query cand variant_id e prezent
  if variant_id.blank? && product.variants.active.exists?
    redirect_back fallback_location: carti_path, alert: "Selecteaza o varianta."
    return
  end

  # Variant SCOPED la product — previne combinatii imposibile (variant din alt produs)
  variant = variant_id.present? ? product.variants.active.find(variant_id) : nil

  # Varianta activa dar fara pret (feed bug, edit incomplet) → indisponibila
  if variant && variant.price.blank?
    redirect_back fallback_location: carti_path, alert: "Varianta selectata nu mai este disponibila."
    return
  end

  cart_key = variant ? "#{product.id}_v#{variant.id}" : product.id.to_s

  price_source = variant || product
  stock_source = variant || product

  # ... restul logicii de stoc/cantitate ramane la fel,
  # doar ca citeste din price_source / stock_source

  @cart[cart_key] ||= { "quantity" => 0 }
  @cart[cart_key]["quantity"] += quantity  # quantity deja validat > 0 mai sus
  @cart[cart_key]["variant_id"] = variant.id if variant
  save_cart
end
```

**De ce validare `quantity > 0` la add (nu doar in load_cart):**
- `params[:quantity]` poate fi manipulat (DevTools, curl, sesiune corupta)
- Fara validare: `quantity = 0` → linia apare in cos cu qty 0 → UX confuz (dispare la reload din load_cart cleanup)
- Fara validare: `quantity = -5` → decrement cos → cantitate negativa posibila
- Cu validare la intrare: refuz imediat + mesaj clar → UX mai bun
- `load_cart` cleanup ramane ca safety net (sesiuni corupte, race conditions), dar nu mai e singura aparare

**De ce `product.variants.active.find(variant_id)` si nu `Variant.find(variant_id)`:**
- Scope la product previne sa adaugi in cos o varianta care apartine ALTUI produs
- Daca sesiunea e corupta sau cineva trimite manual un variant_id gresit,
  ActiveRecord::RecordNotFound e mai bun decat un order_item inconsistent
- `.active` asigura ca nu se pot adauga variante inactive in cos

**Structura cart (sesiune):**
- Produs simplu: `{ "123" => { "quantity" => 2 } }` (ca acum)
- Produs cu varianta: `{ "123_v456" => { "quantity" => 1, "variant_id" => 456 } }`

---

## PASUL 9: Adaptare calcul totals

**Fisier:** `app/controllers/application_controller.rb`

In `load_cart` / calcul `@cart_products`:

```ruby
cart_dirty = false

# .to_a creeaza o copie a perechilor — sigur sa faci delete din @cart in timpul iteratiei
@cart.to_a.each do |key, data|
  key = key.to_s
  data = data.is_a?(Hash) ? data : {}
  product_id, raw_vid = key.split("_v", 2)
  # Sursa de adevar pt variant_id = cheia, cu fallback pe data (compat cart vechi)
  variant_id = raw_vid.presence || data["variant_id"].presence

  # Produs disparut → scoate din cos
  product = Product.find_by(id: product_id)
  if product.nil?
    @cart.delete(key)
    cart_dirty = true
    next
  end

  # Produsul are variante active dar linia nu are variant_id → invalida
  # (cart vechi, sesiune corupta, variante activate dupa ce linia era deja in cos)
  # variant_id.blank? PRIMUL → short-circuit: skip exists? query cand variant_id e prezent
  if variant_id.blank? && product.variants.active.exists?
    @cart.delete(key)
    cart_dirty = true
    next
  end

  # Scope la product + DOAR active — varianta inactiva = indisponibila
  variant = variant_id.present? ? product.variants.active.find_by(id: variant_id) : nil

  # Daca variant_id e prezent dar varianta nu mai exista / e inactiva → scoate din cos
  if variant_id.present? && variant.nil?
    @cart.delete(key)
    cart_dirty = true
    next
  end

  # Varianta activa dar fara pret (feed bug, edit incomplet) → indisponibila
  if variant && variant.price.blank?
    @cart.delete(key)
    cart_dirty = true
    next
  end

  # Quantity invalid (0, negativ, nil, non-numeric) → scoate din cos
  qty = data["quantity"].to_i
  if qty <= 0
    @cart.delete(key)
    cart_dirty = true
    next
  end

  price = variant ? variant.price : product.price
  # ... restul calculului foloseste `price` si `qty`
end

# Persista cleanup-ul in sesiune (altfel liniile sterse revin la requestul urmator)
save_cart if cart_dirty
```

**De ce `.to_a` inainte de iteratie:**
- `hash.each` + `hash.delete(key)` in acelasi loop poate produce comportament imprevizibil in Ruby
- `.to_a` creeaza un array de perechi `[key, data]` = copie independenta
- Iterezi copia, stergi din hash-ul original → safe, deterministic

**De ce `Product.find_by(id:)` (nu `Product.find`):**
- Produsul poate fi sters/arhivat din DB dupa ce a fost adaugat in cos
- `Product.find(id)` ridica `ActiveRecord::RecordNotFound` → 500 la fiecare page load cu cos
- `find_by(id:)` returneaza `nil` → cleanup graceful (scoate din cos, continua)

**De ce `.active` pe variant lookup:**
- O varianta poate deveni `inactive` dupa ce a fost adaugata in cos (admin/feed o dezactiveaza)
- Fara `.active`: varianta inactiva ramane in cos → user plateste pt ceva indisponibil
- Cu `.active`: varianta inactiva = nil → cleanup din cos (consistent cu "varianta disparuta")
- Aliniat cu cart_controller#add care deja foloseste `.active` la adaugare

**De ce `save_cart if cart_dirty`:**
- `@cart.delete(key)` modifica hash-ul in memorie, dar NU scrie inapoi in `session[:cart]`
- Fara `save_cart`: la urmatorul request, `load_cart` citeste din sesiune → liniile sterse reapar
- `cart_dirty` flag previne scrieri inutile cand nu s-a sters nimic (majority of requests)
- Daca `save_cart` nu exista ca metoda separata, inlocuieste cu `session[:cart] = @cart`

**De ce `key = key.to_s` inainte de `split`:**
- Cheile din cart sunt de regula string-uri (`"123"`, `"123_v456"`)
- Dar daca exista cart-uri vechi (inainte de migrare) sau sesiunea e alterata (serializare JSON/Marshal),
  cheia poate fi integer (`123`) sau symbol (`:123`)
- `123.split("_v", 2)` → `NoMethodError: undefined method 'split' for Integer` → 500 la fiecare page load
- `.to_s` pe string e no-op (zero overhead), pe non-string previne crash-ul
- Aplicat consistent in `load_cart` (Pas 9) si `orders#create` (Pas 10)

**De ce `data = data.is_a?(Hash) ? data : {}`:**
- `data` ar trebui sa fie mereu un Hash (`{"quantity" => 2, "variant_id" => 456}`)
- Dar sesiunea poate fi corupta (serializare gresita, manipulare manuala, migrare format):
  `session[:cart] = { "123" => "old_format" }` → `data` e String, nu Hash
- `data["variant_id"]` pe String → returneaza caractere (Ruby <3) sau `nil` (Ruby 3+) — comportament imprevizibil
- `data["quantity"].to_i` pe non-Hash → crash sau valoare gresita → order_item cu quantity 0
- Guard-ul normalizeaza: non-Hash → `{}` → `data["variant_id"]` = nil, `data["quantity"].to_i` = 0
  → varianta nil → daca produsul NU are variante active: ok (simplu); daca ARE: linia invalidata (guard urmator). Quantity 0 → cleanup la pasul qty <= 0
- Aplicat consistent in `load_cart` (Pas 9) si `orders#create` (Pas 10)

**De ce `product_id, raw_vid = key.split("_v", 2)` + `.presence`:**
- Cart-ul are doua surse: cheia (`"123_v456"`) si payload-ul (`data["variant_id"] = 456`)
- Daca sesiunea e corupta/editata si cele doua diverge, pretul se calculeaza pe varianta gresita
- Sursa de adevar = cheia (e imuabila dupa creare, identifica unic linia din cos)
- Fallback pe `data["variant_id"].presence` — compatibilitate cu cart-uri vechi care nu au `_v` in cheie
- `split("_v", 2)` — limita 2 previne probleme daca product_id contine `_v` (improbabil, dar defensiv)
- `.presence` normalizeaza: `""` → `nil`, `nil` → `nil`, `"456"` → `"456"`
  → `variant_id.present?` e consistent (string gol nu mai face query inutil)

**De ce guard `variant_id.blank? && product.variants.active.exists?`:**
- Produsul a fost adaugat in cos ca produs simplu (fara variant_id)
- Ulterior, se activeaza variante pe produs (admin adauga variante, feed sync, etc.)
- Fara guard: `variant = nil` (variant_id e blank) → fallback pe `product.price` → pret GRESIT
  (produsul "variant-driven" nu mai ar trebui sa se vanda ca simplu)
- Cu guard: linia invalida se curata din cos / checkout-ul e refuzat cu mesaj clar
- **Cazuri reale:** cart vechi (inainte de activare variante), sesiune corupta, doua tab-uri,
  manipulare manuala a sesiunii
- Pe produse fara variante active: `exists?` = false → guard nu se activeaza → zero impact
- **Ordinea conteaza:** `variant_id.blank?` PRIMUL → Ruby face short-circuit:
  - Daca `variant_id` e prezent (cazul normal pt produse cu variante), `blank?` = false → `exists?` NU se mai executa
  - Economiseste 1 query SQL per linie de cart care are deja variant_id
  - Pe un cos cu 10 linii cu variant_id: 10 query-uri eliminate
- **De ce `.exists?` (nu `.any?`) in cart/checkout:**
  - `.exists?` genereaza `SELECT 1 ... LIMIT 1` — cel mai eficient check posibil
  - `.any?` in Rails cheama intern `exists?` pe relatie unloaded, dar semantica e mai putin clara
  - Standardizare: `cart#add`, `load_cart`, `orders#create` — toate folosesc `.exists?`
  - In view (toggle default) se pastreaza `.any?` — asocierea poate fi loaded deja, `.any?` e mai natural in ERB

**De ce cleanup cand variant_id e prezent dar varianta nu se gaseste:**
- Varianta poate fi stearsa/inactivata/ID-ul invalid in sesiune
- Fara cleanup: `variant.nil?` → fallback pe `product.price` → pret GRESIT
  (pretul produsului poate fi diferit de pretul variantei)
- Cu cleanup: linia se scoate din cos, user-ul vede cosul actualizat
- Nu afecteaza produsele fara variante (variant_id e nil → nu se intra in if)

**De ce `variant.price.blank?` guard (varianta activa fara pret):**
- O varianta poate fi `active` dar cu `price = nil` (feed bug, import incomplet, edit partial)
- Fara guard: `price = variant.price` → `nil` → `nil * qty` → `TypeError` / `NoMethodError` → crash 500
- Sau mai subtil: `total_price: nil * 2` pe order_item → crash sau factura cu pret 0
- Guard-ul trateaza "varianta fara pret" identic cu "varianta disparuta/inactiva":
  - In `cart#add`: refuza adaugare cu mesaj
  - In `load_cart`: scoate linia din cos (cleanup)
  - In `orders#create`: refuza checkout cu mesaj
- Pe date valide (varianta cu pret setat): `price.blank?` = false → zero impact
- Aliniat cu G10 (cleanup variante invalide) si cu principiul "nu fallback pe pret gresit"

**De ce `qty <= 0` guard (quantity invalid):**
- `data["quantity"]` poate fi `nil`, `""`, `"0"`, `"-2"` sau absent (sesiune corupta, data normalizat la `{}`)
- `.to_i` normalizeaza: `nil` → 0, `""` → 0, `"0"` → 0, `"-2"` → -2
- Fara guard: linia ramane in cos cu qty 0 → `price * 0` = total 0 → comanda cu subtotal gresit
  sau qty negativ → total negativ → discount neintetiontionat pe factura
- In `load_cart`: qty <= 0 → scoate linia din cos (cleanup, ca la varianta disparuta)
- In `orders#create`: qty <= 0 → refuza checkout cu mesaj (nu crea comanda partiala)
  - Refuz e mai safe decat `next` (skip) — cu skip user-ul poate plati pt 2 produse dar primi 3
  - Mesaj explicit ajuta user-ul sa inteleaga problema (reload cos → qty invalid dispare din load_cart)
- Pe date valide (qty >= 1): guard nu se activeaza → zero impact
- Scenarii reale: sesiune corupta (data non-Hash normalizat la {}), JS bug care seteaza qty=0, race condition la remove

**Transport:** nu se schimba — verifica categoria "fizic" pe Product (nu pe Variant).

---

## PASUL 10: Adaptare creare OrderItems

**Fisier:** `app/controllers/orders_controller.rb` (metoda `create`)

```ruby
@cart.each do |key, data|
  key = key.to_s
  data = data.is_a?(Hash) ? data : {}
  product_id, raw_vid = key.split("_v", 2)
  # Sursa de adevar pt variant_id = cheia (consistent cu load_cart)
  variant_id = raw_vid.presence || data["variant_id"].presence

  product = Product.find_by(id: product_id)

  # Produs disparut → refuza checkout
  if product.nil?
    flash.now[:alert] = "Un produs din cos nu mai este disponibil."
    render :new, status: :unprocessable_entity and return
  end

  # Produsul are variante active dar linia nu are variant_id → refuza checkout
  # variant_id.blank? PRIMUL → short-circuit: skip exists? query cand variant_id e prezent
  if variant_id.blank? && product.variants.active.exists?
    flash.now[:alert] = "Selecteaza o varianta pentru produsul #{product.name}."
    render :new, status: :unprocessable_entity and return
  end

  # Scope la product + DOAR active (consistent cu load_cart)
  variant = variant_id.present? ? product.variants.active.find_by(id: variant_id) : nil

  # Daca variant_id e prezent dar varianta nu mai exista / e inactiva → refuza checkout
  if variant_id.present? && variant.nil?
    flash.now[:alert] = "Varianta selectata nu mai este disponibila."
    render :new, status: :unprocessable_entity and return
  end

  # Varianta activa dar fara pret (feed bug, edit incomplet) → refuza checkout
  if variant && variant.price.blank?
    flash.now[:alert] = "Varianta selectata nu mai este disponibila."
    render :new, status: :unprocessable_entity and return
  end

  price = variant ? variant.price : product.price
  vat = variant ? (variant.vat_rate || product.vat || 0) : (product.vat || 0)
  qty = data["quantity"].to_i

  # Quantity invalid → refuza checkout (nu crea comanda partiala)
  if qty <= 0
    flash.now[:alert] = "Cos invalid (cantitate lipsa sau zero)."
    render :new, status: :unprocessable_entity and return
  end

  @order.order_items.build(
    product: product,
    product_name: product.name,
    variant_id: variant&.id,
    variant_sku: variant&.sku,
    variant_options_text: variant&.options_text,
    vat_rate_snapshot: vat,
    quantity: qty,
    price: price,
    vat: vat,
    total_price: price * qty
  )
end
```

**De ce `data["quantity"].to_i`:**
- Sesiunile Rails stocheaza valori ca string-uri (JSON serialization)
- `price * "2"` pe BigDecimal/Float → `TypeError: String can't be coerced into BigDecimal`
- `.to_i` e idempotent pe integer si corect pe string numeric ("2" → 2)
- Folosit si in `quantity:` si in `total_price:` pt consistenta

**De ce refuz la checkout (nu fallback pe product.price):**
- In `load_cart` (Pas 9) curatam cosul — linia dispare
- Dar daca user-ul are 2 tab-uri deschise si da checkout inainte de refresh,
  variant_id e inca in sesiune dar varianta nu mai exista
- Fara guard: `variant.nil?` → pretul vine de pe product → factura GRESITA
- Cu guard: checkout refuza cu mesaj clar → user-ul reincarca cosul si vede starea corecta
- Nu afecteaza produsele fara variante (variant_id e nil → nu se intra in if)

---

## PASUL 11: Adaptare pagina produs (shop)

**Fisier:** `app/views/carti/show.html.erb`

Daca produsul are variante active, afiseaza:
- Selectoare de optiuni (dropdown-uri sau butoane)
- Pretul se actualizeaza dinamic la selectie
- Butonul "Adauga in cos" trimite si `variant_id`
- Daca nu are variante — afiseaza ca acum

---

## PASUL 12: Adaptare view cart

**Fisier:** `app/views/cart/index.html.erb` (sau equivalent)

Daca item-ul are `variant_id`:
- Afiseaza numele produsului + optiunile variantei (ex: "Index Ayurvedic — Format A4, Coperta moale")
- Pretul vine din varianta

Daca nu are:
- Afiseaza ca acum

---

## GUARDRAILS

### G1: Cart — produs cu variante fara variant_id selectat
- Server-side: `add` refuza si returneaza eroare
- Client-side: butonul "Adauga in cos" disabled pana se selecteaza varianta
- **Produsele fara variante functioneaza exact ca acum**

### G2: Nested form — variante duplicate
- DB constraint: `idx_unique_active_options_per_product` (exista deja)
- Model: `compute_options_digest` + unicitate pe digest (exista deja)
- UI: daca save-ul esueaza, afiseaza eroarea pe formularul de variante

### G3: Stergere variante cu comenzi
- `dependent: :nullify` pe `has_many :order_items` in Variant (exista deja)
- In UI: varianta cu order_items afiseaza lacat, nu buton "x"
- Alternativ: in loc de stergere, `status: :inactive` (soft disable)

### G4: Feed sync vs editari manuale
- Coloana "Sursa" in tabelul de variante: "feed" vs "manual" vs "nou"
- Determinare: `variant.external_ids.any?` = feed, altfel = manual
- Tooltip pe badge "feed": "Sincronizat din feed. Modificarile pot fi suprascrise."
- **NU se schimba logica de sync** — doar informational in admin

### G5: Product.price/stock vs Variant.price/stock
- Cand toggle "Are variante" e ON: campurile price/stock de pe Product sunt readonly + ascunse
- `readonly` pe input text/number/textarea, `pointerEvents: none` + `tabIndex: -1` pe select, checkbox si radio
  (unlock: restaureaza tabindex original din `data-orig-tabindex`, sau `removeAttribute` daca nu exista initial)
- Checkbox/radio (ex: `track_inventory`) sunt blocate cu pointerEvents (readonly e ignorat de browsere pe aceste tipuri)
- **Lock guard suplimentar:** `bindLockGuards(section)` intercepteaza click/keydown in capture phase
  → previne bypass prin click pe `<label>` asociat cu checkbox/radio (label nu trece prin pointerEvents)
- In runtime (cart/checkout): `variant ? variant.price : product.price`
- **Nicio ambiguitate** — sursa e clara din prezenta/absenta variant_id

### G6: Variant scoped la Product in cart/checkout
- Toate lookup-urile de variant folosesc `product.variants.find_by(id:)`, nu `Variant.find(id)`
- Previne combinatii imposibile (variant din alt produs)
- `variant_id` derivat din cart key (sursa de adevar), nu din `data["variant_id"]` (poate diverge la coruptie sesiune)
- Daca variant_id e invalid → nil → cleanup cos / refuz checkout (nu fallback pe pret gresit)

### G7: JS event handler duplicare cu Turbo
- Click handler pentru "x" (remove variant) se leaga de `#section-variants`, nu de `document`
- Guard `data-remove-bound` previne atasarea multipla la navigari Turbo repetate
- Guard `data-add-bound` previne duplicarea handler-ului "+" (altfel adauga N randuri dupa N navigari)
- Guard `data-change-bound` pe toggle previne dubla atasare la back/forward din Turbo cache
  (DOM-ul e reutilizat, listenerul vechi ramane, `turbo:load` mai ataseaza inca unul)
- Fara guards: dupa 5 navigari, un click pe "x"/"+"/toggle ar executa handler-ul de 5 ori

### G8: HTML injection in template-uri JS
- `escapeHtml()` pe toate valorile text din `buildVariantRow()`
- `ERB::Util.html_escape` (nu `json_escape`) pe `data-option-types` in ERB — garanteaza escapare `"` in atribut HTML
- Previne XSS daca numele optiunilor contin caractere speciale (`<`, `"`, `&`)

### G9: Portabilitate _form.html.erb (fallback complet)
- `respond_to?(:preload_variants)` in view — fallback pe `.to_a` daca helper-ul nu exista
- `(@option_types || [])` — fallback pe array gol daca `before_action :load_option_types` lipseste
- `respond_to?(:order_items)` si `respond_to?(:external_ids)` in partial — guard defensiv pe asociatii (badge + lacat)
- `respond_to?(:option_values)` in partial — guard pe afisarea options_text (variante feed)
- `respond_to?(:option_value_ids)` in partial — guard pe select-uri optiuni, fallback pe `[]` + `.map(&:to_s)` (normalizare int/string)
- `feed_with_options` in partial — optiunile sunt readonly (text) DOAR pt variante din feed (nu pt manuale)
- Permite reutilizarea `_form` din alt controller fara crash
- In `ProductsController` (cazul normal): toate variabilele exista → output identic
- **Nota N+1:** fallback pe `.to_a` (fara preload) poate genera N+1 pe `variant.external_ids.any?`,
  `variant.order_items.any?`, `variant.option_values.any?`. Acceptabil (caz rar — alt controller).
  Daca devine relevant, solutia e: muta `preload_variants` in `ApplicationController` sau un concern comun

### G10: Varianta/produs disparut sau invalid din sesiune
- In `load_cart` (Pas 9):
  - Produs disparut → scoate din cos + `save_cart` (nu 500)
  - Varianta disparuta/inactiva → scoate din cos + `save_cart`
  - Varianta activa fara pret (feed bug) → scoate din cos + `save_cart`
  - `.to_a` pe hash inainte de iteratie → safe delete in loop
  - `.active` pe variant lookup → varianta inactiva = indisponibila (consistent cu cart#add)
  - `key.to_s` previne crash daca cheia e integer/symbol (cart-uri vechi, serializare alterata)
  - `data.is_a?(Hash) ? data : {}` normalizeaza payload-ul — sesiune corupta cu `data` non-Hash nu produce crash
  - `qty <= 0` → scoate din cos (quantity invalid: 0, negativ, nil, non-numeric din sesiune corupta)
  - Produs cu variante active dar variant_id blank → scoate din cos (cart vechi, variante activate ulterior)
- In `cart#add` (Pas 8):
  - Varianta activa fara pret → refuza adaugare cu mesaj
- In `orders#create` (Pas 10):
  - Produs disparut → refuza checkout cu mesaj
  - Varianta disparuta/inactiva → refuza checkout cu mesaj
  - Varianta activa fara pret → refuza checkout cu mesaj
  - `qty <= 0` → refuza checkout cu mesaj (nu crea comanda partiala)
  - Produs cu variante active dar variant_id blank → refuza checkout cu mesaj "Selecteaza o varianta"
  - `key.to_s` consistent cu load_cart
  - `data.is_a?(Hash)` consistent cu load_cart
- Previne facturare la pret gresit (fallback pe product.price cand varianta nu mai exista)
- Previne crash pe `nil * qty` cand varianta exista dar nu are pret
- Previne linii "fantoma" cu qty 0 sau total negativ (qty <= 0 cleanup)
- `save_cart if cart_dirty` persista cleanup-ul in sesiune (altfel liniile sterse revin la requestul urmator)

### G11: Validare conditionala Product.price
- `validates :price, presence: true, unless: :has_active_variants?`
- Produse fara variante (carti): `price` obligatoriu (ca inainte)
- Produse cu variante **active**: `price` pe Product nu e obligatoriu (pretul e pe variante)
- Produse cu DOAR variante **inactive**: `price` obligatoriu (in runtime se comporta ca produs simplu)
- `marked_for_destruction?` previne bypass: user sterge toate variantele si trimite fara pret → `price` redevine obligatoriu
- **Toggle default aliniat:** `variants.active.any?` (nu `variants.any?`) — toggle ON doar daca exista variante active
  - Doar variante inactive → toggle OFF → price vizibil → user il completeaza → save OK
  - Evita mismatch-ul: toggle ON (ascunde price) dar validarea cere price (nu sunt active variants)

---

## MIGRARE

Nu e necesara nicio migrare:
- `has_variants` se determina din `product.variants.active.exists?` (index pe `product_id` exista deja)
- `variant_id` pe `order_items` exista deja
- `variant_sku`, `variant_options_text`, `vat_rate_snapshot` pe `order_items` exista deja
- Toate tabelele de variante/optiuni exista deja

---

## ORDINE DE IMPLEMENTARE

1. **Pas 1** — Model (`accepts_nested_attributes_for`) + controller (`before_action`, `helper_method`, `preload_variants`, params) — zero impact pe existent
2. **Pas 2-3** — Toggle UI + JS — zero impact (sectiuni noi, ascunse default)
3. **Pas 4-5-6** — Sectiunea variante + partial + JS "+" — zero impact (apare doar cu toggle ON)
4. **Pas 7** — CSS — zero impact
5. **Pas 8-9-10** — Cart + totals + order_items — **aici e adaptarea reala**
   - Backward compatible: cart fara variant_id functioneaza ca inainte
   - Cart cu variant_id: feature noua
   - Varianta disparuta: cleanup cos / refuz checkout
6. **Pas 11-12** — Views shop + cart — afisare conditionala

**Teste:** dupa fiecare pas, ruleaza `bundle exec rspec` — nu trebuie sa sparga nimic.

---

## CHECKLIST PRE-IMPLEMENTARE (sa nu scape nimic)

- [ ] `Product::BOOL_CASTER` definit in interiorul `class Product < ApplicationRecord` (nu la top-level)
- [ ] `_form.html.erb`: `id="section-prices"` si `id="section-stock"` pe sectiunile existente (altfel JS-ul se opreste la guard)
- [ ] `ProductsController`: `before_action :load_option_types, only: [:new, :edit, :create, :update]`
- [ ] `ProductsController`: `helper_method :preload_variants`
- [ ] `ProductsController`: `variants_attributes` in strong params (cu `option_value_ids: []`, `_destroy`, etc.)
- [ ] Partial randat cu path absolut: `render "products/variant_fields"`
- [ ] Cart/checkout: toate lookup-urile variant scoped la product (`product.variants.active...`)
- [ ] Cart/checkout: "variant-driven fara variant_id" = refuz/cleanup (`variant_id.blank? && product.variants.active.exists?`)
- [ ] Cart#add: `quantity = params[:quantity].to_i; if quantity <= 0 → refuz`
- [ ] Bunny upload: **neatins** (nicio modificare)

### Unde pui JS-ul (alegi una, dupa setup)

| Setup | Fisier | Wiring |
|-------|--------|--------|
| Asset pipeline (Sprockets) | `app/assets/javascripts/admin_products.js` | Include in manifestul admin |
| Importmap | `app/javascript/admin/products.js` | Pin + import in layout admin |
| jsbundling (esbuild/webpack) | `app/javascript/admin/products.js` | Import in pack/entrypoint admin |

Continutul JS ramane identic — doar wiring-ul difera.

---

## TESTE RECOMANDATE

### Formular admin:
- [ ] `/products/new` si `/products/:id/edit` deschide fara erori
- [ ] Log-ul nu are "Unpermitted parameter: has_variants"
- [ ] Toggle ON → sectiunile pret/stoc ascunse si readonly, sectiunea variante vizibila
- [ ] Toggle OFF → pret/stoc vizibile si editabile, variante ascunse
- [ ] Navigare Turbo intre /products si /products/:id/edit → toggle/+ functioneaza de fiecare data
- [ ] "+" adauga un singur rand nou (nu 2/3) cu select-uri corecte (status din enum, option types din DB)
- [ ] "x" pe varianta noua → sterge randul din DOM
- [ ] "x" pe varianta existenta fara comenzi → marcheaza _destroy, ascunde randul (o singura data)
- [ ] Lacat pe varianta cu comenzi → nu se poate sterge
- [ ] Editare SKU la varianta existenta → se modifica aceeasi inregistrare, nu apare duplicat
- [ ] Creare varianta noua complet goala → nu se creaza (reject_if)
- [ ] Selectie optiuni → se pastreaza dupa re-render cu erori de validare
- [ ] Variante nesalvate raman vizibile in tabel dupa re-render cu erori
- [ ] Badge "feed" pe variante din sync, "manual" pe cele create in admin, "nou" pe cele nesalvate
- [ ] POST /products invalid → re-render new fara erori (@option_types disponibil)
- [ ] PATCH /products/:id invalid → re-render edit fara erori (@option_types disponibil)
- [ ] Toggle ON, completare gresita, submit → re-render cu toggle ON (params persistence)
- [ ] Navigare Turbo /products → edit → back → edit → "+" → apare un singur rand
- [ ] Navigare Turbo /products → edit → back → edit → "x" pe variant → se ascunde o singura data
- [ ] Option type cu nume special (A"4, <b>Bold</b>) → JS nu crapa, UI nu injecteaza HTML
- [ ] Toggle ON → select-urile din sectiunile ascunse nu se pot interactiona (pointerEvents: none)
- [ ] Toggle ON → click pe label asociat cu checkbox (ex: track_inventory) → checkbox NU se schimba (lock guard)
- [ ] Toggle ON → Tab+Space pe checkbox din sectiune locked → nu se bifeaza/debifeaza (keydown capture)
- [ ] Produs cu variante active + linie in cart fara variant_id (cart vechi) → load_cart curata linia
- [ ] Tab order in form inainte/dupa toggle → ordinea naturala ramane (tabindex original restaurat)
- [ ] Select cu tabindex="2" → toggle ON → toggle OFF → tabindex ramane "2" (nu pierdut)
- [ ] Click rapid pe "+" (5 click-uri sub 1ms) → 5 randuri distincte (chei unice, nu duplicate)
- [ ] `vf.hidden_field :id` randat in `<td>`, nu direct in `<tbody>` (HTML valid, verificat cu W3C validator)
- [ ] `_form` randat din alt controller (fara `preload_variants`) → nu crapa, variante afisate corect
- [ ] /products → edit → back → edit (de cateva ori) → toggle ON/OFF → sectiunile se comuta o singura data (fara flicker, fara executii multiple in console)
- [ ] Toggle OFF → submit invalid → re-render cu toggle OFF (nu se re-bifeaza fortat)
- [ ] Produs cu variante existente: debifezi toggle, submit invalid → ramane debifat
- [ ] OptionType cu `"` in nume → data-option-types nu rupe HTML, JSON.parse reuseste
- [ ] "x" pe varianta noua (server-rendered dupa submit invalid) → row.remove() (nu doar ascunsa)
- [ ] "x" pe varianta persistata → _destroy=1, row hidden (nu removed din DOM)
- [ ] Create produs cu toggle ON + variante completate + product.price gol → save reuseste
- [ ] Create produs fara variante + product.price gol → validare pica (price obligatoriu)
- [ ] Edit produs: sterge toate variantele (_destroy) + product.price gol → validare pica
- [ ] Produs cu DOAR variante inactive + product.price gol → validare pica (has_active_variants? = false)
- [ ] Edit produs cu variante active, toggle OFF → apare warning "Produsul are variante active..."
- [ ] Click pe label "Acest produs are variante" → bifeaza/debifeaza checkbox-ul (nu hidden field)
- [ ] Selectezi optiuni pe varianta noua, lasi SKU/price goale, alt camp invalid pe produs → re-render pastreaza selectiile
- [ ] Varianta complet goala (nici optiuni, nici SKU, nimic) → nu se creaza (reject_if)
- [ ] Submit formular cu variante existente → reject_if proc nu ridica LocalJumpError (if/else, nu next)
- [ ] Submit formular cu varianta existenta + varianta noua goala → exista se updateaza, noua se ignora (fara crash)
- [ ] Partial randat fara asociatia option_values pe Variant → nu crapa (respond_to? guard, graceful degradation)
- [ ] Partial randat fara asociatia option_value_ids pe Variant → select-uri fara pre-selectie (fallback pe [])
- [ ] JS: click pe "x" cand butonul nu e in .variant-row (edge case DOM) → niciun efect, fara TypeError
- [ ] Toggle ON → checkbox-urile din sectiunea stoc (track_inventory) nu se pot interactiona (pointerEvents: none)
- [ ] Toggle OFF → tabindex original al checkbox-urilor revine (daca exista)
- [ ] Submit cu toggle ON → valorile checkbox-urilor se trimit (nemodificate, nu disabled)
- [ ] Butonul "x" cu `<span>` interior → click pe span inca sterge (closest, nu classList.contains)
- [ ] `product.variants_attributes = [{id: 1, _destroy: true}]` (chei simbol) → nu e respins de reject_if
- [ ] Submit normal din formular (chei string) → identic ca inainte (fallback nu schimba logica)
- [ ] .form-section cu display:flex → toggle ON/OFF pastreaza flex (nu forteaza block)
- [ ] Checkout cu quantity ca string in sesiune → nu crapa (to_i), totals corecte
- [ ] Cart key "123_v" (variant_id gol) → `.presence` returneaza nil → daca produsul NU are variante active: tratat ca simplu (ok); daca ARE variante active: linia e invalidata (cleanup/refuz)
- [ ] Selectie optiune pe varianta noua → submit invalid → re-render → optiunea ramane selectata (int/string normalizare cu .map(&:to_s))
- [ ] Selectie optiune pe varianta persistata (din DB, int IDs) → submit invalid → re-render (string IDs din params) → optiunea ramane selectata
- [ ] Varianta manuala persistata cu optiuni → select-uri editabile (nu text readonly)
- [ ] Varianta feed persistata cu optiuni → text readonly (options_text), fara select-uri
- [ ] Varianta feed fara optiuni → select-uri editabile (graceful degradation)
- [ ] `data-variant-statuses="active, inactive"` (cu spatii) → JS parse corecta (trim, fara "" entries)
- [ ] `BOOL_CASTER` constant → nu produce warning "already initialized" in dev (const_defined? guard)
- [ ] `feed` calculat o singura data per rand, reutilizat la optiuni si la badge (fara query dublu)
- [ ] `BOOL_CASTER` definit ca `Product::BOOL_CASTER` (nu `Object::BOOL_CASTER`) — scoped in clasa
- [ ] `variants_attributes = [{ sku: "", price: "", stock: "", vat_rate: "", option_value_ids: [""] }]` → reject_if respinge (varianta goala)
- [ ] `variants_attributes = [{ option_value_ids: ["3"] }]` (doar optiuni) → NU e respinsa (se pastreaza la re-render)

### Cart/Checkout:
- [ ] Add-to-cart produs simplu (fara variante) → functioneaza ca inainte
- [ ] Add-to-cart produs cu variante fara variant_id → respins cu mesaj
- [ ] **Checkout produs variant-driven fara variant_id in sesiune → refuzat cu "Selecteaza o varianta" (MUST-HAVE)**
- [ ] **load_cart produs variant-driven fara variant_id → linia curatata din cos (MUST-HAVE)**
- [ ] Add-to-cart cu quantity=0 → refuzat cu "Cantitate invalida" (nu se adauga in cos)
- [ ] Add-to-cart cu quantity=-1 → refuzat cu "Cantitate invalida"
- [ ] Add-to-cart cu quantity=nil (params lipsa) → to_i=0 → refuzat
- [ ] Add-to-cart cu variant_id valid → OK, cart_key = "pid_vVid"
- [ ] Add-to-cart cu variant_id din ALT produs → RecordNotFound (scoped)
- [ ] Add-to-cart cu variant_id invalid → RecordNotFound (nu order_item corupt)
- [ ] Varianta stearsa/inactivata cu cart vechi → linia dispare din cos la load_cart
- [ ] Checkout cu variant_id invalid in sesiune → refuzat cu mesaj (nu factura la pret gresit)
- [ ] Checkout cu mix de produse simple si cu variante → order_items corecte
- [ ] Order item cu varianta: variant_sku, variant_options_text, vat_rate_snapshot populate
- [ ] Cart corect (key "1_v2", data variant_id=2) → pret din varianta 2
- [ ] Cart corupt (key "1_v2", data variant_id=3) → sistemul foloseste varianta 2 (din key)
- [ ] Varianta stearsa → load_cart curata linia → al doilea request nu mai arata linia (persistat in sesiune)
- [ ] Varianta inactiva in cart → load_cart curata linia (tratata ca indisponibila)
- [ ] Produs sters din DB cu cart vechi → load_cart curata linia (fara 500 / RecordNotFound)
- [ ] Checkout cu produs sters din DB → refuzat cu mesaj (nu crash)
- [ ] Varianta activa cu price=nil in cos → linia dispare la load_cart (cleanup)
- [ ] Add-to-cart varianta activa cu price=nil → refuzat cu mesaj (nu crash)
- [ ] Checkout cu varianta price=nil → refuzat cu mesaj, fara crash (nu factura cu pret nil)
- [ ] session[:cart] = { 123 => {"quantity"=>"1"} } (cheie integer) → load_cart nu produce 500 (key.to_s)
- [ ] session[:cart] cu cheie symbol → load_cart nu produce 500
- [ ] session[:cart] = { "123" => "not_a_hash" } (data non-Hash) → load_cart nu produce 500 (data normalizat la {})
- [ ] session[:cart] = { "123" => nil } → load_cart nu produce 500
- [ ] Checkout cu data non-Hash in sesiune → nu crapa (data normalizat la {})
- [ ] session[:cart] = { "123" => {"quantity" => "0"} } → load_cart curata linia (qty <= 0)
- [ ] session[:cart] = { "123" => {"quantity" => "-2"} } → load_cart curata linia
- [ ] session[:cart] = { "123" => {"quantity" => nil} } → load_cart curata linia (nil.to_i = 0)
- [ ] session[:cart] = { "123" => {} } → load_cart curata linia (qty absent → 0)
- [ ] orders#create cu qty=0 in sesiune → refuz checkout cu mesaj "Cos invalid", nu se creeaza Order
- [ ] orders#create cu data=nil → refuz checkout (data normalizat, qty=0)
- [ ] Produs fara variante active (are doar inactive) + variant_id blank → se adauga ca produs simplu
- [ ] Cart mix: 1 linie qty=0, 1 linie qty=2 → load_cart curata prima, pastreaza a doua
- [ ] Produs cu DOAR variante inactive → toggle default OFF, campul price vizibil
- [ ] Produs cu cel putin o varianta active → toggle default ON, campul price ascuns
- [ ] Varianta "junk" (doar optiuni, fara price/sku) → reject_if o lasa, dar Variant validarile (price presence) o opresc → eroare pe form, selectiile se pastreaza
- [ ] render "products/variant_fields" din alt controller (ex: admin) → partial se gaseste corect
- [ ] Transport gratuit (price=0, qty=1) → order_item valid, afisat ca "Gratuit" (nu prins de qty <= 0)
- [ ] Transport 20 lei → order_item valid, total_price=20
- [ ] Guard-ul qty <= 0 nu afecteaza linia de Transport (e construita separat, dupa loop-ul @cart)

---

## EXEMPLE RSPEC (gata de copiat)

### A) Model specs — Product validari conditionale + reject_if

```ruby
# spec/models/product_spec.rb
RSpec.describe Product, type: :model do
  describe "conditional price validation" do
    let(:product) { create(:product, price: nil) }

    it "requires price when it has only inactive variants" do
      create(:variant, product:, status: :inactive, price: 10)
      expect(product).not_to be_valid
      expect(product.errors[:price]).to be_present
    end

    it "requires price if all active variants are marked_for_destruction (loaded association)" do
      v = create(:variant, product:, status: :active, price: 10)
      product.reload
      product.variants.load
      product.assign_attributes(variants_attributes: [{ id: v.id, _destroy: "1" }])

      expect(product.variants.loaded?).to be(true)
      expect(product).not_to be_valid
      expect(product.errors[:price]).to be_present
    end

    it "does NOT require price if it has at least one active variant not destroyed" do
      create(:variant, product:, status: :active, price: 10)
      expect(product).to be_valid
    end
  end

  describe "reject_if proc" do
    let(:product) { create(:product, price: 50) }

    it "rejects completely blank variant (no sku, price, stock, vat_rate, options)" do
      product.assign_attributes(variants_attributes: [
        { sku: "", price: "", stock: "", vat_rate: "", option_value_ids: [""] }
      ])
      expect { product.save! }.not_to change(Variant, :count)
    end

    it "keeps option_value_ids when only options are selected (not rejected), but variant validation fails" do
      ov = create(:option_value)
      product.assign_attributes(variants_attributes: [
        { sku: "", price: "", stock: "", vat_rate: "", option_value_ids: [ov.id.to_s] }
      ])

      expect(product).not_to be_valid
      v = product.variants.first
      expect(v).to be_present
      expect(v.option_value_ids.map(&:to_s)).to include(ov.id.to_s)
      expect(v.errors[:sku]).to be_present
      expect(v.errors[:price]).to be_present
    end

    it "does NOT reject existing variant marked for destruction (symbol keys)" do
      v = create(:variant, product:, status: :active, price: 10, sku: "X")
      product.reload
      product.variants.load
      # Chei simbol (ca in script/seed)
      product.assign_attributes(variants_attributes: [{ id: v.id, _destroy: true }])
      product.save!

      expect(Variant.exists?(v.id)).to be(false)
    end

    it "does not raise LocalJumpError (uses if/else, not next)" do
      expect {
        product.assign_attributes(variants_attributes: [
          { sku: "TEST", price: "10" }
        ])
        product.save!
      }.not_to raise_error
    end
  end
end
```

### B) Request specs — Cart#add

```ruby
# spec/requests/cart_spec.rb
RSpec.describe "Cart", type: :request do
  describe "POST /cart/add" do
    it "rejects add when product has active variants but variant_id is blank" do
      product = create(:product, price: 100)
      create(:variant, product:, status: :active, price: 50)

      post add_cart_path, params: { product_id: product.id, quantity: 1 }
      expect(response).to redirect_to(carti_path)
      follow_redirect!
      expect(response.body).to include("Selecteaza o varianta")
    end

    it "scopes variant to product (variant from other product => RecordNotFound)" do
      p1 = create(:product, price: 100)
      p2 = create(:product, price: 100)
      v2 = create(:variant, product: p2, status: :active, price: 50)

      expect {
        post add_cart_path, params: { product_id: p1.id, variant_id: v2.id, quantity: 1 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "rejects add when variant has nil price" do
      product = create(:product, price: 100)
      variant = create(:variant, product:, status: :active, price: nil)

      post add_cart_path, params: { product_id: product.id, variant_id: variant.id, quantity: 1 }
      follow_redirect!
      expect(response.body).to include("nu mai este disponibila")
    end

    it "adds product without variants as simple product (no variant_id needed)" do
      product = create(:product, price: 100)

      post add_cart_path, params: { product_id: product.id, quantity: 1 }
      expect(session[:cart][product.id.to_s]).to be_present
    end

    it "rejects add when quantity is 0" do
      product = create(:product, price: 100)

      post add_cart_path, params: { product_id: product.id, quantity: 0 }
      expect(response).to redirect_to(carti_path)
      follow_redirect!
      expect(response.body).to include("Cantitate invalida")
    end

    it "rejects add when quantity is negative" do
      product = create(:product, price: 100)

      post add_cart_path, params: { product_id: product.id, quantity: -1 }
      expect(response).to redirect_to(carti_path)
      follow_redirect!
      expect(response.body).to include("Cantitate invalida")
    end
  end
end
```

### C) Controller specs — load_cart cleanup

```ruby
# spec/controllers/load_cart_spec.rb
RSpec.describe "load_cart cleanup", type: :controller do
  controller(ApplicationController) do
    def index
      load_cart
      head :ok
    end
  end

  before { routes.draw { get "index" => "anonymous#index" } }

  it "does not crash on non-hash payload; cleans it" do
    product = create(:product, price: 10)
    session[:cart] = { product.id.to_s => "not_a_hash" }

    get :index
    expect(response).to have_http_status(:ok)
    expect(session[:cart]).not_to have_key(product.id.to_s)
  end

  it "cleans qty <= 0 lines" do
    product = create(:product, price: 10)
    session[:cart] = { product.id.to_s => { "quantity" => "0" } }

    get :index
    expect(session[:cart]).not_to have_key(product.id.to_s)
  end

  it "cleans lines where product was deleted" do
    session[:cart] = { "999999" => { "quantity" => "1" } }

    get :index
    expect(session[:cart]).not_to have_key("999999")
  end

  it "cleans lines where variant is inactive" do
    product = create(:product, price: 10)
    variant = create(:variant, product:, status: :inactive, price: 20)
    session[:cart] = { "#{product.id}_v#{variant.id}" => { "quantity" => "1" } }

    get :index
    expect(session[:cart]).not_to have_key("#{product.id}_v#{variant.id}")
  end

  it "cleans lines where variant has nil price" do
    product = create(:product, price: 10)
    variant = create(:variant, product:, status: :active, price: nil)
    session[:cart] = { "#{product.id}_v#{variant.id}" => { "quantity" => "1" } }

    get :index
    expect(session[:cart]).not_to have_key("#{product.id}_v#{variant.id}")
  end

  it "uses variant_id from key when data diverges (key wins)" do
    product = create(:product, price: 10)
    v1 = create(:variant, product:, status: :active, price: 11)
    v2 = create(:variant, product:, status: :active, price: 22)
    cart_key = "#{product.id}_v#{v1.id}"
    session[:cart] = { cart_key => { "quantity" => "1", "variant_id" => v2.id.to_s } }

    get :index
    # Linia ramane (v1 exista si e activa), nu crapa
    expect(session[:cart]).to have_key(cart_key)
  end

  it "does not crash on integer key (old cart format)" do
    product = create(:product, price: 10)
    session[:cart] = { product.id => { "quantity" => "1" } }

    get :index
    expect(response).to have_http_status(:ok)
  end

  it "cleans line when product has active variants but no variant_id (old cart)" do
    product = create(:product, price: 10)
    create(:variant, product:, status: :active, price: 20, sku: "V1")
    session[:cart] = { product.id.to_s => { "quantity" => "1" } }

    get :index
    expect(session[:cart]).not_to have_key(product.id.to_s)
  end
end
```

### D) Controller/Request specs — Orders#create

**Nota:** Testul "variant-driven fara variant_id" e mai stabil ca **controller spec** (`type: :controller`)
decat request spec — poti seta `session[:cart]` direct. Restul pot fi request specs.

```ruby
# spec/controllers/orders_variant_guard_spec.rb  (controller spec pt guard-ul variant-driven)
# sau spec/requests/orders_spec.rb               (request spec pt restul)
RSpec.describe "Orders", type: :request do
  describe "POST /orders (checkout)" do
    it "rejects checkout when variant_id is present but variant is inactive" do
      product = create(:product, price: 100)
      variant = create(:variant, product:, status: :inactive, price: 50)

      # Simuleaza cart cu varianta inactiva
      post checkout_path, params: { ... },
        headers: { "Cookie" => "cart=#{...}" } # adapteaza la setup-ul tau

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("nu mai este disponibila")
    end

    it "rejects checkout when variant has nil price" do
      product = create(:product, price: 100)
      variant = create(:variant, product:, status: :active, price: nil)
      # setup cart...
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects checkout when qty <= 0" do
      product = create(:product, price: 100)
      # setup cart cu qty=0...
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("cantitate")
    end

    it "populates variant snapshot fields on order_item" do
      product = create(:product, price: 100)
      variant = create(:variant, product:, status: :active, price: 50, sku: "VAR-001")
      # setup cart cu varianta...
      # checkout...

      order = Order.last
      item = order.order_items.find_by(variant_id: variant.id)
      expect(item.variant_sku).to eq("VAR-001")
      expect(item.variant_options_text).to be_present
      expect(item.price).to eq(50)
    end

    it "creates transport order_item with price=0 (free shipping) — valid" do
      # setup cart + checkout cu subtotal >= 200 (transport gratuit)
      order = Order.last
      transport = order.order_items.find_by(product_name: "Transport")
      expect(transport).to be_present
      expect(transport.quantity).to eq(1)
      expect(transport.total_price).to eq(0)
    end

    it "creates transport order_item with price=20 (paid shipping) — valid" do
      # setup cart + checkout cu subtotal < 200 si produse fizice
      order = Order.last
      transport = order.order_items.find_by(product_name: "Transport")
      expect(transport.total_price).to eq(20)
    end
  end
end
```

### D2) Controller spec — Orders variant-driven guard (MUST-HAVE)

**Separat** de request specs — controller spec permite `session[:cart]` direct.

```ruby
# spec/controllers/orders_variant_guard_spec.rb
RSpec.describe OrdersController, type: :controller do
  describe "POST #create" do
    it "rejects checkout when product has active variants but cart line has no variant_id" do
      product = create(:product, price: 100)
      create(:variant, product:, status: :active, price: 50, sku: "V1")

      session[:cart] = { product.id.to_s => { "quantity" => "1" } }

      # IMPORTANT: adapteaza params la ce cere OrdersController (ex: order: attributes_for(:order))
      post :create, params: { order: {} }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to match(/Selecteaza o varianta/i)
    end
  end
end
```

### E) System specs (Capybara) — UI/JS (optionale, dar valoroase)

```ruby
# spec/system/product_form_spec.rb
RSpec.describe "Product form variants", type: :system, js: true do
  before { login_as(admin) } # adapteaza la auth

  it "toggle ON hides price/stock sections, shows variants section" do
    visit new_product_path
    check "toggle-variants"

    expect(page).not_to have_css("#section-prices", visible: true)
    expect(page).not_to have_css("#section-stock", visible: true)
    expect(page).to have_css("#section-variants", visible: true)
  end

  it "'+' adds exactly 1 row (not 2/3)" do
    visit new_product_path
    check "toggle-variants"
    click_button "+ Adauga varianta"

    expect(page).to have_css(".variant-row", count: 1)
  end

  it "'x' on new variant removes the row from DOM" do
    visit new_product_path
    check "toggle-variants"
    click_button "+ Adauga varianta"
    click_button "x"

    expect(page).not_to have_css(".variant-row")
  end

  it "feed variant shows readonly text, manual variant shows selects" do
    product = create(:product, price: 100)
    feed_variant = create(:variant, product:, status: :active, price: 50)
    create(:variant_external_id, variant: feed_variant) # face-o "feed"
    manual_variant = create(:variant, product:, status: :active, price: 30)

    visit edit_product_path(product)
    check "toggle-variants"

    # Feed variant: text readonly
    within(".variant-row[data-variant-id='#{feed_variant.id}']") do
      expect(page).to have_css(".variant-options-text")
      expect(page).not_to have_css("select[name*='option_value_ids']")
    end

    # Manual variant: select-uri editabile
    within(".variant-row[data-variant-id='#{manual_variant.id}']") do
      expect(page).not_to have_css(".variant-options-text")
      expect(page).to have_css("select[name*='option_value_ids']")
    end
  end
end
```

**Nota:** Adapteaza factory names (`:product`, `:variant`, `:option_value`), rute (`add_cart_path`, `checkout_path`) si auth (`login_as`) la setup-ul proiectului. Scheletele acopera logica — wiring-ul la factories/rute e specific.

---

## FISIERE MODIFICATE

| Fisier | Ce se modifica |
|--------|---------------|
| `app/models/product.rb` | `accepts_nested_attributes_for :variants` |
| `app/controllers/products_controller.rb` | `product_params` + `before_action :load_option_types` + `helper_method :preload_variants` |
| `app/views/products/_form.html.erb` | Toggle + sectiune variante + id-uri pe sectiuni |
| `app/views/products/_variant_fields.html.erb` | **NOU** — partial pt rand varianta |
| `app/assets/stylesheets/pages/_admin.css` | Stiluri tabel variante + badges |
| `app/controllers/cart_controller.rb` | Accept variant_id, cart_key compus, scoped lookup |
| `app/controllers/application_controller.rb` | Calcul pret din variant sau product, scoped lookup, cleanup variant invalida |
| `app/controllers/orders_controller.rb` | OrderItem cu variant_id/sku/options, scoped lookup, refuz variant invalida |
| `app/views/carti/show.html.erb` | Selector optiuni daca are variante |
| `app/views/cart/index.html.erb` | Afisare optiuni varianta in cos |

## FISIERE NEATINSE (pastrate exact cum sunt)

- Upload Bunny (imagini/fisiere) — nicio modificare
- Categorii (toggle badges) — nicio modificare
- Stripe checkout — primeste line_items la fel
- Cupoane — functioneaza pe subtotal, nu pe variant/product
- Transport — aceeasi regula (fizic + subtotal < 200)
- Email-uri, webhook, thank_you — neatinse
- Toate testele existente — trebuie sa ramana verzi

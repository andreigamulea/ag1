# PLAN_VARIANTE2.md - Plan Relaxat pentru Sistem de Variante

## Planul tau (reprodus):

```
Fluxul în Admin (pas cu pas):

PASUL 1: Introduci FAMILIA (produsul principal)
- Nume produs: "Stick USB Kingston DataTraveler"
- Descriere, Categorie, Brand
- Salvezi -> ai creat FAMILIA

PASUL 2: Introduci VARIANTELE (combinațiile cumpărabile)
- Fiecare variantă: SKU + Caracteristici + Preț + Stoc + Imagini
- Manual sau cu Generator automat

Reguli:
- Poți edita/adăuga/șterge variante ORICÂND
- Comenzile vechi au snapshot (nu sunt afectate)
- Produse fără variante = 1 variantă default
```

---

## Analiza: Este acest plan RELAXAT?

### DA! Acest plan e mult mai aproape de WooCommerce/Shopify.

Fraza cheie din planul tau:
> **"Poți edita/adăuga/șterge variante oricând"**

Asta e EXACT ce fac WooCommerce si Shopify. E opusul planului restrictiv din PLAN_VARIANTE.md.

---

## Comparatie directa:

| Functionalitate | PLAN_VARIANTE.md (restrictiv) | PLAN_VARIANTE2 (relaxat) | WooCommerce | Shopify |
|-----------------|------------------------------|--------------------------|-------------|---------|
| Editare optiuni varianta | NU (write-once) | **DA, oricand** | DA | DA |
| Stergere varianta | NU daca are comenzi | **DA, oricand** | DA | DA |
| Adaugare variante noi | DA | DA | DA | DA |
| Editare pret/stoc | DA | DA | DA | DA |
| Snapshot comenzi | DA | DA | DA | DA |
| Produse fara variante | Master variant | 1 varianta default | Similar | Similar |

**Verdict: Planul tau relaxat e IDENTIC cu WooCommerce/Shopify ca filozofie!**

---

## Ce inseamna tehnic "poti sterge oricand"?

Pentru a implementa asta, trebuie:

### 1. Comenzile sa pastreze TOATE datele necesare (snapshot complet)

```ruby
# order_items trebuie sa aiba:
- product_name        # "Stick USB Kingston DataTraveler"
- variant_sku         # "USB-RED-1TB"
- variant_options_text # "Culoare: Roșu, Capacitate: 1TB"
- unit_price          # 49.00
- vat_rate_snapshot   # 19.0
- quantity            # 2
```

Cand stergi varianta, comanda INCA arata corect toate datele.

### 2. variant_id pe order_item e OPTIONAL (nullable)

```ruby
belongs_to :variant, optional: true  # poate fi NULL dupa stergere
```

Cand afisezi comanda:
```ruby
def display_name
  if variant_options_text.present?
    # Avem snapshot - folosim datele salvate
    "#{product_name} — #{variant_options_text}"
  elsif variant.present?
    # Varianta inca exista - folosim datele live
    "#{variant.product.name} — #{variant.display_options}"
  else
    # Varianta stearsa, dar avem snapshot
    product_name || "Produs șters"
  end
end
```

### 3. Stergerea variantei = SET NULL pe comenzi, nu blocare

```ruby
# In loc de:
has_many :order_items, dependent: :restrict_with_exception  # BLOCHEAZA

# Folosim:
has_many :order_items, dependent: :nullify  # Seteaza variant_id = NULL
```

---

## Schimbari necesare fata de PLAN_VARIANTE.md:

### A. Eliminam "write-once" pe optiuni

```ruby
# ELIMINAM aceasta validare:
# validate :option_values_immutable, on: :update

# Admin poate schimba optiunile oricand
# Comenzile vechi au snapshot, nu sunt afectate
```

### B. Schimbam dependent: :restrict -> :nullify

```ruby
# Variant model - INAINTE (restrictiv):
has_many :order_items, dependent: :restrict_with_exception

# Variant model - DUPA (relaxat):
has_many :order_items, dependent: :nullify
```

### C. Eliminam blocajele la stergere option_values

```ruby
# INAINTE (restrictiv):
has_many :option_value_variants, dependent: :restrict_with_exception

# DUPA (relaxat) - doua optiuni:

# Optiunea 1: Cascade delete (sterge si join-urile)
has_many :option_value_variants, dependent: :destroy

# Optiunea 2: Soft delete pe option_value
# Nu stergi fizic, doar marchezi deleted_at
```

### D. Permitem editare option_types pe produs cu variante

```ruby
# ELIMINAM:
# before_destroy :check_no_variants_exist  # pe ProductOptionType

# Admin poate adauga/scoate option_types
# Variantele existente raman cum sunt
# Variantele NOI vor avea noile option_types
```

---

## Riscuri si cum le gestionam:

### Risc 1: Admin sterge varianta din greseala

**Solutie:** Confirmation dialog + optional Trash/Undo

```javascript
// In admin UI:
if (confirm("Sigur vrei să ștergi varianta 'Roșu 1TB'?\n\nAceastă acțiune nu poate fi anulată.")) {
  deleteVariant(id);
}
```

**Solutie avansata:** Soft delete cu recuperare 30 zile
```ruby
# Variant model
include Discard::Model  # sau acts_as_paranoid
default_scope { kept }  # exclude soft-deleted din queries normale
```

### Risc 2: Admin schimba optiunile si uita ce era inainte

**Solutie:** Audit log / versioning

```ruby
# Folosim paper_trail sau audited gem
class Variant < ApplicationRecord
  has_paper_trail
end

# Admin poate vedea istoricul:
# "Varianta #123 modificata la 15:30 - Culoare schimbata din Rosu in Albastru"
```

### Risc 3: Comenzi vechi arata "Produs sters"

**Solutie:** Snapshot COMPLET la creare comanda (deja in plan)

```ruby
# La creare order_item, salvam TOATE datele:
order_item = OrderItem.create!(
  product_name: variant.product.name,
  variant_sku: variant.sku,
  variant_options_text: variant.display_options,  # "Roșu, 1TB"
  unit_price: variant.price,
  vat_rate_snapshot: variant.product.vat,
  # ...
)
```

Chiar daca varianta e stearsa, comanda arata perfect.

---

## Implementare tehnica simplificata:

### Schema DB (modificari minime):

```ruby
# order_items - asigura snapshot complet
add_column :order_items, :variant_sku, :string
add_column :order_items, :variant_options_text, :string
add_column :order_items, :vat_rate_snapshot, :decimal

# variant_id ramane optional (poate fi NULL dupa stergere)
change_column_null :order_items, :variant_id, true
```

### Variant model (simplificat):

```ruby
class Variant < ApplicationRecord
  belongs_to :product
  has_many :option_value_variants, dependent: :destroy
  has_many :option_values, through: :option_value_variants
  has_many :order_items, dependent: :nullify  # RELAXAT!

  validates :sku, presence: true, uniqueness: { scope: :product_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # NU mai avem:
  # - validate :option_values_immutable
  # - validate :is_master_immutable (optional, poti pastra)

  # Pastrezi restul: display_options, available?, etc.
end
```

### OptionValueVariant (simplificat):

```ruby
class OptionValueVariant < ApplicationRecord
  belongs_to :variant
  belongs_to :option_value

  # NU mai avem before_create/before_destroy care blocheaza
  # Join-urile se pot crea/sterge liber
end
```

---

## Flow-ul complet (relaxat):

```
ADMIN CREEAZA PRODUS
        |
        v
    [Product]
    - nume, descriere
    - categorie, brand
        |
        v
ADMIN ADAUGA VARIANTE (manual sau generator)
        |
        v
    [Variant 1]          [Variant 2]          [Variant 3]
    - SKU: RED-1TB       - SKU: RED-3TB       - SKU: BLK-1TB
    - Rosu, 1TB          - Rosu, 3TB          - Negru, 1TB
    - 49 RON             - 89 RON             - 49 RON
    - Stoc: 10           - Stoc: 5            - Stoc: 8
        |
        v
CLIENT CUMPARA (Variant 1)
        |
        v
    [OrderItem] - SNAPSHOT COMPLET
    - product_name: "Stick USB Kingston"
    - variant_sku: "RED-1TB"
    - variant_options_text: "Roșu, 1TB"
    - unit_price: 49
    - variant_id: 1  (link la varianta)
        |
        v
ADMIN STERGE Variant 1 (peste 1 an)
        |
        v
    [OrderItem] - INCA CORECT!
    - product_name: "Stick USB Kingston"
    - variant_sku: "RED-1TB"
    - variant_options_text: "Roșu, 1TB"  <- SNAPSHOT
    - unit_price: 49
    - variant_id: NULL  (varianta stearsa)
```

---

## Concluzii:

### Planul tau RELAXAT este:

1. **CORECT** - urmeaza standardul industriei (WooCommerce, Shopify)
2. **SIMPLU** - mai putin cod, mai putine validari
3. **FLEXIBIL** - admin poate face orice, oricand
4. **SIGUR** - comenzile au snapshot, nu sunt afectate de modificari

### Diferenta fata de planul restrictiv:

| Aspect | Restrictiv | Relaxat |
|--------|-----------|---------|
| Complexitate cod | Mare (multe validari) | Mica |
| Flexibilitate admin | Mica | Mare |
| Risc erori admin | Mic (blocat de sistem) | Mediu (depinde de admin) |
| Experienta admin | Frustranta | Placuta |
| Aproape de WooCommerce | NU | DA |

### Recomandare:

**Implementeaza planul RELAXAT** cu aceste protectii minime:
1. Snapshot COMPLET pe order_items (obligatoriu)
2. Confirmation dialog la stergere (UI)
3. Optional: Soft delete cu recuperare 30 zile
4. Optional: Audit log pentru istoric modificari

---

## Intrebari pentru tine:

1. Vrei sa adaug **soft delete** (recuperare variante sterse)?
2. Vrei **audit log** (istoric modificari)?
3. Sau mergem pe varianta **cea mai simpla** (doar snapshot + confirmation)?

Spune-mi si incepem implementarea!

---

# PARTEA 2: Decizie - `status: active/inactive`

## Discutie: De ce sa NU folosim `archived` / `discarded_at`?

### Intrebarea ta:
> "Dar de ce trebuie să arhivezi? Nu ar fi mai bine să fie un câmp care să facă invalid?"

### Raspunsul:

Ai dreptate! **`archived`** implica ceva DEFINITIV - "nu mai vreau sa vad niciodata, e istorie".

Dar in realitate, o varianta "stearsa" de admin poate fi:
- Temporar indisponibila (stoc 0, dar poate reveni)
- Gresita si trebuie ascunsa (dar poate fi corectata)
- Discontinuata (dar poate reveni peste cateva luni)

**Concluzie:** Un `status` e mai flexibil decat un timestamp de "arhivare".

---

## Cum fac Shopify si Solidus?

### Shopify: Status-based (ca tine)

```
status: active / draft / archived
```

- **active** = vizibil pe site, poate fi cumparat
- **draft** = nu e publicat inca (pentru produse in lucru)
- **archived** = ascuns, nu mai e vandut, DAR poate fi reactivat oricand

Shopify NU sterge nimic - totul ramane in sistem cu status diferit.

### Solidus: Soft-delete (discarded_at)

```ruby
# Solidus foloseste un timestamp
deleted_at: nil sau DateTime
```

- `deleted_at = nil` = activ
- `deleted_at = "2024-01-15"` = "sters" (soft delete)

Solidus poate restaura (`deleted_at = nil`), dar semantica e "a fost sters la data X".

---

## Diferenta practica:

| Aspect | Shopify (status) | Solidus (soft-delete) |
|--------|------------------|----------------------|
| Semantica | "Ce stare are acum?" | "A fost sters vreodata?" |
| Reactivare | Schimbi status: inactive → active | Stergi timestamp: deleted_at = nil |
| Raportare | Filtrez dupa status | Filtrez dupa deleted_at IS NULL |
| Intentia | "Poate reveni" | "A fost eliminat" |
| Audit | Trebuie log separat | deleted_at = timestamp implicit |

---

## Ce inseamna "arhivat"?

**Arhivat** = "Nu mai e relevant pentru operatiunile curente, dar il pastram pentru istoric."

Exemplu din viata reala:
- Documentele arhivate merg in DEPOZIT - nu le mai accesezi zilnic
- Emailurile arhivate dispar din Inbox - le gasesti doar daca cauti specific
- Produsele arhivate dispar din catalog - le vezi doar in rapoarte vechi

**Problema cu "arhivat" pentru variante:**
> "pare ca inactive ar fi solutia deoarece poate va reveni"

Exact! Daca varianta "Rosu 1TB" nu mai e in stoc acum, dar peste o luna primesti marfa, vrei sa o REACTIVEZI, nu sa o "dezarhivezi".

---

## Decizia FINALA: `status: active/inactive`

### De ce `inactive` si nu `archived`:

1. **Semantica corecta:** "Varianta nu e disponibila ACUM" (nu "a fost eliminata definitiv")
2. **Actiune clara:** Admin face "Dezactiveaza" / "Activeaza" (nu "Arhiveaza" / "Restaureaza")
3. **Asteptare de revenire:** `inactive` sugereaza ca POATE reveni

### Implementare:

```ruby
# Migrare
add_column :variants, :status, :integer, null: false, default: 0
add_index :variants, :status

# Model
class Variant < ApplicationRecord
  enum :status, { active: 0, inactive: 1 }
  # SAU cu Rails 7+:
  # enum :status, [:active, :inactive], default: :active

  # NU avem default_scope!

  # Scope-uri
  scope :available, -> { active }  # sau where(status: :active)
  scope :purchasable, -> { active.complete.where('stock > 0') }

  # Metode pentru admin
  def deactivate!
    update!(status: :inactive)
  end

  def activate!
    update!(status: :active)
  end
end
```

### Diferente fata de Discard (soft delete):

```ruby
# Cu Discard (INAINTE):
variant.discard!           # seteaza discarded_at = Time.current
variant.undiscard!         # seteaza discarded_at = nil
variant.kept?              # discarded_at.nil?
variant.discarded?         # discarded_at.present?
Variant.kept               # WHERE discarded_at IS NULL

# Cu status enum (ACUM):
variant.inactive!          # status = 1
variant.active!            # status = 0
variant.active?            # status == 'active'
variant.inactive?          # status == 'inactive'
Variant.active             # WHERE status = 0
```

---

## CHECKLIST ACTUALIZAT (inlocuieste Discard cu status enum):

### Database (migrare actualizata):

```ruby
# 1. Status pe Variant (in loc de discarded_at)
add_column :variants, :status, :integer, null: false, default: 0
add_index :variants, :status
# enum: { active: 0, inactive: 1 }

# 2. SKU unic pe viata (FARA conditie)
add_index :variants, [:product_id, :sku], unique: true

# 3. options_digest unic (FARA conditie pe status!)
#    O combinatie = o singura varianta (nu creezi duplicate, doar reactivezi)
add_column :variants, :options_digest, :string
add_index :variants, [:product_id, :options_digest], unique: true,
          where: "options_digest IS NOT NULL"
# IMPORTANT: Index-ul NU are conditie "WHERE status = 0"
# Asta previne situatia confuza: 2 variante cu aceeasi combinatie (una active, una inactive)

# 4. Index unic pe join (previne duplicate)
add_index :option_value_variants, [:variant_id, :option_value_id], unique: true

# 5. Indexuri pentru performanta scope :complete
add_index :product_option_types, [:product_id, :option_type_id]
add_index :option_values, :option_type_id

# 6. Snapshot pe order_items
add_column :order_items, :variant_sku, :string
add_column :order_items, :variant_options_text, :string
add_column :order_items, :vat_rate_snapshot, :decimal, precision: 5, scale: 2
add_column :order_items, :currency, :string, default: 'RON'
add_column :order_items, :line_total_gross, :decimal, precision: 10, scale: 2
add_column :order_items, :tax_amount, :decimal, precision: 10, scale: 2
change_column_null :order_items, :variant_id, true
```

### Variant Model FINAL (cu status enum):

```ruby
class Variant < ApplicationRecord
  # NU mai folosim Discard::Model
  # NU avem default_scope!

  enum :status, { active: 0, inactive: 1 }, default: :active

  belongs_to :product
  has_many :option_value_variants, dependent: :destroy
  has_many :option_values, through: :option_value_variants
  has_many :order_items, dependent: :nullify

  validates :sku, presence: true, uniqueness: { scope: :product_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :one_value_per_option_type

  # Scope-uri (inlocuiesc `kept` din Discard)
  scope :available, -> { active }
  scope :purchasable, -> { active.complete.where('stock > 0') }
  scope :complete, -> {
    where("NOT EXISTS (
      SELECT 1 FROM product_option_types pot
      WHERE pot.product_id = variants.product_id
        AND NOT EXISTS (
          SELECT 1 FROM option_value_variants ovv
          JOIN option_values ov ON ov.id = ovv.option_value_id
          WHERE ovv.variant_id = variants.id
            AND ov.option_type_id = pot.option_type_id
        )
    )")
  }

  # Metode pentru admin (inlocuiesc discard!/undiscard!)
  def deactivate!
    inactive!
  end

  def activate!
    active!
  end

  private

  def one_value_per_option_type
    ot_ids = option_values.map(&:option_type_id)
    if ot_ids.size != ot_ids.uniq.size
      errors.add(:base, "Varianta nu poate avea mai multe valori din acelasi tip")
    end
  end
end
```

### OptionValueVariant (neschimbat):

```ruby
class OptionValueVariant < ApplicationRecord
  belongs_to :variant
  belongs_to :option_value

  after_create :recalculate_variant_digest
  after_destroy :recalculate_variant_digest

  private

  def recalculate_variant_digest
    digest = variant.option_value_ids.sort.join('-').presence
    variant.update_column(:options_digest, digest)
  end
end
```

### OrderItem (neschimbat):

```ruby
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true
  belongs_to :variant, optional: true  # Poate fi nil daca varianta e hard-deleted (cleanup)

  def display_name
    if variant_options_text.present?
      "#{product_name} — #{variant_options_text}"
    elsif variant.present?
      "#{variant.product.name} — #{variant.display_options}"
    else
      product_name || "Produs"
    end
  end
end
```

### Admin Controller:

```ruby
class Admin::VariantsController < Admin::BaseController
  def deactivate
    @variant = Variant.find(params[:id])
    @variant.deactivate!
    redirect_to admin_product_path(@variant.product),
                notice: "Varianta '#{@variant.sku}' a fost dezactivata."
  end

  def activate
    @variant = Variant.find(params[:id])
    @variant.activate!
    redirect_to admin_product_path(@variant.product),
                notice: "Varianta '#{@variant.sku}' a fost activata."
  end

  # "Sterge" = dezactiveaza (nu hard delete)
  def destroy
    @variant = Variant.find(params[:id])
    @variant.deactivate!
    redirect_to admin_product_path(@variant.product),
                notice: "Varianta a fost dezactivata."
  end
end
```

---

## Sumar: De ce `status: active/inactive` e mai bun pentru cazul tau

| Criteriu | discarded_at (soft delete) | status enum |
|----------|---------------------------|-------------|
| Semantica | "A fost sters" | "Ce stare are acum" |
| Reactivare | "Restaureaza din arhiva" | "Activeaza varianta" |
| Intentie admin | Definitiv | Poate reveni |
| Gem necesar | Discard | Niciuna (built-in Rails) |
| Flexibilitate | 2 stari (activ/sters) | Extensibil (active/inactive/draft/etc) |

**Decizia finala:**
> "pare ca inactive ar fi solutia deoarece poate va reveni"

**Corect!** Folosim `status: active/inactive` pentru ca:
1. Varianta POATE reveni (nu e "arhivata definitiv")
2. Semantica e mai clara pentru admin ("Dezactiveaza" vs "Arhiveaza")
3. Nu avem nevoie de gem extern (Discard)
4. Putem extinde mai tarziu cu alte statusuri (draft, pending_review, etc.)

---

## CONCLUZIE PARTEA 2:

**Planul e COMPLET cu decizia:**

```
status: active/inactive  (NU discarded_at)
```

**Toate celelalte componente raman la fel:**
- SKU unic pe viata
- options_digest + index unic
- Index unic pe join
- Validare 1 value per type
- Callback recalculare digest
- Indexuri performanta
- Checkout atomic
- OptionValue global protejat
- Snapshot pe order_items
- variant_id nullable pe order_items

**GATA DE IMPLEMENTARE!**

---

## Clarificare FINALA de la prieten (confirmare):

> "Dacă intenția e „o scot din vânzare acum, dar poate revine", atunci `inactive` (status) e mai potrivit decât `archived/soft-delete`."

### Puncte cheie confirmate:

1. **`inactive` = varianta rămâne în DB**, legată de comenzi/rapoarte, dar:
   - NU e cumpărabilă
   - NU apare în selectorul de pe site
   - Admin-ul poate oricând s-o **reactiveze**

2. **Unicitatea combinației (options_digest) - FARA conditie pe status:**
   - O combinație = o singură variantă
   - Nu creezi duplicate, doar **reactivezi** varianta existentă
   - Index unic `(product_id, options_digest)` fără `WHERE status = 0`
   - Asta previne situația confuză: "2 variante cu aceeași combinație (una active, una inactive)"

3. **În shop filtrezi pe `active`:**
   - Tot ce e "nevândabil" (inactive, incomplete, stock 0) nu intră în selector
   - Scope: `purchasable -> { active.complete.where('stock > 0') }`

4. **NU folosi default_scope pe Variant:**
   - Indiferent dacă e discard sau status
   - Ca să nu-ți "ascundă" varianta în comenzi/rapoarte

### Admin UX (relaxat):

- Buton: **"Dezactivează"** / **"Activează"**
- **"Delete"** îl poți scoate din UI (sau îl lași doar pentru superadmin/cleanup tasks)

---

## STATUS FINAL: PLAN COMPLET SI VALIDAT

| Componenta | Decizie | Status |
|------------|---------|--------|
| Status vs Soft-delete | `status: active/inactive` | FINALIZAT |
| SKU | Unic pe viață | FINALIZAT |
| options_digest | Index unic FARA conditie pe status | FINALIZAT |
| Index pe join | `(variant_id, option_value_id)` unique | FINALIZAT |
| Validare 1 value per type | Validare in model | FINALIZAT |
| Callback digest | Pe OptionValueVariant | FINALIZAT |
| Indexuri performanță | Pe product_option_types, option_values | FINALIZAT |
| Checkout atomic | UPDATE WHERE stock >= qty | FINALIZAT |
| OptionValue global | Protejat (nu sterge, detașează) | FINALIZAT |
| Snapshot order_items | Campuri complete | FINALIZAT |
| variant_id nullable | dependent: :nullify | FINALIZAT |
| default_scope | NU folosim! | FINALIZAT |

**PLANUL E 100% COMPLET SI GATA DE IMPLEMENTARE!**

---

# PARTEA 3: Implementare FINALA - O SINGURA strategie (status enum)

## Feedback final de la prieten:

> "În text încă există urme din varianta cu Discard/discarded_at amestecate cu varianta nouă status: active/inactive. Ca să fie 100% coerent și implementabil fără surprize, curăță planul."

---

## CE SE ELIMINA (varianta veche Discard):

| Element | Status |
|---------|--------|
| `discarded_at` column | ELIMINAT |
| `gem 'discard'` | ELIMINAT |
| `include Discard::Model` | ELIMINAT |
| `Variant.kept` scope | ELIMINAT |
| `discard!` / `undiscard!` | ELIMINAT |
| Index pe `discarded_at` | ELIMINAT |
| Conditii `WHERE discarded_at IS NULL` | ELIMINATE |

---

## CE RAMANE (varianta finala status enum):

| Element | Implementare |
|---------|--------------|
| `status` column | `enum :status, { active: 0, inactive: 1 }` |
| Scope pentru active | `scope :available, -> { active }` |
| Metode admin | `deactivate!` / `activate!` |
| Index pe status | `add_index :variants, :status` |

---

## MIGRARE FINALA CURATATA (fara Discard):

```ruby
class SetupVariantsSystem < ActiveRecord::Migration[7.0]
  def change
    # 1. Status pe Variant (NU discarded_at!)
    add_column :variants, :status, :integer, null: false, default: 0
    add_index :variants, :status
    # enum: { active: 0, inactive: 1 }

    # 2. SKU unic pe viata (FARA conditie)
    add_index :variants, [:product_id, :sku], unique: true,
              name: 'idx_unique_sku_per_product'

    # 3. options_digest unic (FARA conditie pe status!)
    add_column :variants, :options_digest, :string
    add_index :variants, [:product_id, :options_digest], unique: true,
              where: "options_digest IS NOT NULL",
              name: 'idx_unique_options_per_product'

    # 4. Index unic pe join (previne duplicate)
    add_index :option_value_variants, [:variant_id, :option_value_id], unique: true,
              name: 'idx_unique_option_value_per_variant'

    # 5. Indexuri pentru performanta scope :complete
    add_index :product_option_types, [:product_id, :option_type_id],
              name: 'idx_product_option_types_lookup'
    add_index :option_values, :option_type_id,
              name: 'idx_option_values_by_type'

    # 6. Snapshot pe order_items
    add_column :order_items, :variant_sku, :string
    add_column :order_items, :variant_options_text, :string
    add_column :order_items, :vat_rate_snapshot, :decimal, precision: 5, scale: 2
    add_column :order_items, :currency, :string, default: 'RON'
    add_column :order_items, :line_total_gross, :decimal, precision: 10, scale: 2
    add_column :order_items, :tax_amount, :decimal, precision: 10, scale: 2
    change_column_null :order_items, :variant_id, true
  end
end
```

---

## MODEL VARIANT FINAL CURAT (fara Discard):

```ruby
class Variant < ApplicationRecord
  # ====== STATUS ENUM (inlocuieste Discard) ======
  enum :status, { active: 0, inactive: 1 }, default: :active

  # ====== ASOCIERI ======
  belongs_to :product
  has_many :option_value_variants, dependent: :destroy
  has_many :option_values, through: :option_value_variants
  has_many :order_items, dependent: :nullify  # plasa de siguranta pentru cleanup

  # ====== VALIDARI ======
  validates :sku, presence: true, uniqueness: { scope: :product_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :one_value_per_option_type

  # ====== SCOPES ======
  # Inlocuiesc `kept` din Discard
  scope :available, -> { active }
  scope :purchasable, -> { active.complete.where('stock > 0') }
  scope :complete, -> {
    where("NOT EXISTS (
      SELECT 1 FROM product_option_types pot
      WHERE pot.product_id = variants.product_id
        AND NOT EXISTS (
          SELECT 1 FROM option_value_variants ovv
          JOIN option_values ov ON ov.id = ovv.option_value_id
          WHERE ovv.variant_id = variants.id
            AND ov.option_type_id = pot.option_type_id
        )
    )")
  }

  # ====== METODE ADMIN ======
  # Inlocuiesc discard!/undiscard!
  def deactivate!
    inactive!
  end

  def activate!
    active!
  end

  private

  def one_value_per_option_type
    ot_ids = option_values.map(&:option_type_id)
    if ot_ids.size != ot_ids.uniq.size
      errors.add(:base, "Varianta nu poate avea mai multe valori din acelasi tip")
    end
  end
end
```

---

## SERVICE PENTRU OPTIONS (un singur "writer" - recomandat):

> "Standardizează pe service (un singur writer) fiindcă previne recalculări multiple și evită coliziuni temporare cu indexul unic."

```ruby
# app/services/variants/update_options_service.rb
module Variants
  class UpdateOptionsService
    def initialize(variant)
      @variant = variant
    end

    # Schimba optiunile atomic - un singur loc unde se face asta
    def call(option_value_ids)
      @variant.transaction do
        # 1. Sterge join-urile vechi
        @variant.option_value_variants.destroy_all

        # 2. Creeaza join-urile noi
        option_value_ids.each do |ov_id|
          @variant.option_value_variants.create!(option_value_id: ov_id)
        end

        # 3. Recalculeaza digest ATOMIC
        digest = option_value_ids.sort.join('-').presence
        @variant.update_column(:options_digest, digest)
      end
    end
  end
end

# Folosire:
# Variants::UpdateOptionsService.new(variant).call([1, 5, 12])
```

**Nota:** Daca folosesti service-ul, poti elimina callback-ul din `OptionValueVariant`. Alege UNA din variante:
- **Varianta A (service):** Toate modificarile de optiuni trec prin service → fara callback pe join
- **Varianta B (callback):** Modificari directe permise → callback pe join recalculeaza digest

---

## ORDER ITEM (neschimbat):

```ruby
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true
  belongs_to :variant, optional: true  # Poate fi nil doar pentru cleanup rare

  def display_name
    if variant_options_text.present?
      "#{product_name} — #{variant_options_text}"
    elsif variant.present?
      "#{variant.product.name} — #{variant.display_options}"
    else
      product_name || "Produs"
    end
  end
end
```

---

## ADMIN CONTROLLER FINAL:

```ruby
class Admin::VariantsController < Admin::BaseController
  def deactivate
    @variant = Variant.find(params[:id])
    @variant.deactivate!
    redirect_to admin_product_path(@variant.product),
                notice: "Varianta '#{@variant.sku}' a fost dezactivată."
  end

  def activate
    @variant = Variant.find(params[:id])
    @variant.activate!
    redirect_to admin_product_path(@variant.product),
                notice: "Varianta '#{@variant.sku}' a fost activată."
  end

  # "Delete" in UI = deactivate (NU hard delete)
  def destroy
    @variant = Variant.find(params[:id])
    @variant.deactivate!
    redirect_to admin_product_path(@variant.product),
                notice: "Varianta a fost dezactivată."
  end

  # Hard delete - DOAR pentru superadmin/cleanup tasks
  # def hard_delete
  #   @variant = Variant.find(params[:id])
  #   @variant.destroy!  # dependent: :nullify seteaza order_items.variant_id = NULL
  #   redirect_to admin_product_path(@variant.product),
  #               notice: "Varianta a fost stearsa definitiv."
  # end
end
```

---

## CHECKOUT ATOMIC (neschimbat):

```ruby
# Order#finalize!
def finalize!
  transaction do
    order_items.each do |item|
      # Re-validare: varianta e activa?
      variant = Variant.active.find_by(id: item.variant_id)
      raise VariantUnavailableError, "Varianta nu mai este disponibila" unless variant

      # UPDATE atomic - imposibil de depasit
      rows = Variant
        .where(id: item.variant_id)
        .where('stock >= ?', item.quantity)
        .update_all(['stock = stock - ?', item.quantity])

      if rows == 0
        raise InsufficientStockError, "Stoc insuficient pentru #{item.variant_sku}"
      end
    end

    update!(status: 'confirmed')
  end
end
```

---

## VARIANTE INCOMPLETE CAND SE SCHIMBA OPTION_TYPES:

> "Când schimbi option_types, rulează un job mic care pune `inactive` pe variantele care devin incomplete."

```ruby
# Cand admin schimba option_types pe produs:
class Products::UpdateOptionTypesService
  def initialize(product)
    @product = product
  end

  def call(new_option_type_ids)
    @product.transaction do
      # Actualizeaza option_types
      @product.option_type_ids = new_option_type_ids

      # Dezactiveaza variantele incomplete
      incomplete_variants = @product.variants.reject(&:complete?)
      incomplete_variants.each(&:deactivate!)

      # Returneaza numarul de variante dezactivate pentru mesaj admin
      incomplete_variants.count
    end
  end
end

# In admin controller:
def update_option_types
  count = Products::UpdateOptionTypesService.new(@product).call(params[:option_type_ids])
  if count > 0
    flash[:warning] = "#{count} variante au fost dezactivate (incomplete)."
  end
  redirect_to admin_product_path(@product)
end
```

---

## MVP FINAL - 8 LINII (curat, fara Discard):

```
1. variants.status enum: active/inactive
2. order_items snapshot suficient (cum ai listat)
3. variant_id nullable + fallback pe snapshot
4. index unic pe (product_id, sku) - SKU pe viata
5. index unic pe (product_id, options_digest) unde digest nu e null
6. index unic pe join (variant_id, option_value_id)
7. complete scope + indexuri pt performanta
8. checkout re-validare + decrement stoc atomic
```

---

## CHECKLIST FINAL CURAT:

| Componenta | Implementare | Status |
|------------|--------------|--------|
| Status management | `enum :status, { active: 0, inactive: 1 }` | FINALIZAT |
| SKU unicitate | Index unic `(product_id, sku)` fara conditie | FINALIZAT |
| options_digest unicitate | Index unic `(product_id, options_digest)` fara conditie pe status | FINALIZAT |
| Join unicitate | Index unic `(variant_id, option_value_id)` | FINALIZAT |
| Validare 1 value/type | `validate :one_value_per_option_type` | FINALIZAT |
| Options update | Service object (un singur writer) | FINALIZAT |
| Scopes | `available`, `purchasable`, `complete` | FINALIZAT |
| Admin actions | `deactivate!` / `activate!` | FINALIZAT |
| Checkout | Re-validare + UPDATE atomic | FINALIZAT |
| Order snapshot | Campuri complete pe order_items | FINALIZAT |
| variant_id | Optional + dependent: :nullify (plasa siguranta) | FINALIZAT |
| Variante incomplete | Job care dezactiveaza cand se schimba option_types | FINALIZAT |

---

## DIFERENTE FATA DE VERSIUNILE ANTERIOARE:

| Aspect | Versiunea veche (Discard) | Versiunea FINALA (status) |
|--------|---------------------------|---------------------------|
| Gem extern | `gem 'discard'` | Nimic (built-in Rails) |
| Column | `discarded_at: datetime` | `status: integer` |
| Scope activi | `Variant.kept` | `Variant.active` |
| Dezactivare | `variant.discard!` | `variant.deactivate!` |
| Reactivare | `variant.undiscard!` | `variant.activate!` |
| Semantica | "A fost sters" | "Ce stare are acum" |
| Extensibilitate | 2 stari (activ/sters) | N stari (active/inactive/draft/etc) |

---

## CONCLUZIE ABSOLUT FINALA:

**Planul e 100% COERENT si CURAT:**

- O SINGURA strategie: `status: active/inactive`
- FARA urme de Discard/discarded_at
- Toate indexurile si conditiile sunt consistente
- Un singur "writer" pentru options (service)
- Admin UX clar: Dezactiveaza/Activeaza

**GATA DE IMPLEMENTARE!**

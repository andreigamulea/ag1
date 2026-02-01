# Plan de implementare: Sistem de Variante (Varianta B — normalizat)

## Fișiere existente care vor fi modificate

| Fișier | Ce se schimbă |
|--------|--------------|
| `app/models/product.rb` | Relații: has_many :variants, has_many :option_types through. Callback-uri after_create, after_commit |
| `app/models/order_item.rb` | Adăugare `belongs_to :variant, optional: true` + fallback display + snapshot câmpuri |
| `app/models/order.rb` | Actualizare `finalize_order!` cu lock ordonat pe variant și decrementare atomică |
| `app/controllers/products_controller.rb` | Orchestrare `Variants::Generator` service, management option types pe produs |
| `app/controllers/cart_controller.rb` | Cart să lucreze cu variant_id + validare backend anti-master |
| `app/controllers/orders_controller.rb` | Creare order_items cu variant_id + snapshot preț/opțiuni/VAT |
| `app/views/products/show.html.erb` | Dropdown-uri opțiuni + actualizare preț/stoc dinamic |
| `app/views/products/_form.html.erb` | Secțiune admin pentru option types + variante |
| `config/routes.rb` | Rute noi pentru option_types și admin management |

## Fișiere noi

| Fișier | Scop |
|--------|------|
| `app/models/variant.rb` | Model Variant |
| `app/models/option_type.rb` | Model OptionType |
| `app/models/option_value.rb` | Model OptionValue |
| `app/models/product_option_type.rb` | Join model Product ↔ OptionType |
| `app/models/option_value_variant.rb` | Join model Variant ↔ OptionValue |
| `app/services/variants/generator.rb` | Service object pentru generare combinații |
| 7+ migrări DB (detaliate mai jos) | Schema + data migration |
| `app/javascript/controllers/variant_select_controller.js` | Stimulus controller pt selecție variante pe frontend |

---

## Pașii de implementare

### Pas 1: Migrări bază de date

**1a. `create_option_types`**
```ruby
enable_extension 'citext'  # dacă nu e deja activă

create_table :option_types do |t|
  t.citext :name, null: false         # "size", "capacity", "color" — case insensitive
  t.string :presentation, null: false  # "Mărime", "Capacitate", "Culoare"
  t.integer :position, default: 0
  t.timestamps
end
add_index :option_types, :name, unique: true  # citext face unicitatea case-insensitive automat
```

**1b. `create_option_values`**
```ruby
create_table :option_values do |t|
  t.references :option_type, null: false, foreign_key: true
  t.citext :name, null: false          # "s", "m", "l", "xl" — case insensitive
  t.string :presentation, null: false   # "S", "M", "L", "XL"
  t.integer :position, default: 0
  t.timestamps
end
add_index :option_values, [:option_type_id, :name], unique: true  # citext = case-insensitive unic
```

**Decizie unicitate case-insensitive:** Folosim extensia Postgres `citext` în loc de indexuri pe `lower()`. `citext` e mai simplu — indexul unic clasic devine automat case-insensitive. Alternativă: `add_index :option_types, "lower(name)", unique: true` dacă nu vrei citext.

**1c. `create_product_option_types`**
```ruby
create_table :product_option_types do |t|
  t.references :product, null: false, foreign_key: true
  t.references :option_type, null: false, foreign_key: true
  t.integer :position, default: 0
  t.timestamps
end
add_index :product_option_types, [:product_id, :option_type_id], unique: true
```

**1d. `create_variants`**
```ruby
create_table :variants do |t|
  t.references :product, null: false, foreign_key: true
  t.string :sku, null: false, limit: 255
  t.decimal :price, precision: 10, scale: 2, null: false
  t.decimal :discount_price, precision: 10, scale: 2
  t.decimal :cost_price, precision: 10, scale: 2
  t.integer :stock, null: false, default: 0                    # FIX R8-4: NOT NULL
  t.string :stock_status, null: false, default: "in_stock"     # FIX R8-4: NOT NULL
  t.boolean :track_inventory, null: false, default: true       # FIX R8-4: NOT NULL
  t.decimal :weight, precision: 8, scale: 2
  t.integer :position, null: false, default: 0                 # FIX R8-4: NOT NULL
  t.boolean :is_master, null: false, default: false            # FIX R8-4: NOT NULL
  # FIX R10-9: options_digest ca :text pentru a evita limita de 255 chars
  t.text :options_digest, null: false, default: "MASTER"
  t.timestamps
end
add_index :variants, [:product_id, :sku], unique: true
add_index :variants, [:product_id, :options_digest], unique: true  # fără WHERE — acoperă și master
# FIX R8-6: Indexul parțial e redundant (CHECK + unique digest deja garantează 1 master),
# dar îl păstrăm pentru query performance pe `product.master` (index scan direct)
add_index :variants, :product_id, unique: true, where: "is_master = true",
          name: "index_variants_one_master_per_product"

# CHECK constraint: master ↔ digest "MASTER" e bicondiționat
execute <<~SQL
  ALTER TABLE variants ADD CONSTRAINT chk_master_digest
    CHECK ((is_master = true AND options_digest = 'MASTER') OR
           (is_master = false AND options_digest <> 'MASTER'));
SQL
```

**Decizie SKU:** Unicitate la nivel de produs (`product_id + sku`), nu global. Permite SKU-uri mai scurte și evită conflicte între produse diferite. Dacă pe viitor ai nevoie de SKU global unic (integrare ERP), adaugi un index global separat.

**Decizie options_digest:** Coloana e `NOT NULL` cu default `"MASTER"`. Master variant are mereu digest = "MASTER". Variantele reale au digest calculat din option_value_ids sortate (ex: "1-7-12"). Indexul unic pe `(product_id, options_digest)` fără `WHERE` garantează:
- Un singur master per produs (doar un "MASTER" per product_id)
- Nicio combinație duplicată per produs
- Nicio variantă non-master fără digest (NOT NULL)

**1e. `create_option_value_variants`**
```ruby
create_table :option_value_variants do |t|
  t.references :variant, null: false, foreign_key: true
  t.references :option_value, null: false, foreign_key: true
end
add_index :option_value_variants, [:variant_id, :option_value_id], unique: true
```

**1f. `add_variant_id_and_snapshot_to_order_items`**
```ruby
add_reference :order_items, :variant, foreign_key: true, null: true
add_column :order_items, :variant_sku, :string
add_column :order_items, :variant_options_text, :string  # "XL, Negru" — snapshot la momentul comenzii
add_column :order_items, :vat_rate_snapshot, :decimal, precision: 4, scale: 2  # VAT snapshot
```
Câmpurile `unit_price` și `product_name` există deja pe `order_items` — le folosim pentru snapshot.
`vat_rate_snapshot` salvează rata TVA la momentul comenzii (VAT se poate schimba în timp).

**1g. Data migration: `create_master_variants_for_existing_products`**
```ruby
# Idempotentă + safe la concurență (find_or_create_by + rescue)
Product.find_each do |product|
  Variant.find_or_create_by!(product: product, is_master: true) do |v|
    v.sku = product.sku.presence || "PROD-#{product.id}"
    v.price = product.price || 0
    v.discount_price = product.discount_price
    v.cost_price = product.cost_price
    v.stock = product.stock || 0
    v.stock_status = product.stock_status || "in_stock"
    v.track_inventory = product.track_inventory.nil? ? true : product.track_inventory
    v.weight = product.weight
    v.options_digest = "MASTER"
  end
rescue ActiveRecord::RecordNotUnique
  # Alt worker a creat-o deja, skip
  next
end
```

---

### Pas 2: Modele Rails

**Modele noi:**

**`OptionType`**
```ruby
class OptionType < ApplicationRecord
  has_many :option_values, -> { order(:position) }, dependent: :restrict_with_exception
  has_many :product_option_types, dependent: :restrict_with_exception
  has_many :products, through: :product_option_types

  # FIX R9-6: case_sensitive: false pentru a alinia Rails cu citext (DB)
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :presentation, presence: true
end
```

**`OptionValue`**
```ruby
class OptionValue < ApplicationRecord
  belongs_to :option_type
  has_many :option_value_variants, dependent: :restrict_with_exception
  has_many :variants, through: :option_value_variants

  # FIX R9-6: case_sensitive: false pentru a alinia Rails cu citext (DB)
  validates :name, presence: true, uniqueness: { scope: :option_type_id, case_sensitive: false }
  validates :presentation, presence: true
end
```

**`ProductOptionType`**
```ruby
class ProductOptionType < ApplicationRecord
  belongs_to :product
  belongs_to :option_type

  validates :option_type_id, uniqueness: { scope: :product_id }

  # FIX R9-5: Blochează ștergerea option_types dacă există variante non-master
  before_destroy :check_no_variants_exist

  private

  def check_no_variants_exist
    # FIX R12-4 + R13-2: Permite cascade destroy când produsul e distrus
    # destroyed_by_association e setat de Rails când join-ul e distrus prin asociere (product.destroy)
    # Asta e mai robust decât product.destroyed? care poate fi încă false în before_destroy
    return if destroyed_by_association.present?

    if product.variants.non_master.exists?
      errors.add(:base, "Nu poți elimina un option type când există variante. Șterge variantele întâi.")
      throw(:abort)
    end
  end
end
```

**Notă R9-5: Politica pentru schimbări de option_types:**
- **Ștergere option_type de pe produs:** BLOCATĂ dacă există variante non-master
- **Adăugare option_type nou:** PERMISĂ, dar variantele existente devin "incomplete" (nu au valoare pentru noul tip) — generatorul le va ignora, trebuie regenerate
- **Recomandare UI:** Avertizează admin-ul și oferă opțiunea de a regenera variantele sau de a le șterge pe cele vechi

**`Variant`**
```ruby
class Variant < ApplicationRecord
  belongs_to :product
  has_many :option_value_variants, dependent: :destroy
  has_many :option_values, through: :option_value_variants
  has_many :order_items, dependent: :restrict_with_exception

  # FIX R15-1: Flag explicit pentru a permite scrieri pe join-uri DOAR din generator
  # Fără acest flag setat explicit, orice attempt de a crea/șterge join-uri e blocat
  attr_accessor :allow_option_value_writes

  validates :sku, presence: true, uniqueness: { scope: :product_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :options_digest, presence: true, uniqueness: { scope: :product_id }

  before_validation :set_master_digest, if: :is_master
  # Opțiunile sunt write-once: nu se editează după creare (doar preț/stoc/sku)
  validate :option_values_immutable, on: :update, unless: :is_master
  # Invariant: non-master trebuie să aibă option_values, master trebuie să aibă zero
  validate :option_values_count_invariant, on: :create
  # FIX R10-5: Maxim 1 option_value per option_type
  validate :one_value_per_option_type, on: :create, unless: :is_master
  # FIX R9-4: is_master nu se poate schimba după creare
  validate :is_master_immutable, on: :update
  # FIX R10-10: Validare non-master digest != "MASTER" la nivel Rails (feedback curat)
  validate :non_master_digest_valid, on: :create, unless: :is_master

  before_validation :ensure_unique_sku_within_product, on: :create

  enum stock_status: { in_stock: "in_stock", out_of_stock: "out_of_stock" }

  scope :non_master, -> { where(is_master: false) }
  scope :masters, -> { where(is_master: true) }

  # FIX R12-3: Regula unificată de disponibilitate
  # - track_inventory=true → disponibil dacă stock > 0
  # - track_inventory=false → disponibil dacă stock_status == "in_stock"
  scope :available, -> {
    where("(track_inventory = true AND stock > 0) OR (track_inventory = false AND stock_status = 'in_stock')")
  }

  # FIX R12-5 + R14-2: Scope pentru variante "complete" (au toate option_values necesare)
  # Folosit în UI, "De la" pricing, JSON export
  # FIX R14-2: NU folosim GROUP BY — ar sparge .minimum(:price) care returnează Hash în loc de scalar
  # Folosim subquery cu WHERE EXISTS pentru a păstra relation-ul "flat" (fără grupare)
  scope :complete, -> {
    where(is_master: false).where(
      "NOT EXISTS (
        SELECT 1 FROM product_option_types pot
        WHERE pot.product_id = variants.product_id
          AND NOT EXISTS (
            SELECT 1 FROM option_value_variants ovv
            JOIN option_values ov ON ov.id = ovv.option_value_id
            WHERE ovv.variant_id = variants.id
              AND ov.option_type_id = pot.option_type_id
          )
      )"
    )
  }

  def available?
    # FIX R12-3: Metoda de instanță pentru disponibilitate
    if track_inventory?
      stock > 0
    else
      in_stock?  # enum method
    end
  end

  def available_for_quantity?(qty)
    # FIX R12-3: Verificare disponibilitate pentru o cantitate specifică
    if track_inventory?
      stock >= qty
    else
      in_stock?
    end
  end

  def complete?
    # FIX R12-5 + R13-3: Verifică dacă varianta are toate option_values necesare
    # FIX R13-3: Folosim distinct pe option_type_id pentru a detecta și date corupte
    # (ex: 2 valori din același option_type, lipsește alt option_type → count egal dar incomplet)
    return true if is_master?
    variant_ot_ids = option_values.map(&:option_type_id).uniq
    product_ot_ids = product.option_type_ids
    variant_ot_ids.sort == product_ot_ids.sort
  end

  # FIX R10-4: display_options în două variante:
  # - display_options: folosește datele preîncărcate (pentru listări cu includes)
  # - display_options_fresh: face query (pentru cazuri izolate, emails, jobs)

  def display_options
    # Versiune care folosește asocierile preîncărcate (ZERO queries dacă ai includes)
    # Ordinea: sortăm în Ruby după option_type.position (fallback dacă nu avem product_option_types)
    return "" if option_values.empty?

    # Dacă avem acces la product.product_option_types, folosim ordinea per produs
    pot_positions = if product&.association(:product_option_types)&.loaded?
      product.product_option_types.index_by(&:option_type_id).transform_values(&:position)
    else
      {}  # fallback: folosim option_type.position
    end

    option_values
      .sort_by { |ov| [pot_positions[ov.option_type_id] || ov.option_type.position, ov.position] }
      .map { |ov| "#{ov.option_type.presentation}: #{ov.presentation}" }
      .join(", ")
  end

  def display_options_fresh
    # Versiune cu query explicit (pentru jobs/emails unde nu ai preload)
    # FIX R9-1: Parametrizat SQL
    option_values
      .joins(:option_type)
      .joins(
        Variant.sanitize_sql_array([
          "INNER JOIN product_option_types pot
           ON pot.option_type_id = option_types.id AND pot.product_id = ?",
          product_id
        ])
      )
      .order("pot.position ASC, option_values.position ASC")
      .select("option_values.*, option_types.presentation AS ot_presentation")
      .map { |ov| "#{ov.ot_presentation}: #{ov.presentation}" }
      .join(", ")
  end

  def compute_and_set_digest!(ov_ids)
    self.options_digest = ov_ids.sort.join("-")
  end

  private

  def set_master_digest
    self.options_digest = "MASTER"
  end

  # FIX R9-4: Blochează schimbarea is_master după creare
  def is_master_immutable
    if will_save_change_to_is_master?
      errors.add(:is_master, "nu se poate modifica după creare")
    end
  end

  # FIX R10-5: Verifică că avem maxim 1 option_value per option_type
  def one_value_per_option_type
    return if option_value_variants.empty?
    ot_ids = option_value_variants.map { |ovv| ovv.option_value&.option_type_id }.compact
    if ot_ids.size != ot_ids.uniq.size
      errors.add(:base, "Varianta nu poate avea mai multe valori din același option type")
    end
  end

  # FIX R10-10: Non-master trebuie să aibă digest != "MASTER"
  def non_master_digest_valid
    if options_digest == "MASTER"
      errors.add(:options_digest, "nu poate fi 'MASTER' pentru variante non-master")
    end
  end

  # FIX R8-9: Validare robustă pentru write-once — compară snapshot-ul original
  def option_values_immutable
    return unless persisted?
    # Compară setul curent cu cel din DB (reîncărcat)
    current_ids = option_value_ids.sort
    original_ids = self.class.find(id).option_value_ids.sort
    if current_ids != original_ids
      errors.add(:base, "Opțiunile nu pot fi modificate după creare")
    end
  end

  def option_values_count_invariant
    return unless product
    if is_master
      if option_value_variants.any?
        errors.add(:base, "Master variant nu poate avea option values")
      end
    else
      expected = product.option_types.count
      actual = option_value_variants.size
      # FIX R8-5: Blocăm non-master când produsul nu are option types
      if expected == 0
        errors.add(:base, "Produsul nu are option types; nu se pot crea variante non-master")
      elsif actual != expected
        errors.add(:base, "Varianta trebuie să aibă exact #{expected} option values (are #{actual})")
      end
    end
  end

  # FIX R15-2: Verifică SKU-ul COMPLET (trunchiat), nu doar base
  # Problema veche: dacă SKU complet există dar base nu → nu adăugam sufix → RecordNotUnique
  # Noua abordare: verificăm existența SKU-ului final dorit, nu doar a bazei
  def ensure_unique_sku_within_product
    return if sku.blank? || product.blank?

    # SKU-ul complet dorit (deja trunchiat la 255 dacă e cazul)
    desired_sku = sku.to_s[0..254]
    # Base pentru construcția sufixelor (mai scurt pentru a lăsa loc pentru sufix)
    base = desired_sku[0..200]

    # FIX R10-13: Escape caractere speciale LIKE (%, _) în base
    escaped_base = Variant.sanitize_sql_like(base)

    # Query pentru toate SKU-urile care încep cu base (include și desired_sku)
    existing = product.variants.where.not(id: id)
      .where("sku LIKE ?", "#{escaped_base}%")
      .pluck(:sku).to_set

    # FIX R15-2: Verificăm dacă SKU-ul COMPLET dorit există, nu doar base
    return self.sku = desired_sku unless existing.include?(desired_sku)

    # Găsește un sufix liber
    counter = 1
    loop do
      candidate = "#{base}-#{counter}"[0..254]
      unless existing.include?(candidate)
        self.sku = candidate
        return
      end
      counter += 1
      # Fallback la random după 1000 încercări (coliziune improbabilă)
      if counter > 1000
        self.sku = "#{base}-#{SecureRandom.hex(4)}"[0..254]
        return
      end
    end
  end
end
```

**Decizie: Opțiuni write-once.** După creare, opțiunile unei variante nu se modifică — doar prețul, stocul, SKU-ul. Asta simplifică enorm digest-ul (calculat o singură dată la creare, nu la fiecare save) și evită inconsistențe când digest-ul ar trebui recalculat.

**`OptionValueVariant`**
```ruby
class OptionValueVariant < ApplicationRecord
  belongs_to :variant
  belongs_to :option_value
  validates :option_value_id, uniqueness: { scope: :variant_id }

  # FIX R12-2 + R15-1: Enforce write-once la nivel de join model cu flag explicit
  # Previne modificarea opțiunilor prin variant.option_values << ov sau .destroy
  # DOAR generatorul (care setează allow_option_value_writes = true) poate crea join-uri
  before_create  :ensure_write_allowed
  before_destroy :ensure_write_allowed

  # FIX R14-10: Blochează adăugarea de opțiuni pe master (invariant: master = 0 option_values)
  validate :master_cannot_have_options, on: :create

  private

  def ensure_write_allowed
    # FIX R13-1: Permite cascade destroy (variant.destroy → distruge join-urile)
    # destroyed_by_association e setat de Rails când join-ul e distrus prin asociere
    return if destroyed_by_association.present?

    # FIX R15-1: Permite scrieri DOAR dacă flag-ul e setat explicit (de generator)
    # Asta blochează: variant.option_values << ov, variant.option_value_variants.destroy_all
    # pe variante persistate, DAR permite generatorului să creeze join-uri
    return if variant&.allow_option_value_writes

    # FIX R14-10: Master nu ar trebui să aibă opțiuni — blochează orice modificare
    if variant&.is_master?
      errors.add(:base, "Master variant nu poate avea option values")
      throw(:abort)
    end

    # Blochează orice modificare pe variante persistate fără flag-ul explicit
    unless variant.nil? || variant.new_record?
      errors.add(:base, "Nu se pot modifica opțiunile unei variante existente")
      throw(:abort)
    end
  end

  # FIX R14-10: Master variant nu poate avea option_values — validare suplimentară
  def master_cannot_have_options
    if variant&.is_master?
      errors.add(:base, "Master variant nu poate avea option values")
    end
  end
end
```
**FIX R12-2 + R15-1:** Protecția write-once folosește acum un flag explicit `allow_option_value_writes` pe Variant.
- Generatorul setează `variant.allow_option_value_writes = true` înainte de build
- Orice altceva (console, cod malițios, bug) care încearcă `variant.option_values << ov` e blocat
- `before_create` și `before_destroy` verifică flag-ul
**FIX R13-1:** Permite cascade destroy — când ștergi o variantă, join-urile se șterg fără blocare (Rails setează `destroyed_by_association`).
**FIX R14-10:** Master nu poate primi option_values în nicio circumstanță.

**Modificări pe modele existente:**

**`Product`** — adăugări:
```ruby
has_many :variants, dependent: :destroy
has_many :product_option_types, -> { order(:position) }, dependent: :destroy
has_many :option_types, through: :product_option_types

# FIX R14-5: Validare lungime SKU (limita DB e 255)
validates :sku, length: { maximum: 255 }, allow_blank: true

before_create :build_master_variant
after_commit :sync_master_attributes, on: :update, if: :relevant_attributes_changed?
# FIX R13-4: Normalizează SKU-ul master după create dacă produsul nu avea SKU
after_commit :normalize_master_sku, on: :create

# FIX R13-6: Folosește asocierea încărcată dacă disponibilă (evită query suplimentar)
def master
  if association(:variants).loaded?
    variants.detect(&:is_master?)
  else
    variants.find_by(is_master: true)
  end
end

# FIX R14-9: Folosește asocierea încărcată dacă disponibilă (evită N+1 în migrare cart etc.)
def has_variants?
  if association(:variants).loaded?
    variants.any? { |v| !v.is_master? }
  else
    variants.where(is_master: false).exists?
  end
end

# Sursa adevărului: Product e entitatea de catalog.
# Master variant e mirror comercial — până la migrarea viitoare.

private

def build_master_variant
  # build, nu create! — se salvează atomic cu Product în aceeași tranzacție
  # FIX R14-5: Trunchiază SKU la 255 chars (limita DB)
  sku_value = (sku.presence || "PROD-TEMP-#{SecureRandom.hex(4)}")[0..254]
  variants.build(
    is_master: true,
    sku: sku_value,
    price: price || 0,
    discount_price: discount_price,
    cost_price: cost_price,
    stock: stock || 0,
    stock_status: stock_status || "in_stock",
    track_inventory: track_inventory.nil? ? true : track_inventory,
    weight: weight,
    options_digest: "MASTER"
  )
end

def sync_master_attributes
  m = master
  return unless m&.persisted?

  # FIX R8-1: Fallback pentru câmpuri NOT NULL — evită DB constraint violation
  # FIX R14-5: Trunchiază SKU la 255 chars (limita DB) — previne excepție în after_commit
  sku_value = (sku.presence || m.sku.presence || "PROD-#{id}").to_s[0..254]
  price_value = price || m.price || 0

  # FIX R12-1: NU sincronizăm stock/stock_status/track_inventory!
  # Inventarul e gestionat DOAR pe Variant (decrementat la checkout).
  # Dacă am sincroniza, am suprascrie stocul corect al variantei cu valoarea veche din Product.
  # Sincronizăm doar: preț, discount, cost, weight, SKU (atribute de catalog, nu de inventar).

  # update_columns evită callback-uri pe Variant (sync strict, fără cascadă)
  m.update_columns(
    price: price_value,
    discount_price: discount_price,
    cost_price: cost_price,
    weight: weight,
    sku: sku_value,
    updated_at: Time.current
  )
end

def relevant_attributes_changed?
  # FIX R12-1: Eliminat stock/stock_status/track_inventory din trigger
  # (inventarul nu se sincronizează de la Product → Variant)
  saved_change_to_price? || saved_change_to_discount_price? || saved_change_to_cost_price? ||
  saved_change_to_weight? || saved_change_to_sku?
end

# FIX R13-4: Normalizează SKU-ul master dacă produsul a fost creat fără SKU
# La create, master primește "PROD-TEMP-xxx", dar după create avem id-ul produsului
def normalize_master_sku
  return if sku.present?  # Produsul are SKU, nu trebuie normalizat
  m = master
  return unless m&.persisted? && m.sku&.start_with?("PROD-TEMP-")
  m.update_columns(sku: "PROD-#{id}", updated_at: Time.current)
end
```

**Decizie sync: `update_columns` în loc de `update!`.** Evită callback-uri pe Variant (care ar putea cauza cascadă). Nu rulează validări — de aceea avem fallback-uri explicite pentru câmpurile NOT NULL (FIX R8-1).

**FIX R12-1: Variant e sursa adevărului pentru inventar.** `sync_master_attributes` sincronizează doar atributele de catalog (preț, SKU, weight), NU inventarul (stock, stock_status, track_inventory). Motivul: checkout-ul decrementează `variant.stock`, iar dacă Product.stock ar suprascrie master.stock la orice update, am pierde vânzările.

**`OrderItem`** — adăugări:
```ruby
belongs_to :variant, optional: true

def display_name
  if variant_options_text.present?
    "#{product_name} — #{variant_options_text}"
  elsif variant.present?
    "#{product&.name} — #{variant.display_options}"
  else
    product_name || product&.name || "Produs șters"
  end
end
```

**Dependent / restrict pe relații:**

| Relație | Strategie | Motiv |
|---------|-----------|-------|
| Product → variants | `dependent: :destroy` | Ștergerea produsului șterge variantele |
| Variant → order_items | `dependent: :restrict_with_exception` | Nu poți șterge variantă cu comenzi |
| OptionType → product_option_types | `dependent: :restrict_with_exception` | Nu poți șterge tip atașat la produse |
| OptionType → option_values | `dependent: :restrict_with_exception` | Nu poți șterge tip cu valori |
| OptionValue → option_value_variants | `dependent: :restrict_with_exception` | Nu poți șterge valoare folosită |

**Consecință Product → destroy:** Dacă un produs are variante cu comenzi, `product.destroy` va eșua (restrict pe Variant → order_items). Asta e corect — admin-ul trebuie să dezactiveze produsul (status: "inactive"), nu să-l șteargă. Controller-ul trebuie să prindă excepția și să afișeze mesaj clar.

**Alternativă viitoare:** Soft delete pe Variant și Product (adaugi `deleted_at`) pentru a păstra istoricul complet.

---

### Pas 3: Admin — Management Option Types

Pagină admin unde:
- Creezi option types: "Mărime", "Culoare", "Capacitate"
- Adaugi option values: S, M, L, XL pentru Mărime
- Reutilizezi aceleași option types pe mai multe produse
- Unicitate name pe OptionType și pe OptionValue per OptionType (case insensitive prin citext)

Rute noi:
```ruby
resources :option_types do
  resources :option_values, only: [:create, :destroy]
end
```

---

### Pas 4: Admin — Variante pe formularul de produs

Extindere `_form.html.erb` cu secțiune nouă:
1. Selectare option types pentru acest produs
2. Tabel cu variantele existente — coloane: SKU, preț, stoc, opțiuni afișate ca "Mărime: XL, Culoare: Negru"
3. Buton "Generează variante" — creează toate combinațiile
4. Editare inline a prețului/stocului/SKU per variantă (opțiunile NU se editează — write-once)
5. Ștergere variantă individuală (doar dacă nu are comenzi)

**Detaliu tehnic: Generare combinații — Service Object `Variants::Generator`**

Logica de generare e mutată din controller într-un service pentru testabilitate și reutilizare:

```ruby
# app/services/variants/generator.rb
module Variants
  class Generator
    def initialize(product)
      @product = product
    end

    def call
      master = @product.master
      return { created: 0, skipped: 0 } unless master

      # FIX R8-3: Folosim ordinea per produs (product_option_types.position), nu globală
      # Preload pentru a evita N+1
      ordered_option_types = @product.product_option_types
        .includes(option_type: :option_values)
        .order(:position)
        .map(&:option_type)

      # FIX R10-12: option_values sunt deja ordonate prin has_many scope, nu mai sortăm
      option_values_arrays = ordered_option_types.map { |ot| ot.option_values.to_a }

      # FIX R10-2: Blocăm generarea dacă nu există option types sau dacă vreunul nu are valori
      return { created: 0, skipped: 0 } if option_values_arrays.empty?
      return { created: 0, skipped: 0, error: "Un option type nu are valori definite" } if option_values_arrays.any?(&:empty?)

      # FIX R14-7: Advisory lock cu namespace (2-key) + try pentru a evita blocări infinite
      # Namespace 42 e arbitrar dar constant — evită coliziuni cu alte lock-uri din aplicație
      # pg_try_advisory_lock returnează true/false, nu blochează indefinit
      lock_acquired = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT pg_try_advisory_lock(42, ?)", @product.id]
        )
      )

      unless lock_acquired
        return { created: 0, skipped: 0, error: "Generare în curs de altcineva. Reîncearcă." }
      end

      begin
        # Preîncarcă digest-urile existente — O(1) lookup, fără N+1
        existing_digests = @product.variants
          .where(is_master: false)
          .pluck(:options_digest)
          .to_set

        created = 0
        skipped = 0

        # Fallback SKU dacă product.sku e NULL/blank — previne NoMethodError
        base_sku = (@product.sku.presence || "PROD-#{@product.id}")[0..200]

        # FIX R8-3: Folosim indexul din ordered_option_types pentru a păstra ordinea per produs
        # (combo vine deja în ordinea corectă din option_values_arrays)

        # Generare incrementală cu Enumerator (fără materializare completă în memorie)
        each_combination(option_values_arrays) do |combo|
          # combo e deja în ordinea product_option_types.position (din preload)
          digest = combo.map(&:id).sort.join("-")

          if existing_digests.include?(digest)
            skipped += 1
            next
          end

          sanitized_names = combo.map { |v| v.name.gsub(/[^a-zA-Z0-9]/, '_') }
          # FIX R8-7: Trunchiază SKU final la 255 chars (limita DB)
          generated_sku = "#{base_sku}-#{sanitized_names.join('-')}"[0..254]

          # FIX R8-15: Copiază direct din @product (sursa adevărului), nu din master
          # FIX R10-3: Copiază track_inventory din produs
          track_inv = @product.track_inventory.nil? ? true : @product.track_inventory
          # FIX R12-8: stock e NOT NULL în DB, deci folosim 0 (nu nil)
          # Pentru track_inventory=false, stocul 0 e ignorat oricum (se bazează pe stock_status)
          initial_status = track_inv ? "in_stock" : (@product.stock_status || "in_stock")

          begin
            # FIX R10-1: Construim varianta cu option_values ÎNAINTE de save!
            # (altfel validarea option_values_count_invariant pică)
            ActiveRecord::Base.transaction do
              variant = @product.variants.new(
                price: @product.price || 0,
                cost_price: @product.cost_price,
                discount_price: @product.discount_price,
                weight: @product.weight,
                stock: 0,  # FIX R12-8: Stoc 0 inițial (NOT NULL), admin setează după
                stock_status: initial_status,
                track_inventory: track_inv,
                is_master: false,
                sku: generated_sku,
                options_digest: digest
              )
              # FIX R15-1: Setăm flag-ul pentru a permite crearea join-urilor
              # Fără acest flag, before_create pe OptionValueVariant ar bloca salvarea
              variant.allow_option_value_writes = true
              # Atașăm option_values ÎNAINTE de save! pentru a trece validarea
              combo.each { |ov| variant.option_value_variants.build(option_value: ov) }
              variant.save!
            end
            existing_digests.add(digest)
            created += 1
          rescue ActiveRecord::RecordNotUnique
            # Conflict concurent pe digest sau SKU — skip, altcineva a creat-o
            skipped += 1
          end
        end

        { created: created, skipped: skipped }
      ensure
        # FIX R14-7: Unlock cu același namespace (2-key)
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(
            ["SELECT pg_advisory_unlock(42, ?)", @product.id]
          )
        )
      end
    end

    def total_combinations_count
      # FIX R8-8: Un singur query în loc de N (evită N+1)
      # FIX R11-4: Returnează 0 când produsul nu are option_types (nu 1)
      return 0 if @product.option_type_ids.empty?

      counts = OptionValue
        .where(option_type_id: @product.option_type_ids)
        .group(:option_type_id)
        .count
      @product.option_type_ids.map { |id| counts[id] || 0 }.reduce(1, :*)
    end

    private

    # Generare incrementală iterativă (zero risc stack overflow, chiar și cu 15+ option_types)
    def each_combination(arrays)
      return enum_for(:each_combination, arrays) unless block_given?
      return if arrays.empty?
      indices = Array.new(arrays.size, 0)
      loop do
        yield indices.each_with_index.map { |idx, i| arrays[i][idx] }
        pos = indices.size - 1
        while pos >= 0
          indices[pos] += 1
          if indices[pos] < arrays[pos].size
            break
          else
            indices[pos] = 0
            pos -= 1
          end
        end
        break if pos < 0
      end
    end
  end
end
```

**Folosire în controller:**
```ruby
# products_controller.rb
def generate_variants
  generator = Variants::Generator.new(@product)
  count = generator.total_combinations_count

  if count > 200
    # TODO: background job
    redirect_to @product, alert: "Prea multe combinații (#{count}). Generarea va rula în background."
  else
    result = generator.call
    redirect_to @product, notice: "Variante generate: #{result[:created]} noi, #{result[:skipped]} existente."
  end
end
```

**SKU conflict safety:** Gestionat de `before_validation :ensure_unique_sku_within_product` pe Variant (Pas 2).

---

### Pas 5: Frontend — Pagina de produs cu selecție variante

Modificare `show.html.erb`:
1. Dacă produsul `has_variants?` → afișează dropdown-uri/butoane per option type
2. La selectare, actualizează dinamic: preț, stoc, disponibilitate
3. Butonul "Adaugă în coș" trimite `variant_id`
4. Butonul e dezactivat până se selectează toate opțiunile
5. **FIX R12-3 + R12-5:** Preț inițial (înainte de selecție): afișează "De la X RON" filtrat pe variantele **complete** și **disponibile**:
   ```ruby
   # Variantele complete (au toate option_values) și disponibile
   available_complete = @product.variants.non_master.complete.available
   min_price = available_complete.minimum(:price)
   # Fallback: dacă niciuna nu e disponibilă, ia prețul minim din toate completele
   min_price ||= @product.variants.non_master.complete.minimum(:price)
   # Fallback final: dacă nu sunt variante complete, ia master
   min_price ||= @product.master&.price
   ```
   + mesaj "Alegeți opțiunile pentru preț exact"

**Stimulus controller** `variant_select_controller.js`:
- Încarcă un JSON cu toate variantele și combinațiile lor
- La schimbare dropdown → găsește varianta corespunzătoare → actualizează UI
- Dacă combinația nu există → "Indisponibil"
- **FIX R11-2:** Dropdown-urile apar în ordinea `product.product_option_types.order(:position).map(&:option_type)` (poziție per produs, nu globală), valorile în ordinea `option_values.position`

**Format JSON pentru lookup rapid (key = ID-uri sortate, nu name-uri):**
```json
{
  "1-7":  { "id": 2, "price": "49.99", "stock": 10, "sku": "TRI-s-alb",    "display": "S, Alb" },
  "2-7":  { "id": 3, "price": "49.99", "stock": 15, "sku": "TRI-m-alb",    "display": "M, Alb" },
  "4-8":  { "id": 9, "price": "59.99", "stock": 3,  "sku": "TRI-xl-negru", "display": "XL, Negru" }
}
```
Key-ul e compus din `option_value_id`-uri sortate, concatenate cu `-`. Stabil, fără probleme de diacritice/spații/redenumiri. Presentation-ul se folosește doar pentru afișare.

**Preload în controller** pentru evitare N+1:
```ruby
# products_controller.rb#show
# FIX R11-2: Include product_option_types pentru ordinea per produs în display_options
@product = Product.includes(
  :product_option_types,
  variants: { option_values: :option_type },
  option_types: :option_values
).find(params[:id])
```

---

### Pas 6: Cart — Lucru cu variante

Modificare `cart_controller.rb`:
- `session[:cart]` va stoca `variant_id` în loc de `product_id`
- Format: `{ "variant_42" => { "quantity" => 2 } }`
- Verificare stoc pe variantă, nu pe produs
- Afișare în coș: "Tricou Basic — XL, Negru"

**Validare backend anti-master + anti-incompletă + anti-out_of_stock + anti-negative:**
```ruby
# În cart_controller.rb#add
variant = Variant.find(params[:variant_id])
# FIX R15-3: SECURITY — normalizează cantitatea pentru a preveni stoc negativ/crescut
# to_i pe string negativ dă număr negativ → stock = stock - (-5) = stock + 5!
qty = [(params[:quantity] || 1).to_i, 1].max

# FIX R11-1 + R13-3: Refuză variante incomplete (după adăugare option_type nou)
# Folosim metoda complete? care verifică distinct pe option_type_id (detectează și date corupte)
if !variant.is_master? && !variant.complete?
  redirect_to variant.product, alert: "Această variantă nu mai este disponibilă. Selectează opțiunile din nou."
  return
end

if variant.is_master? && variant.product.has_variants?
  redirect_to variant.product, alert: "Selectează opțiunile produsului."
  return
end

# FIX R14-3: Verifică disponibilitatea (inclusiv track_inventory=false + out_of_stock)
# available_for_quantity? folosește regula unificată: track_inventory=true → stock >= qty,
# track_inventory=false → stock_status == "in_stock"
unless variant.available_for_quantity?(qty)
  redirect_to variant.product, alert: "Acest produs nu este disponibil în cantitatea dorită."
  return
end
```
Previne:
- Adăugarea master-ului în coș prin request manual (cineva trimite variant_id = master.id direct)
- **FIX R11-1:** Cumpărarea variantelor incomplete (care au devenit invalide după adăugarea unui nou option_type)
- **FIX R14-3:** Cumpărarea variantelor indisponibile (track_inventory=false + stock_status="out_of_stock")

**Cart cleanup — variante șterse sau indisponibile:**
```ruby
# În prepare_cart_variables (se apelează la fiecare acces al coșului)
# Batch query: 1 query în loc de N (evită N+1)
if session[:cart].present?
  # FIX R14-8: Procesează STRICT doar cheile conforme (variant_\d+)
  # Alte chei (din bug-uri vechi sau schimbări viitoare) sunt ignorate/eliminate
  valid_keys = session[:cart].keys.select { |k| k.match?(/\Avariant_\d+\z/) }
  variant_ids = valid_keys.map { |k| k.sub("variant_", "").to_i }

  existing_ids = Variant.where(id: variant_ids).pluck(:id).to_set
  removed = false
  invalid_keys_removed = false

  session[:cart].select! do |key, _|
    # Elimină cheile non-conforme
    unless key.match?(/\Avariant_\d+\z/)
      invalid_keys_removed = true
      next false
    end

    vid = key.sub("variant_", "").to_i
    exists = existing_ids.include?(vid)
    removed = true unless exists
    exists
  end

  # FIX R8-11: Folosim flash (nu flash.now) pentru a supraviețui redirect-urilor
  flash[:notice] = "Unele produse au fost eliminate din coș (nu mai sunt disponibile)." if removed
  Rails.logger.warn("Cart cleanup: removed invalid keys") if invalid_keys_removed
end
```
Dacă o variantă e ștearsă între timp (admin), coșul se curăță automat la următorul acces.
**FIX R14-8:** Cheile non-conforme (din bug-uri vechi) sunt eliminate silențios cu log warning.

**Migrare cart-uri vechi la deploy:**
```ruby
# În prepare_cart_variables sau la începutul oricărei acțiuni cart
# Detectează format vechi (key numeric = product_id) și convertește la variant_id
if session[:cart].present? && session[:cart].keys.any? { |k| k =~ /\A\d+\z/ }
  # FIX R8-12: Batch query în loc de N query-uri
  old_ids = session[:cart].keys.select { |k| k =~ /\A\d+\z/ }.map(&:to_i)
  products_with_masters = Product.includes(:variants)
    .where(id: old_ids)
    .index_by(&:id)

  # FIX R11-5: Păstrăm cheile variant_* existente (nu le pierdem la migrare)
  new_cart = session[:cart].select { |k, _| k.start_with?("variant_") }
  removed_items = []

  session[:cart].each do |old_id, data|
    next unless old_id =~ /\A\d+\z/
    product = products_with_masters[old_id.to_i]
    next unless product

    # FIX R10-14: Dacă produsul are variante non-master, NU migrăm master-ul în coș
    # (ar fi refuzat la checkout oricum). Îl eliminăm și notificăm user-ul.
    if product.has_variants?
      removed_items << product.name
    else
      # Produs fără variante → OK să folosim master
      variant = product.master
      new_cart["variant_#{variant.id}"] = data if variant
    end
  end
  session[:cart] = new_cart

  if removed_items.any?
    flash[:warning] = "Următoarele produse au fost eliminate din coș (necesită selecție opțiuni): #{removed_items.join(', ')}"
  end
end
```
**Notă R10-14:** Produsele cu variante sunt eliminate din cart-ul vechi (nu migrăm master-ul) și user-ul trebuie să le re-adauge selectând opțiunile. Alternativă: invalidează complet cart-urile vechi (`session[:cart] = {}`).
**FIX R11-5:** Păstrăm cheile `variant_*` existente la migrare — cart-uri mixte (numeric + variant_) nu pierd item-urile deja convertite.

---

### Pas 7: Orders — Creare comenzi cu variante + snapshot

- `order_item` primește `variant_id` pe lângă `product_id`
- **Snapshot la creare:** salvează `unit_price`, `product_name`, `variant_sku`, `variant_options_text`, `vat_rate_snapshot` la momentul comenzii
- Dacă prețul variantei sau rata TVA se schimbă ulterior, comanda rămâne cu valorile originale
- Afișarea comenzilor folosește câmpurile snapshot, independent de existența variantei

```ruby
# La creare order_item:
order_item = order.order_items.create!(
  product: variant.product,
  variant: variant,
  quantity: qty,
  unit_price: variant.price,
  price: variant.price,
  vat: variant.product.vat,
  vat_rate_snapshot: variant.product.vat,   # snapshot rata TVA
  product_name: variant.product.name,
  variant_sku: variant.sku,
  # FIX R12-6: Folosim display_options_fresh pentru snapshot (ordinea garantată prin SQL)
  # display_options normal depinde de preload, care poate lipsi în contextul checkout-ului
  variant_options_text: variant.display_options_fresh  # "Mărime: XL, Culoare: Negru"
)
```

**Validare backend anti-master + anti-incompletă + anti-out_of_stock la creare order:**
```ruby
# În orders_controller.rb#create — pentru fiecare item din cart
variant = Variant.find(variant_id)
qty = cart_data["quantity"].to_i

# FIX R11-1 + R13-3: Refuză variante incomplete (după adăugare option_type nou)
# Folosim metoda complete? care verifică distinct pe option_type_id
if !variant.is_master? && !variant.complete?
  raise ActiveRecord::RecordInvalid, "Variantă incompletă: produsul a fost actualizat, reselectați opțiunile"
end

if variant.is_master? && variant.product.has_variants?
  # Refuză comanda — nu se poate cumpăra master-ul unui produs cu variante
  raise ActiveRecord::RecordInvalid, "Variantă invalidă: selectați opțiunile"
end

# FIX R14-3: Verifică disponibilitatea ÎNAINTE de a crea order_item
# (finalize_order! verifică din nou la decrementare, dar e mai curat să refuzăm devreme)
unless variant.available_for_quantity?(qty)
  raise ActiveRecord::RecordInvalid, "Stoc insuficient pentru #{variant.product.name}"
end
```

**FIX R13-5: Finalizare comandă cu UPDATE atomic (standardizat):**
```ruby
# În Order#finalize_order!
# FIX R13-5: Standardizat pe UPDATE atomic — cea mai robustă abordare
# UPDATE ... WHERE stock >= qty e atomic și imposibil de depășit în high concurrency
ActiveRecord::Base.transaction do
  # FIX R12-7: Agregăm cantitățile per variant_id înainte de decrementare
  aggregated = order_items
    .select(&:variant_id)
    .group_by(&:variant_id)
    .transform_values { |items| items.sum(&:quantity) }

  # Sortare pentru ordine consistentă (util pentru debugging/logging)
  aggregated.keys.sort.each do |variant_id|
    total_qty = aggregated[variant_id]

    # FIX R11-3: UPDATE atomic cu where(track_inventory: true)
    # Nu scădem stoc pe variante fără tracking
    # FIX R14-11: Setează și updated_at pentru cache invalidation / sync / exporturi
    rows = Variant.where(id: variant_id)
                  .where(track_inventory: true)
                  .where("stock >= ?", total_qty)
                  .update_all(["stock = stock - ?, updated_at = ?", total_qty, Time.current])

    # Dacă rows == 0: stoc insuficient SAU track_inventory=false
    if rows == 0
      variant = Variant.find(variant_id)
      if variant.track_inventory?
        raise InsufficientStockError, "Stoc insuficient pentru #{variant.sku}"
      end
      # track_inventory=false → nu trebuie să scădem stoc, continuăm
    end
  end
end
```

**De ce UPDATE atomic:**
- `UPDATE ... WHERE stock >= qty` verifică și decrementează într-un singur statement SQL
- Imposibil de depășit chiar și în high concurrency (atomicitate garantată de DB)
- Nu necesită lock explicit (`SELECT ... FOR UPDATE`) — mai eficient
- Sortarea nu e strict necesară pentru atomicitate, dar ajută la debugging

**Alternativă cu lock explicit (pentru cazuri speciale):**
```ruby
# Dacă ai nevoie să citești alte câmpuri înainte de decrementare
variant = Variant.lock.find(variant_id)  # SELECT ... FOR UPDATE
next unless variant.track_inventory?
raise InsufficientStockError if variant.stock < total_qty
variant.decrement!(:stock, total_qty)
```
Această variantă e mai puțin eficientă dar permite logică complexă înainte de decrementare.

---

## Erori critice adresate (review 1-7)

### 1. CRITIC: Creare automată master variant pentru produse NOI
→ **Rezolvat:** `before_create :build_master_variant` pe Product — salvare atomică cu produsul (Pas 2)

### 2. CRITIC: Generare SKU pentru variante noi
→ **Rezolvat:** Format `PRODUCT_SKU-val1-val2` + `ensure_unique_sku_within_product` (Pas 2, 4)

### 3. CRITIC: Valori default pentru variantele generate
→ **Rezolvat:** Copiază din master (Pas 4)

### 4. CRITIC: Unicitate SKU — strategie
→ **Rezolvat:** SKU unic per produs (`product_id + sku`), nu global (Pas 1d)

### 5. CRITIC: Data migration idempotentă
→ **Rezolvat:** Verifică existența master + toleranță la nil/missing values (Pas 1g)

### 6. CRITIC: Concurență la stoc (oversell)
→ **Rezolvat:** Lock ordonat pe variant_id + tranzacție + alternativă UPDATE atomic (Pas 7)

### 7. CRITIC: Snapshot preț/opțiuni/VAT în order_items
→ **Rezolvat:** Câmpuri `variant_sku`, `variant_options_text`, `vat_rate_snapshot` (Pas 1f, 7)

### 8. CRITIC: Unicitate case-insensitive la DB (citext)
→ **Rezolvat:** Coloanele `name` pe option_types/values sunt `citext`, indexuri unice funcționează case-insensitive automat (Pas 1a, 1b)

### 9. CRITIC: options_digest NULL pentru non-master
→ **Rezolvat:** `options_digest NOT NULL default "MASTER"`, master are "MASTER", non-master au digest calculat, index unic fără WHERE (Pas 1d, 2)

### 10. CRITIC: compute_options_digest fragil (before_save pe join-uri incomplete)
→ **Rezolvat:** Digest setat explicit la creare din generator (`compute_and_set_digest!`), opțiuni write-once, nu se recalculează (Pas 2, 4)

### 11. CRITIC: Generator materializează toate combinațiile în memorie
→ **Rezolvat:** `each_combination` recursiv cu yield (Enumerator), fără Array#product. Digest-uri existente preîncărcate în Set (Pas 4)

### 12. CRITIC: Master nu se vinde — validare backend
→ **Rezolvat:** Check în cart_controller#add și orders_controller#create (Pas 6, 7)

### 13. IMPORTANT: sync_master_attributes cascadă callback-uri
→ **Rezolvat:** `update_columns` în loc de `update!` + guard `relevant_attributes_changed?` + `after_commit` (Pas 2)

### 14. IMPORTANT: Product.destroy eșuează dacă variante au comenzi
→ **Rezolvat:** Documentat + admin trebuie să dezactiveze, nu să șteargă. Controller prinde excepția (Pas 2)

### 15. IMPORTANT: Backward compatibility comenzi vechi
→ **Rezolvat:** Fallback `display_name` cu verificare variant.present? (Pas 2)

### 16. IMPORTANT: Unicitate combinații option_values
→ **Rezolvat:** `options_digest NOT NULL` + index unic DB + preîncărcare digest-uri în generator (Pas 1d, 2, 4)

### 17. IMPORTANT: Unicitate OptionType/OptionValue case-insensitive
→ **Rezolvat:** `citext` + indexuri unice (Pas 1a, 1b)

### 18. IMPORTANT: Frontend key bazat pe name e fragil
→ **Rezolvat:** Key JSON compus din ID-uri sortate (Pas 5)

### 19. IMPORTANT: N+1 pe display_options / listări
→ **Rezolvat:** Preload `includes(variants: { option_values: :option_type })` în controller (Pas 5)

### 20. IMPORTANT: Deadlock la finalize cu mai multe variante
→ **Rezolvat:** Sortare stabilă după variant_id înainte de lock (Pas 7)

### 21. RECOMANDAT: Un singur master per produs
→ **Rezolvat:** Index unic parțial `WHERE is_master = true` la nivel DB (Pas 1d)

### 22. RECOMANDAT: Dependent/restrict pe toate relațiile
→ **Rezolvat:** Tabel complet cu strategii (Pas 2)

### 23. RECOMANDAT: Ștergerea option_value folosite
→ **Rezolvat:** `restrict_with_exception` (Pas 2)

### 24. RECOMANDAT: Logica generator în service, nu controller
→ **Rezolvat:** `Variants::Generator` service object (Pas 4)

### 25. RECOMANDAT: stock_status calculat vs stocat
→ **Planificat pentru migrarea viitoare**
→ **Notă Review 4:** Când `track_inventory = false`, `stock_status` e sursa de adevăr (setat manual de admin). Când `track_inventory = true`, `stock_status` ar trebui derivat din `stock`. Pe termen scurt, admin-ul gestionează ambele; pe termen lung, stock_status devine calculat.

### 26. RECOMANDAT: Performanță JSON variante
→ **Acceptat:** JSON preîncărcat OK pentru <100 variante, AJAX pentru mai mult

### 27. CRITIC (R4): CHECK constraint master ↔ digest bicondiționat
→ **Rezolvat:** `CHECK ((is_master AND options_digest='MASTER') OR (NOT is_master AND options_digest <> 'MASTER'))` (Pas 1d)

### 28. CRITIC (R4): Tranzacție per variantă în generator (create + joins atomic)
→ **Rezolvat:** Fiecare variantă se creează într-un `ActiveRecord::Base.transaction` separat (Pas 4)

### 29. CRITIC (R4): Advisory lock pentru generare concurentă pe același produs
→ **Rezolvat:** `pg_advisory_lock(product_id)` în generator (Pas 4)

### 30. CRITIC (R4): Rescue RecordNotUnique în generator
→ **Rezolvat:** `rescue ActiveRecord::RecordNotUnique` → skip (Pas 4)

### 31. CRITIC (R4): Invariant validări master/non-master option_values count
→ **Rezolvat:** `option_values_count_invariant` pe Variant — master=0, non-master=nr option types (Pas 2)

### 32. IMPORTANT (R4): "De la" preț filtrat pe variante disponibile
→ **Rezolvat:** `.where(stock_status: :in_stock).minimum(:price)` cu fallback (Pas 5)

### 33. IMPORTANT (R4): Cart cleanup pentru variante șterse
→ **Rezolvat:** Verificare `Variant.exists?` în `prepare_cart_variables` (Pas 6)

### 34. RECOMANDAT (R4): Product fără master (auto-repair)
→ **Planificat:** Validare `after_initialize` sau background job periodic. Pe termen scurt, `after_create :create_master_variant` acoperă cazul principal. Edge case (master șters manual din console) — se adaugă la migrarea viitoare.

### 35. RECOMANDAT (R4): Schimbare product.sku nu actualizează variant SKU-uri
→ **Acceptat ca intentionat.** SKU-urile variantelor sunt independente după generare. Documentat.

### 36. CRITIC (R5): Race condition în data migration (workers paraleli)
→ **Rezolvat:** `find_or_create_by!` + `rescue ActiveRecord::RecordNotUnique` (Pas 1g)

### 37. CRITIC (R5): SQL injection în advisory lock
→ **Rezolvat:** `sanitize_sql_array(["SELECT pg_advisory_lock(?)", id])` (Pas 4)

### 38. CRITIC (R5): SKU injection — caractere speciale în option_value.name
→ **Rezolvat:** Sanitizare cu `gsub(/[^a-zA-Z0-9]/, '_')` + truncare bază SKU la 200 chars (Pas 4)

### 39. CRITIC (R5): SQL injection în stock decrement atomic
→ **Rezolvat:** Parameterized query `update_all(["stock = stock - ?", qty])` (Pas 7)

### 40. GRAV (R5): after_create eșuat lasă Product fără master
→ **Rezolvat:** `before_create :build_master_variant` — salvare atomică cu produsul (Pas 2)

### 41. GRAV (R5): Infinite loop în ensure_unique_sku
→ **Rezolvat:** Truncare bază la 200 chars + max 1000 tentative + fallback SecureRandom (Pas 2)

### 42. GRAV (R5): Cart cleanup N+1 queries (N query-uri per request)
→ **Rezolvat:** Batch query `Variant.where(id: ids).pluck(:id).to_set` — 1 query (Pas 6)

### 43. IMPORTANT (R6): display_options N+1 — sort_by forțează materializare fără eager load
→ **Rezolvat:** `.order("option_types.position")` SQL ORDER BY în loc de Ruby `sort_by` (Pas 2)

### 44. CRITIC (R6): Generator crash pe product.sku NULL — NoMethodError pe nil[0..200]
→ **Rezolvat:** `base_sku = (@product.sku.presence || "PROD-#{@product.id}")[0..200]` (Pas 4)

### 45. GRAV (R7): Recursia each_combination → stack overflow la 15+ option_types
→ **Rezolvat:** Înlocuit cu iterator iterativ (indices ca odometru), zero risc stack overflow (Pas 4)

### 46. GRAV (R7): ensure_unique_sku loop cu N query-uri (1 per tentativă)
→ **Rezolvat:** 1 singur query `WHERE sku = ? OR sku LIKE ?` + iterare in-memory (Pas 2)

---

## Corecții Review 8 (consolidat)

### 47. CRITIC (R8-1): sync_master_attributes poate scrie NULL în coloane NOT NULL
→ **Rezolvat:** Fallback-uri explicite pentru sku, price, stock, stock_status, track_inventory (Pas 2)

### 48. CRITIC (R8-2): display_options are bug SQL (ORDER BY pe tabel ne-joinuit)
→ **Rezolvat:** `joins(:option_type)` + `joins("INNER JOIN product_option_types...")` în loc de `includes` (Pas 2)

### 49. CRITIC (R8-3): Inconsecvență position — global vs per-produs
→ **Rezolvat:** Unificat pe `product_option_types.position` peste tot (display_options, generator). Eliminat folosirea `option_types.position` în contexte per-produs (Pas 2, 4)

### 50. MAJOR (R8-4): Coloane permisive la NULL (stock, is_master, etc.)
→ **Rezolvat:** Adăugat `null: false` pe: stock, stock_status, track_inventory, position, is_master (Pas 1d)

### 51. MAJOR (R8-5): Non-master permis când expected==0 (produs fără option types)
→ **Rezolvat:** Validare explicită: `if expected == 0 → errors.add` (Pas 2)

### 52. INFO (R8-6): Index parțial redundant pentru master
→ **Păstrat:** Deși redundant logic (CHECK + unique digest), indexul parțial `WHERE is_master=true` e util pentru query performance pe `product.master` (Pas 1d — comentariu adăugat)

### 53. MAJOR (R8-7): SKU generat poate depăși limita DB
→ **Rezolvat:** Truncare finală la 255 chars + limit explicit în schema (Pas 1d, 4)

### 54. MAJOR (R8-8): total_combinations_count face N query-uri
→ **Rezolvat:** Un singur query GROUP BY în loc de N `count` (Pas 4)

### 55. MAJOR (R8-9): Write-once validation incompletă
→ **Rezolvat:** Compară option_value_ids cu snapshot din DB la update (Pas 2)

### 56. MAJOR (R8-10): Două abordări pentru finalize (lock vs atomic UPDATE)
→ **Standardizat:** Folosim varianta atomică `UPDATE ... WHERE stock >= ?` ca abordare principală. Varianta cu lock e documentată ca alternativă (Pas 7 — deja documentat)

### 57. MEDIU (R8-11): flash.now nu supraviețuiește redirect
→ **Rezolvat:** Folosim `flash[:notice]` în loc de `flash.now` (Pas 6)

### 58. MEDIU (R8-12): Migrare cart-uri vechi face N query-uri
→ **Rezolvat:** Batch query cu `Product.includes(:variants).where(id: ids)` (Pas 6)

### 59. MEDIU (R8-13): DeleteRestrictionError netratată în UI
→ **Documentat:** Controller-ul trebuie să prindă explicit `ActiveRecord::DeleteRestrictionError` și să afișeze mesaj clar (Pas 2 — deja menționat)

### 60. MEDIU (R8-14): external_image_urls poate veni ca string
→ **Rezolvat:** Normalizare cu `Array(...).flatten.compact.map(&:to_s).reject(&:blank?)` (Pas 8d)

### 61. DESIGN (R8-15): Generator copiază din master, dar Product e sursa adevărului
→ **Rezolvat:** Generator copiază acum direct din `@product`, nu din `master` (Pas 4)

### 62. SIMPLIFICARE (R8-16): compute_and_set_digest! nefolosit
→ **Acceptat:** Metodă păstrată pentru debugging/console, dar generator setează digest direct. Documentat ca utilitar, nu ca parte din flow-ul principal.

---

## Corecții Review 9 (consolidat)

### 63. CRITIC (R9-1): SQL raw cu interpolare în display_options
→ **Rezolvat:** `Variant.sanitize_sql_array([...])` în loc de interpolare directă (Pas 2)

### 64. CRITIC (R9-2): N+1 în @variants_json din cauza pluck
→ **Rezolvat:** `.map(&:id)` în loc de `.pluck(:id)` — folosește obiectele preîncărcate (Pas 8f)

### 65. MAJOR (R9-3): SKU overflow după ensure_unique_sku
→ **Rezolvat:** Truncare finală `[0..254]` pe toate căile de ieșire (Pas 2)

### 66. MAJOR (R9-4): is_master poate fi schimbat după creare
→ **Rezolvat:** Validare `is_master_immutable` pe update — blochează `will_save_change_to_is_master?` (Pas 2)

### 67. MAJOR (R9-5): Schimbarea option_types după ce există variante
→ **Rezolvat:** `before_destroy :check_no_variants_exist` pe ProductOptionType — blochează ștergerea option_type dacă există variante non-master (Pas 2)

### 68. MEDIU (R9-6): Validări Rails case-sensitive vs citext
→ **Rezolvat:** `case_sensitive: false` pe validates :name în OptionType și OptionValue (Pas 2)

### 69. INFO (R9-7): option_values_immutable face query extra la update
→ **Acceptat:** Trade-off între siguranță și performanță. Pentru update-uri în masă de stoc, se poate adăuga guard `unless: -> { only_stock_fields_changed? }`.

### 70. INFO (R9-8): display_options depinde de product_option_types (inner join)
→ **Acceptat:** Pentru ordere, folosim `variant_options_text` (snapshot). Pentru afișare live, inner join e corect — dacă admin schimbă option types, variantele vechi trebuie șterse/regenerate oricum.

---

## Corecții Review 10 (consolidat) — Show-stoppers

### 71. CRITIC (R10-1): Generatorul nu poate crea variante — validarea pică la create!
→ **Rezolvat:** Folosim `variants.new()` + `option_value_variants.build()` ÎNAINTE de `save!` (Pas 4)

### 72. CRITIC (R10-2): Generatorul crapă dacă un option_type nu are valori
→ **Rezolvat:** `return { error: "..." } if option_values_arrays.any?(&:empty?)` (Pas 4)

### 73. CRITIC (R10-3): track_inventory/stock_status ignorate la generare
→ **Rezolvat:** Copiază `track_inventory` din produs; `stock_status` consistent cu politica (Pas 4)

### 74. CRITIC (R10-4): display_options produce N+1 inevitabil (bypasses preload)
→ **Rezolvat:** Două metode: `display_options` (folosește preload, sortare Ruby) și `display_options_fresh` (query explicit pentru jobs/emails) (Pas 2)

### 75. CRITIC (R10-5): Lipsește "maxim 1 option_value per option_type"
→ **Rezolvat:** Validare `one_value_per_option_type` pe create pentru non-master (Pas 2)

### 76. MAJOR (R10-6): Ordinea option types în frontend inconsistentă cu backend
→ **Documentat:** Frontend trebuie să itereze `product.product_option_types.order(:position).map(&:option_type)` (Pas 5 — clarificat)

### 77. DOC (R10-7): "Copiem din master" vs "copiem din Product" — inconsecvență
→ **Aliniat:** Documentație actualizată — generator copiază din `@product` (nu din master). Master e doar mirror.

### 78. DOC (R10-8): finalize_order! — exemplul principal contrazice "standardizat pe atomic"
→ **Clarificat:** Pas 7 menține ambele variante documentate; recomandăm atomic UPDATE, dar lock+decrement e alternativă validă.

### 79. MAJOR (R10-9): options_digest poate depăși 255 chars (t.string)
→ **Rezolvat:** Schimbat în `t.text` (Pas 1d)

### 80. MAJOR (R10-10): Non-master digest="MASTER" dă eroare DB, nu Rails
→ **Rezolvat:** Validare `non_master_digest_valid` pentru feedback curat (Pas 2)

### 81. DEAD CODE (R10-11): ProductOptionType#check_no_variants_on_create e gol
→ **Rezolvat:** Eliminat dead code (Pas 2)

### 82. REDUNDANȚĂ (R10-12): Dublă sortare option_values
→ **Rezolvat:** Eliminat `sort_by(:position)` în generator — has_many scope face deja ORDER BY (Pas 4)

### 83. BUG (R10-13): LIKE fără escape pentru % și _
→ **Rezolvat:** `Variant.sanitize_sql_like(base)` (Pas 2)

### 84. BUG (R10-14): Migrare cart vechi → master pe produse cu variante blochează checkout
→ **Rezolvat:** Eliminăm produsele cu variante din cart vechi + mesaj warning (Pas 6)

### 85. ROBUSTEȚE (R10-15): update_variant_images nu verifică rezultatul update
→ **Acceptat:** Pentru imagini, eșecul silențios e acceptabil (nu blochează fluxul). Opțional: log warning.

---

## Corecții Review 11 (consolidat) — Pre-producție

### 86. CRITIC (R11-1): Variante incomplete pot fi cumpărate după adăugare option_type
→ **Rezolvat:** Validare în cart_controller#add și orders_controller#create: `variant.option_values.count != variant.product.option_types.count` → refuz (Pas 6, 7)

### 87. CRITIC (R11-2): Ordinea per-produs nu e garantată în UI și snapshot
→ **Rezolvat:**
  - UI: iterează `product.product_option_types.order(:position).map(&:option_type)` (Pas 5)
  - Preload: include `product_option_types` în controller#show (Pas 5)
  - display_options folosește corect `pot_positions` când e preîncărcat

### 88. CRITIC (R11-3): Atomic finalize scade stocul pe variante cu track_inventory=false
→ **Rezolvat:** `where(track_inventory: true)` în UPDATE atomic + verificare post-update (Pas 7)

### 89. MAJOR (R11-4): total_combinations_count returnează 1 când produsul nu are option_types
→ **Rezolvat:** `return 0 if @product.option_type_ids.empty?` (Pas 4)

### 90. MEDIU (R11-5): Migrare cart vechi pierde cheile variant_* la conversie
→ **Rezolvat:** `new_cart = session[:cart].select { |k, _| k.start_with?("variant_") }` înainte de procesare (Pas 6)

---

## Corecții Review 12 (consolidat) — Probleme sistemice

### 91. CRITIC (R12-1): sync_master_attributes suprascrie stocul decrementat la checkout
→ **Rezolvat:** `sync_master_attributes` NU mai sincronizează stock/stock_status/track_inventory.
  - Variant e sursa adevărului pentru inventar
  - Product rămâne sursă pentru atribute de catalog (preț, SKU, weight)
  - Checkout decrementează variant.stock, iar Product.update nu mai suprascrie (Pas 2)

### 92. CRITIC (R12-2): Write-once pe opțiuni se poate ocoli prin join model
→ **Rezolvat:** `before_create` și `before_destroy` pe OptionValueVariant verifică `variant.new_record?`
  - `variant.option_values << ov` pe variantă persistată → blocat
  - `variant.option_value_variants.destroy_all` → blocat
  - Singura cale de modificare: generator (când varianta e nouă) (Pas 2)

### 93. MAJOR (R12-3): Disponibilitate inconsistentă (stock vs stock_status vs track_inventory)
→ **Rezolvat:** Regulă unificată:
  - `track_inventory=true` → disponibil dacă `stock > 0`
  - `track_inventory=false` → disponibil dacă `stock_status == "in_stock"`
  - Adăugat scope `available` și metode `available?`, `available_for_quantity?(qty)` pe Variant (Pas 2)

### 94. MAJOR (R12-4): ProductOptionType.before_destroy blochează Product.destroy (cascadă)
→ **Rezolvat:** Guard `return if product.destroyed? || product.marked_for_destruction?` (Pas 2)

### 95. MAJOR (R12-5): Variante incomplete apar în "De la" și JSON
→ **Rezolvat:** Adăugat scope `complete` pe Variant + folosit în:
  - "De la X RON": `variants.non_master.complete.available.minimum(:price)`
  - JSON export (opțional)
  - Adăugat metodă `complete?` pe instanță (Pas 2, 5)

### 96. MAJOR (R12-6): Snapshot variant_options_text poate avea ordine greșită
→ **Rezolvat:** La creare order_item folosim `variant.display_options_fresh` (SQL) în loc de `display_options` (care depinde de preload) (Pas 7)

### 97. MEDIU (R12-7): finalize_order! nu agregă cantitățile per variant
→ **Rezolvat:** `group_by(&:variant_id).transform_values { |items| items.sum(&:quantity) }` înainte de decrementare (Pas 7)

### 98. MIC (R12-8): Comentariu `initial_stock = nil` contrazice schema NOT NULL
→ **Rezolvat:** Eliminat variabila `initial_stock`, folosim direct `stock: 0` în generator (Pas 4)

---

## Corecții Review 13 (consolidat) — Erori logice blocante

### 99. CRITIC (R13-1): Write-once pe OptionValueVariant blochează ștergerea variantelor
→ **Rezolvat:** Adăugat `return if destroyed_by_association.present?` în callback
  - Permite cascade destroy (variant.destroy → join-uri șterse automat)
  - Blochează în continuare modificări directe (`variant.option_values << ov`) (Pas 2)

### 100. CRITIC (R13-2): ProductOptionType.before_destroy poate bloca Product.destroy
→ **Rezolvat:** Înlocuit guard-ul fragil (`product.destroyed?`) cu `destroyed_by_association.present?`
  - Robust: Rails setează acest flag corect în cascade (Pas 2)

### 101. MAJOR (R13-3): Verificare "variantă completă" poate da fals-pozitiv cu date corupte
→ **Rezolvat:** `complete?` compară acum `option_values.map(&:option_type_id).uniq.sort` cu `product.option_type_ids.sort`
  - Detectează corect variante cu 2 valori din același option_type dar lipsește alt tip
  - Cart/order validation folosește `variant.complete?` în loc de count simplu (Pas 2, 6, 7)

### 102. MAJOR (R13-4): SKU master "PROD-TEMP-xxx" rămâne temporar dacă produsul nu are SKU
→ **Rezolvat:** `after_commit :normalize_master_sku, on: :create`
  - Dacă product.sku e blank și master.sku începe cu "PROD-TEMP-", se normalizează la "PROD-{id}" (Pas 2)

### 103. DESIGN (R13-5): Documentare inconsistentă lock vs atomic UPDATE
→ **Rezolvat:** Standardizat pe UPDATE atomic ca implementare principală
  - `UPDATE ... WHERE stock >= qty` e atomic și imposibil de depășit
  - Lock explicit documentat ca alternativă pentru cazuri speciale (Pas 7)

### 104. PERFORMANȚĂ (R13-6): `product.master` poate face query chiar cu includes
→ **Rezolvat:** `master` verifică acum `association(:variants).loaded?`
  - Dacă variantele sunt preîncărcate, folosește `variants.detect(&:is_master?)`
  - Altfel face query normal (Pas 2)

---

## Corecții Review 14 (consolidat) — Bug-uri subtile dar grave

### 105. SHOW-STOPPER (R14-1): OptionValueVariant `before_create` blochează generatorul
→ **Rezolvat:** Eliminat `before_create` — write-once înseamnă "nu modifica DUPĂ creare"
  - Rails salvează variant-ul (devine persisted) ÎNAINTE de join-uri
  - În acel moment `variant.new_record?` e false → callback bloca salvarea join-urilor
  - Păstrăm doar `before_destroy` pentru protecție write-once (Pas 2)

### 106. SHOW-STOPPER (R14-2): Scope `complete` cu GROUP BY sparge `.minimum(:price)`
→ **Rezolvat:** Înlocuit GROUP BY + HAVING cu subquery WHERE NOT EXISTS
  - GROUP BY face ca `.minimum(:price)` să returneze Hash, nu scalar
  - "De la X RON" afișa hash sau crăpa la formatare
  - Noua implementare păstrează relation-ul "flat" (Pas 2)

### 107. CRITIC (R14-3): `track_inventory=false` + `out_of_stock` poate trece checkout
→ **Rezolvat:** Verificare `available_for_quantity?(qty)` în cart și orders controller
  - `finalize_order!` nu blochează explicit variantele fără tracking
  - Acum verificăm disponibilitatea ÎNAINTE de a crea order_item (Pas 6, 7)

### 108. MAJOR (R14-4): JSON frontend lipsește `track_inventory` / `available`
→ **Rezolvat:** Adăugat în JSON: `track_inventory`, `stock_status`, `available` (calculat server-side)
  - UI poate afișa corect disponibilitatea pentru toate tipurile de variante (Pas 5)

### 109. MAJOR (R14-5): `Product.sku` > 255 chars sparge `sync_master_attributes`
→ **Rezolvat:**
  - Validare `validates :sku, length: { maximum: 255 }` pe Product
  - Trunchiere `.to_s[0..254]` în `sync_master_attributes` și `build_master_variant`
  - Previne excepții DB în `after_commit` (Pas 2)

### 110. MAJOR (R14-6): `BigDecimal#to_s` poate produce notație științifică
→ **Rezolvat:** Folosim `.to_s("F")` în JSON pentru preț
  - `BigDecimal("49.99").to_s` poate returna "0.4999E2" în unele cazuri
  - `.to_s("F")` garantează format fix "49.99" (Pas 5)

### 111. MAJOR (R14-7): Advisory lock fără timeout + risc coliziune namespace
→ **Rezolvat:**
  - Înlocuit `pg_advisory_lock` cu `pg_try_advisory_lock` (non-blocking)
  - Adăugat namespace (2-key lock): `pg_try_advisory_lock(42, product_id)`
  - Returnează eroare clară dacă lock-ul e ocupat (Pas 4)

### 112. MEDIU (R14-8): Cart cleanup procesează chei non-standard
→ **Rezolvat:** Validare strictă `key.match?(/\Avariant_\d+\z/)`
  - Cheile non-conforme sunt eliminate silențios cu log warning
  - Previne conversii accidentale la "variant_0" (Pas 6)

### 113. MEDIU (R14-9): `has_variants?` face query chiar cu `includes`
→ **Rezolvat:** Verifică `association(:variants).loaded?` înainte de query
  - Folosește `variants.any? { |v| !v.is_master? }` când e loaded
  - Evită N+1 în migrare cart și alte contexte cu preload (Pas 2)

### 114. MEDIU (R14-10): Master poate primi `option_values` (invariant nesecurizat)
→ **Rezolvat:** Validare `master_cannot_have_options` pe `OptionValueVariant`
  - Blochează explicit `master.option_values << ov` la nivel de join model
  - Complementează validarea existentă de pe Variant (Pas 2)

### 115. MEDIU (R14-11): `update_all` nu setează `updated_at` pe Variant
→ **Rezolvat:** Adăugat `updated_at = ?` în UPDATE atomic
  - Permite cache invalidation, sync-uri incremental, exporturi
  - Stoc modificat dar `updated_at` neschimbat era invizibil pentru unele sisteme (Pas 7)

---

## Ordine de execuție

1. **Pas 1** — Migrări (fundația + citext + options_digest NOT NULL)
2. **Pas 2** — Modele (relații, validări, callback-uri, write-once, update_columns)
3. **Pas 3** — Admin option types (CRUD simplu)
4. **Pas 4** — Admin variante pe produs (Variants::Generator service + editare inline)
5. **Pas 5** — Frontend selecție variante (preload + JSON lookup)
6. **Pas 6** — Cart cu variante (anti-master backend)
7. **Pas 7** — Orders cu variante (snapshot + lock ordonat + UPDATE atomic)
8. **Pas 8** — Cleanup și migrare date vechi

---

## Verificare / Testare

1. Creează un option type "Mărime" cu valori S, M, L, XL din admin
2. Încearcă duplicat option type "marime" (lowercase) → eroare unicitate (citext)
3. Încearcă duplicat option value "s" pe "Mărime" → eroare unicitate (citext)
4. Creează un produs "Tricou Test" → verifică că master variant s-a creat automat cu digest "MASTER"
5. Atașează option type "Mărime" la produs
6. Generează variantele → verifică 4 variante + 1 master, fiecare cu SKU unic și options_digest
7. Generează din nou → nu se creează duplicate (digest existent)
8. Setează prețuri diferite pe XL (59.99) vs restul (49.99)
9. Pe frontend, selectează XL → verifică că prețul se schimbă
10. Verifică că butonul "Adaugă în coș" e dezactivat fără selecție
11. Adaugă în coș → verifică că variant_id e salvat
12. Încearcă POST manual cu variant_id = master.id pe produs cu variante → refuzat
13. Finalizează comanda → verifică variant_id, variant_sku, variant_options_text, vat_rate_snapshot, stocul decrementat
14. Schimbă prețul variantei → comanda veche păstrează prețul original (snapshot)
15. Schimbă rata TVA → comanda veche păstrează TVA original (vat_rate_snapshot)
16. Testează un produs FĂRĂ variante → funcționează ca înainte (master only)
17. Vizualizează o comandă veche (variant_id = null) → afișaj corect cu fallback
18. Încearcă să ștergi o option_value folosită → eroare restrict
19. Încearcă să ștergi un option_type atașat la produse → eroare restrict
20. Încearcă să ștergi o variantă cu comenzi → eroare restrict
21. Încearcă să ștergi un produs cu variante comandate → eroare restrict (mesaj clar)
22. Două comenzi simultane pe ultima bucată din stoc → doar una reușește (lock)
23. Editare produs (price) → master se sincronizează automat (update_columns)
24. Rulează data migration de două ori → idempotentă, fără duplicate
25. User cu cart vechi (product_id) accesează site-ul post-deploy → cart migrat automat sau resetat
26. Pagina produs cu variante arată "De la X RON" înainte de selecție
27. Creează variantă din rails console cu combinație duplicată → eroare (options_digest unic DB)
28. Creează variantă non-master fără digest → eroare NOT NULL
29. Generare >200 combinații → warning sau background job
30. Încearcă editare opțiuni pe variantă existentă → eroare (write-once)
31. Creează master variant cu option_values → eroare (invariant: master=0 option values)
32. Creează non-master variant cu nr greșit de option_values → eroare (invariant)
33. Creează variantă `is_master=true` cu digest != "MASTER" → eroare CHECK constraint DB
34. Creează variantă `is_master=false` cu digest = "MASTER" → eroare CHECK constraint DB
35. Doi admini generează variante simultan pe același produs → advisory lock, niciun duplicat
36. Generare cu SKU/digest conflict concurent → RecordNotUnique rescued, skip
37. Variantă din coș e ștearsă de admin → la acces coș, se elimină automat + mesaj
38. "De la" preț pe produs cu variante out_of_stock → fallback pe toate variantele
39. Data migration rulată pe 2 workers simultan → niciun duplicat master (find_or_create_by + rescue)
40. Option value cu nume "S-M" sau caractere speciale → SKU generat cu underscore, fără ambiguitate
41. Product.create! cu validare eșuată pe master → rollback complet, nici produs nici master
42. SKU bază de 250+ caractere → nu produce infinite loop, fallback SecureRandom
43. Coș cu 50 variante → cleanup face 1 query DB, nu 50
44. `Variant.find(x).display_options` fără preload → verifică 1 query în logs (nu N+1)
45. Product fără SKU (nil) → generare variante funcționează, SKU format "PROD-{id}-..."
46. Produs cu 15+ option_types → generare variante fără stack overflow (iterator iterativ)
47. Produs cu 5000+ variante → ensure_unique_sku face 1 query DB, nu 5000

### Teste noi din Review 8:
48. Product.update cu price=nil → master.price rămâne valid (fallback, nu NOT NULL violation)
49. Product.update cu sku="" → master.sku rămâne valid (fallback la "PROD-{id}")
50. `variant.display_options` → ordinea respectă `product_option_types.position`, nu `option_types.position`
51. Variant.update cu stock=NULL direct în DB → eroare NOT NULL constraint
52. Creează non-master pe produs FĂRĂ option types → eroare "Produsul nu are option types"
53. Generator pe produs cu 10 option types × 5 valori → SKU-uri trunriate la 255 chars
54. `generator.total_combinations_count` → verifică 1 query în logs (nu N)
55. Schimbă option_value_ids pe variantă existentă → eroare "Opțiunile nu pot fi modificate"
56. Cart cleanup după redirect → mesajul flash apare (nu se pierde)
57. Migrare cart vechi cu 100 produse → max 2 query-uri (batch), nu 100
58. `update_variant_images` cu params[:external_image_urls] = "single_string" → funcționează (normalizat la array)

### Teste noi din Review 9:
59. `variant.display_options` cu product_id=nil → nu crăpă (sanitize_sql_array safe)
60. Produs cu 200 variante → @variants_json face 1 query pentru option_values (nu 200)
61. SKU generat cu sufix `-1234` pe bază de 250 chars → SKU final max 255 chars
62. `variant.update!(is_master: true)` pe non-master → eroare "nu se poate modifica"
63. Șterge ProductOptionType când există variante → eroare "Nu poți elimina..."
64. Creează OptionType "SIZE" când există "size" → eroare unicitate Rails (case-insensitive)
65. Creează OptionValue "XL" pe option_type care are "xl" → eroare unicitate Rails

### Teste noi din Review 10 (show-stoppers):
66. Generator pe produs cu 2 option types (Mărime, Culoare) → variantele se creează fără eroare validare
67. Generator pe produs cu option_type "Mărime" fără valori → return `{ error: "..." }`, nu crash
68. Generator pe produs cu `track_inventory=false` → variantele moștenesc `track_inventory=false`
69. Produs cu 100 variante + includes → `display_options` face 0 query-uri suplimentare
70. Variantă cu 2 valori din același option_type → eroare "nu poate avea mai multe valori"
71. Non-master cu `options_digest="MASTER"` → eroare Rails (nu doar DB CHECK)
72. SKU cu caractere `%` sau `_` → ensure_unique_sku funcționează corect (escape LIKE)
73. Cart vechi cu produs care acum are variante → eliminat din cart + warning, nu blocat la checkout
74. options_digest de 500+ caractere → salvat OK (t.text, nu t.string)

### Teste noi din Review 11 (pre-producție):
75. Adaugă option_type nou pe produs cu variante → variantele vechi au mai puține option_values decât option_types
76. Încearcă să adaugi variantă incompletă în coș (POST direct) → refuzat cu mesaj "nu mai este disponibilă"
77. Încearcă să creezi comandă cu variantă incompletă → refuzat cu mesaj "reselectați opțiunile"
78. UI dropdown-uri → ordinea respectă `product_option_types.position`, nu `option_types.position`
79. `variant.display_options` cu preload `product_option_types` → ordinea corectă per produs
80. `generator.total_combinations_count` pe produs FĂRĂ option_types → returnează 0 (nu 1)
81. Atomic finalize pe variantă cu `track_inventory=false` → stocul NU se decrementează
82. Atomic finalize pe variantă cu `track_inventory=true` și stoc suficient → stocul se decrementează
83. Cart mixt (chei numerice + variant_*) la migrare → cheile variant_* se păstrează
84. Cart cu 3 chei numerice + 2 chei variant_* → după migrare, cheile variant_* există + cele numerice convertite/eliminate

### Teste noi din Review 12 (probleme sistemice):
85. Vinde produs (master) → variant.stock scade → Product.update(price: X) → variant.stock NU se resetează
86. `sync_master_attributes` NU include stock/stock_status/track_inventory în update_columns
87. `variant.option_values << OptionValue.first` pe variantă persistată → eroare "Nu se pot modifica"
88. `variant.option_value_variants.destroy_all` pe variantă persistată → eroare "Nu se pot modifica"
89. Generator: `variant.option_value_variants.build()` pe variantă nouă → funcționează
90. `Variant.available` scope → returnează doar variantele cu stoc > 0 (track_inventory=true) sau in_stock (track_inventory=false)
91. `variant.available?` pe variantă cu track_inventory=true și stock=0 → false
92. `variant.available?` pe variantă cu track_inventory=false și stock_status="out_of_stock" → false
93. `variant.available_for_quantity?(5)` pe variantă cu stock=3 → false
94. `Product.destroy` pe produs cu variante (fără comenzi) → șterge product_option_types + variante fără erori
95. `ProductOptionType.destroy` când product e marcat pentru distrugere → nu blochează
96. `Variant.complete` scope → exclude variantele incomplete (după adăugare option_type)
97. `variant.complete?` pe variantă cu 2 option_values când produsul are 3 option_types → false
98. "De la X RON" pe produs cu variante incomplete → ia prețul doar din variantele complete și disponibile
99. Snapshot `variant_options_text` → folosește `display_options_fresh` (ordine garantată SQL)
100. `finalize_order!` cu 2 order_items pentru același variant → agregă cantitățile, decrementează o singură dată
101. Generator creează variante cu `stock: 0` (nu nil) → salvare OK (NOT NULL respectat)

### Teste noi din Review 13 (erori logice blocante):
102. `variant.destroy` pe variantă non-master fără comenzi → șterge varianta + join-urile (cascade)
103. `variant.destroy` → join-urile se șterg automat (destroyed_by_association permite)
104. `Product.destroy` pe produs cu variante + product_option_types → șterge totul fără blocare
105. Variantă cu 2 option_values din același option_type → `complete?` returnează false
106. Variantă cu option_values din 2 option_types când produsul are 3 → `complete?` returnează false (count egal!)
107. Cart: variantă cu date corupte (2 valori din același tip) → refuzată cu `!variant.complete?`
108. Produs creat fără SKU → master SKU se normalizează la "PROD-{id}" după create
109. Produs creat cu SKU → master SKU rămâne cel specificat (nu se normalizează)
110. `Product.includes(:variants).first.master` → folosește colecția încărcată, 0 query-uri
111. `Product.find(id).master` → face query normal (asociere neîncărcată)
112. `finalize_order!` cu UPDATE atomic → verifică 1 UPDATE per variant în logs
113. Două comenzi simultane, ultima bucată → UPDATE atomic refuză a doua corect

### Teste noi din Review 14 (bug-uri subtile dar grave):
114. Generator pe produs cu 2 option types → variantele se creează fără eroare (before_create nu mai blochează)
115. `variant.option_value_variants.build(...)` pe variantă nouă → salvare OK
116. `variant.option_value_variants.destroy_all` pe variantă persistată → eroare write-once
117. `@product.variants.non_master.complete.available.minimum(:price)` → returnează BigDecimal, nu Hash
118. Scope `complete` urmat de `.count` → returnează Integer, nu Hash
119. Variantă cu `track_inventory=false` și `stock_status="out_of_stock"` → refuzată la add to cart
120. Variantă indisponibilă → refuzată la creare comandă cu mesaj clar
121. JSON frontend conține `available: true/false` calculat server-side
122. JSON frontend: preț "49.99" (format fix), nu "0.4999E2" (scientific)
123. Product.sku de 300 chars → validare eșuează "is too long"
124. `sync_master_attributes` pe produs cu SKU de 300 chars → master.sku = primele 255 chars
125. `build_master_variant` pe produs cu SKU lung → SKU trunchiat la 255 chars
126. Generator pe produs când alt request generează simultan → returnează `{ error: "Generare în curs..." }`
127. Advisory lock folosește namespace 42 (2-key) → nu colizionează cu alte lock-uri
128. Cart cu cheie "invalid_key" → eliminată silențios, log warning
129. Cart cu cheie "variant_abc" (non-numeric) → eliminată silențios
130. `Product.includes(:variants).first.has_variants?` → folosește colecția încărcată, 0 query-uri
131. `master.option_values << OptionValue.first` → eroare "Master variant nu poate avea option values"
132. `finalize_order!` → UPDATE atomic setează și `updated_at` pe Variant
133. Export incremental bazat pe `updated_at` → vede modificările de stoc

---

## Pas 8: Imagini per Variant (Bunny CDN)

Sistemul existent de imagini (Bunny CDN cu presigned URLs) se păstrează și se extinde la variante.

### 8a. Migrare: `add_images_to_variants`

```ruby
add_column :variants, :external_image_url, :string           # Imagine principală variantă
add_column :variants, :external_image_urls, :text, array: true, default: []  # Galerie variantă
```

**Nu adăugăm `external_file_urls` pe variante** — fișierele atașate (PDF, manuale) rămân la nivel de produs.

### 8b. Model Variant — adăugări pentru imagini

```ruby
# În app/models/variant.rb

# Fallback la imaginile produsului dacă varianta nu are poze proprii
def main_image_url
  external_image_url.presence || product.external_image_url
end

def gallery_image_urls
  if external_image_urls.present?
    external_image_urls
  else
    product.external_image_urls || []
  end
end

def all_image_urls
  [main_image_url, *gallery_image_urls].compact.uniq
end

def has_own_images?
  external_image_url.present? || external_image_urls.present?
end
```

### 8c. Formular admin — imagini pe variantă

Extindere tabel variante din `_form.html.erb` cu butoane pentru upload imagini per variantă.

**Opțiunea 1: Inline în tabel (pentru puține variante)**
- Fiecare rând din tabelul de variante are un buton "📷 Poze"
- Click deschide un modal cu același UI de upload (imagine principală + galerie)
- Reutilizează exact același JavaScript pentru presigned URLs

**Opțiunea 2: Pagină separată per variantă (pentru multe variante)**
- Link "Editează" pe fiecare variantă → pagină dedicată cu formular complet
- Include secțiunea de imagini identică cu cea de pe produs

**Recomandare:** Opțiunea 1 pentru UX mai rapid, cu lazy-load al modalului.

**JavaScript reutilizat:**
```javascript
// Același pattern ca pe produs, parametrizat pentru variant_id
async function uploadVariantImage(variantId, file, type) {
  const res = await fetch(`/uploads/presign?filename=${encodeURIComponent(file.name)}`);
  const { upload_url, headers } = await res.json();

  const upload = await fetch(upload_url, {
    method: "PUT",
    headers: { "Content-Type": headers["Content-Type"], "AccessKey": headers["AccessKey"] },
    body: file
  });

  if (upload.ok) {
    const path = new URL(upload_url).pathname.split('/').slice(2).join('/');
    const cdnUrl = `https://ayus-cdn.b-cdn.net/${path}`;

    // Actualizează hidden input-ul corect pentru această variantă
    if (type === 'main') {
      document.getElementById(`variant_${variantId}_image_url`).value = cdnUrl;
    } else {
      addToVariantGallery(variantId, cdnUrl);
    }
  }
}
```

**Hidden inputs în formular:**
```erb
<% @product.variants.non_master.each do |variant| %>
  <input type="hidden"
         name="variants[<%= variant.id %>][external_image_url]"
         id="variant_<%= variant.id %>_image_url"
         value="<%= variant.external_image_url %>" />

  <% (variant.external_image_urls || []).each do |url| %>
    <input type="hidden"
           name="variants[<%= variant.id %>][external_image_urls][]"
           value="<%= url %>" />
  <% end %>
<% end %>
```

### 8d. Controller — salvare imagini variante

```ruby
# În products_controller.rb#update
def update
  # ... logica existentă ...

  if @product.update(product_params)
    # Actualizare imagini pe variante
    update_variant_images if params[:variants].present?

    # ... restul ...
  end
end

private

def update_variant_images
  params[:variants].each do |variant_id, variant_params|
    variant = @product.variants.find_by(id: variant_id)
    next unless variant

    # FIX R8-14: Normalizează la array (poate veni ca string în unele cazuri)
    urls = Array(variant_params[:external_image_urls])
      .flatten
      .compact
      .map(&:to_s)
      .reject(&:blank?)

    variant.update(
      external_image_url: variant_params[:external_image_url].presence,
      external_image_urls: urls
    )
  end
end
```

### 8e. Frontend — afișare imagini variantă

Modificare `show.html.erb` + Stimulus controller:

```javascript
// În variant_select_controller.js
updateImages(variantData) {
  const mainImg = document.getElementById('product-main-image');
  const gallery = document.getElementById('product-gallery');

  // Dacă varianta are imagine proprie, o folosim; altfel fallback la produs
  if (variantData.main_image_url) {
    mainImg.src = variantData.main_image_url;
  }

  if (variantData.gallery_urls && variantData.gallery_urls.length > 0) {
    this.renderGallery(variantData.gallery_urls);
  }
}
```

**JSON pentru variante extins:**
```json
{
  "1-7": {
    "id": 2,
    "price": "49.99",
    "stock": 10,
    "sku": "TRI-s-alb",
    "display": "S, Alb",
    "main_image_url": "https://ayus-cdn.b-cdn.net/variants/tri-s-alb.jpg",
    "gallery_urls": ["https://ayus-cdn.b-cdn.net/variants/tri-s-alb-2.jpg"]
  }
}
```

### 8f. Preload imagini în controller

```ruby
# products_controller.rb#show — extindere preload
# FIX R11-2: Include product_option_types pentru ordinea per produs în display_options
@product = Product.includes(
  :product_option_types,
  variants: { option_values: :option_type },
  option_types: :option_values
).find(params[:id])

# JSON pentru frontend include și URL-uri imagini
# FIX R9-2: Folosim .map(&:id) pe obiectele preîncărcate, NU pluck (care face query separat)
# FIX R14-4: Includem track_inventory, stock_status, available pentru UI corect
# FIX R14-6: Folosim to_s("F") pentru BigDecimal (evită notație științifică "0.4999E2")
@variants_json = @product.variants.non_master.map do |v|
  {
    key: v.option_values.map(&:id).sort.join("-"),  # folosește preload, nu pluck!
    id: v.id,
    price: v.price&.to_s("F"),              # FIX R14-6: format fix, nu scientific
    discount_price: v.discount_price&.to_s("F"),
    stock: v.stock,
    sku: v.sku,
    display: v.display_options,
    # FIX R14-4: Info disponibilitate pentru UI
    track_inventory: v.track_inventory,
    stock_status: v.stock_status,
    available: v.available?,                 # calculat server-side
    main_image_url: v.main_image_url,        # Cu fallback
    gallery_urls: v.gallery_image_urls       # Cu fallback
  }
end.to_json
```

---

## Verificare suplimentară (imagini variante)

48. Creează variantă fără imagini → afișează imaginile produsului (fallback)
49. Adaugă imagine pe variantă "XL Negru" → selectând XL Negru se schimbă imaginea
50. Șterge imaginea variantei → revine la fallback (imaginea produsului)
51. Variantă cu galerie proprie → galeria se actualizează la selecție
52. Upload imagine pe variantă → same flow Bunny CDN, URL salvat corect
53. Editare produs → imaginile variantelor se păstrează

---

## Migrare viitoare (după stabilizare)

- Elimină câmpurile duplicate de pe Product (price, stock, sku) și delegă complet la master variant
- Înlocuiește stock_status stocat cu metodă calculată
- Soft delete pe Variant și Product (câmp `deleted_at`) pentru istoric complet
- Adaugă tabel `prices` pentru multi-currency (dacă e nevoie la licențiere)
- Adaugă `stock_locations` + `stock_items` pentru multi-warehouse
- SKU global unic (dacă integrare ERP) — index suplimentar pe `variants.sku`

# PLAN VARIANTE V5.2.1 - Relaxed Enterprise (Final)

## Filozofie: Libertate totală pentru Admin (ca WooCommerce/Shopify/Solidus)

**CE POATE FACE ADMIN-UL:**
- ✅ Creare variantă nouă - oricând
- ✅ Dezactivare variantă - oricând
- ✅ Reactivare variantă - oricând
- ✅ Schimbare preț/stock/SKU - oricând
- ✅ Schimbare combinație opțiuni - oricând
- ✅ Creare variantă default pe produs cu opțiuni - permis
- ✅ Multiple draft-uri (variante inactive) - permis
- ✅ Adăugare/scoatere option_types - oricând

**CE PROTEJEAZĂ SISTEMUL (invariante critice):**
- ❌ Două variante ACTIVE cu aceeași combinație (unicitate)
- ❌ Checkout pe variantă inactive sau fără stoc (atomic check)
- ❌ Modificare comandă după plasare (snapshot imutabil)
- ❌ Stoc/preț negativ sau NULL (CHECK constraints)

---

## CHANGELOG V4.2 → V5.2.1

### Fix 9: validates :stock cu presence: true
**Problema:** Model-ul avea validare numerică pe stock, dar fără `presence`. Înainte de M3, puteai salva `stock: nil`. După M3, CHECK constraint respinge NULL → eroare SQL, nu mesaj user-friendly.

**Fix:** Adaugă `presence: true` pentru aliniere cu invarianta #7:
```ruby
# ÎNAINTE (V4.2):
validates :stock, numericality: { greater_than_or_equal_to: 0 }

# DUPĂ (V5.0):
validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0 }
```

### Fix 10: CreateOrReactivate respectă multiple draft-uri pentru același digest
**Problema:** Planul spune că poți avea multiple variante inactive cu aceeași combinație. Dar dacă există o variantă activă cu acel digest, `find_existing_variant` o găsește și `handle_existing` blochează orice acțiune, chiar dacă admin cere explicit `status: :inactive` pentru draft nou.

**Fix (V5.0 inițial):** Reutiliza un draft existent dacă există.

**Corecție (V5.1):** Reutilizarea automată contrazice invarianta #9 ("multiple draft-uri permise"). Soluția corectă: dacă admin cere `status: :inactive`, creează MEREU un draft nou, fără să cauți existing_draft.
```ruby
# DUPĂ (V5.1):
def call(option_value_ids, attributes = {})
  # ... sanitize, digest, desired_status ...

  # Dacă se cere explicit draft (inactive), creează MEREU unul nou
  # Conform invariantei #9: multiple draft-uri cu același digest = permis
  if desired_status == :inactive
    return create_new(option_value_ids, attributes)
  end

  # Flow normal pentru activare/reactivare
  existing = find_existing_variant(digest)
  existing ? handle_existing(existing, attributes) : create_new(option_value_ids, attributes)
end
```

**Trade-off cunoscut:** Poți genera mai multe draft-uri în timp. Dacă e problemă UX (ex: dublu-click), soluția e în UI (idempotency key / throttling), nu reutilizare implicită în service.

### Fix 11: M2 preflight pentru multi-value per option_type
**Problema:** Migrarea M2 nu face preflight pentru variante cu multiple valori pe același option_type. Dacă există astfel de date, digest-ul calculat poate fi greșit (ex: "12-12-45") și `complete` scope devine ambiguu.

**Fix:** Adaugă preflight și oprește în producție dacă există cazuri (necesită decizie umană):
```ruby
# DUPĂ (V5.2.1) - în M2, înainte de backfill:
# NOTĂ: COUNT(DISTINCT) evită false positives dacă dedupe-ul nu a rulat încă
# V5.2.1: array_agg(DISTINCT) pentru debug ușor (vezi exact care value_ids)
multi_value = execute(<<~SQL).to_a
  SELECT v.product_id, v.id as variant_id, ov.option_type_id,
         COUNT(DISTINCT ovv.option_value_id) as cnt,
         array_agg(DISTINCT ovv.option_value_id ORDER BY ovv.option_value_id) as value_ids
  FROM option_value_variants ovv
  JOIN variants v ON v.id = ovv.variant_id
  JOIN option_values ov ON ov.id = ovv.option_value_id
  GROUP BY v.product_id, v.id, ov.option_type_id
  HAVING COUNT(DISTINCT ovv.option_value_id) > 1
SQL
if multi_value.any?
  multi_value.each do |r|
    puts "Multi value: product #{r['product_id']} variant #{r['variant_id']} " \
         "type #{r['option_type_id']} cnt #{r['cnt']} values #{r['value_ids']}"
  end
  raise "ABORT: Variants have multiple values for same option_type. Fix data first." if Rails.env.production?
end
```

### Fix 12: Checkout lock pe order_items
**Problema:** Checkout blochează comanda cu `lock!`, dar nu și order_items. Dacă alt cod modifică order_items fără să blocheze comanda, poți avea scădere de stoc incorectă față de ce ajunge confirmat.

**Fix:** Lock order_items în tranzacție și folosește acea listă:
```ruby
# DUPĂ (V5.2.1):
@order.transaction do
  @order.lock!
  raise AlreadyFinalizedError unless @order.status == 'pending'

  # order(:id) => ordine stabilă de lock / reduce riscul de deadlock
  items = @order.order_items.lock.order(:id).to_a
  raise VariantUnavailableError if items.any? { |i| i.variant_id.nil? }

  items_by_variant = items.group_by(&:variant_id)
  # restul rămâne identic
end
```

**Convenție lock (V5.2.1):** Orice cod care modifică `order_items` trebuie să ruleze într-o tranzacție și să facă `order.lock!` înainte (ca să nu concureze cu finalize).

### Observație: FK option_values cu RESTRICT
**Context:** FK `option_value_variants → option_values` cu `ON DELETE RESTRICT` blochează ștergerea option_values dacă sunt folosite de orice variantă (inclusiv inactive).

**Decizie:** Acesta e comportamentul dorit. Dacă vrei să ștergi un option_value, trebuie mai întâi să cureți OVV-urile care îl referențiază. UI ar trebui să facă dezactivare, nu ștergere.

---

## 1. MIGRĂRI

### M1: Add Columns

```ruby
class M1AddVariantsColumns < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:variants, :status)
      add_column :variants, :status, :integer, null: false, default: 0
    end
    if column_exists?(:variants, :options_digest)
      # Convertește la :text dacă e :string (evită overflow pe produse cu multe opțiuni)
      col = connection.columns(:variants).find { |c| c.name == 'options_digest' }
      change_column :variants, :options_digest, :text if col && col.type != :text
    else
      add_column :variants, :options_digest, :text
    end
    unless column_exists?(:variants, :external_sku)
      add_column :variants, :external_sku, :string
    end
    add_index :variants, :status, if_not_exists: true

    # Order Items snapshot (toate cu idempotency check)
    unless column_exists?(:order_items, :variant_sku)
      add_column :order_items, :variant_sku, :string
    end

    # variant_options_text ca :text (nu :string) pentru snapshot complet fără truncare
    if column_exists?(:order_items, :variant_options_text)
      col = connection.columns(:order_items).find { |c| c.name == 'variant_options_text' }
      change_column :order_items, :variant_options_text, :text if col && col.type != :text
    else
      add_column :order_items, :variant_options_text, :text
    end

    unless column_exists?(:order_items, :vat_rate_snapshot)
      add_column :order_items, :vat_rate_snapshot, :decimal, precision: 5, scale: 2
    end

    unless column_exists?(:order_items, :currency)
      add_column :order_items, :currency, :string, default: 'RON'
    end

    unless column_exists?(:order_items, :line_total_gross)
      add_column :order_items, :line_total_gross, :decimal, precision: 10, scale: 2
    end

    unless column_exists?(:order_items, :tax_amount)
      add_column :order_items, :tax_amount, :decimal, precision: 10, scale: 2
    end

    change_column_null :order_items, :variant_id, true
  end
end
```

### M2: Cleanup & Preflight

```ruby
class M2CleanupVariantsData < ActiveRecord::Migration[7.0]
  def up
    # 1. Normalizare: BTRIM + NULL-ificare (safe indiferent de schema curentă)
    execute "UPDATE variants SET options_digest = NULLIF(BTRIM(options_digest), '')"
    execute "UPDATE variants SET external_sku = NULLIF(BTRIM(external_sku), '')"
    # SKU: trim + backfill direct (evită NULL temporar dacă coloana e NOT NULL)
    execute "UPDATE variants SET sku = BTRIM(sku) WHERE sku IS NOT NULL"
    execute "UPDATE variants SET sku = 'VAR-' || id WHERE sku IS NULL OR sku = ''"

    # 2. PREFLIGHT: SKU duplicate (per produs)
    sku_duplicates = execute(<<~SQL).to_a
      SELECT product_id, sku, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants WHERE sku IS NOT NULL
      GROUP BY product_id, sku HAVING COUNT(*) > 1
    SQL
    if sku_duplicates.any?
      sku_duplicates.each { |r| puts "SKU dup: Product #{r['product_id']}, SKU '#{r['sku']}' - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix SKU duplicates manually!" if Rails.env.production?
    end

    # 2b. PREFLIGHT: external_sku duplicate (global)
    ext_sku_duplicates = execute(<<~SQL).to_a
      SELECT external_sku, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants WHERE external_sku IS NOT NULL
      GROUP BY external_sku HAVING COUNT(*) > 1
    SQL
    if ext_sku_duplicates.any?
      ext_sku_duplicates.each { |r| puts "External SKU dup: '#{r['external_sku']}' - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix external_sku duplicates manually!" if Rails.env.production?
    end

    # 2c. PREFLIGHT: Variante cu multiple valori pe același option_type (FIX 11)
    # V5.2.1: COUNT(DISTINCT) evită false positives + array_agg pentru debug ușor
    multi_value = execute(<<~SQL).to_a
      SELECT v.product_id, v.id as variant_id, ov.option_type_id,
             COUNT(DISTINCT ovv.option_value_id) as cnt,
             array_agg(DISTINCT ovv.option_value_id ORDER BY ovv.option_value_id) as value_ids
      FROM option_value_variants ovv
      JOIN variants v ON v.id = ovv.variant_id
      JOIN option_values ov ON ov.id = ovv.option_value_id
      GROUP BY v.product_id, v.id, ov.option_type_id
      HAVING COUNT(DISTINCT ovv.option_value_id) > 1
    SQL
    if multi_value.any?
      multi_value.each do |r|
        puts "Multi value: product #{r['product_id']} variant #{r['variant_id']} " \
             "type #{r['option_type_id']} cnt #{r['cnt']} values #{r['value_ids']}"
      end
      raise "ABORT: Variants have multiple values for same option_type. Fix data first." if Rails.env.production?
    end

    # 2d. DEDUPE join tables ÎNAINTE de backfill digest (previne digest-uri gen "12-12-45")
    # Folosim ctid (PostgreSQL row identifier) - funcționează și pentru tabele fără coloană id
    execute(<<~SQL)
      DELETE FROM product_option_types a
      USING product_option_types b
      WHERE a.ctid > b.ctid
        AND a.product_id = b.product_id
        AND a.option_type_id = b.option_type_id
    SQL
    execute(<<~SQL)
      DELETE FROM option_value_variants a
      USING option_value_variants b
      WHERE a.ctid > b.ctid
        AND a.variant_id = b.variant_id
        AND a.option_value_id = b.option_value_id
    SQL

    # 3. BACKFILL: Calculează digest din join-uri existente
    # IMPORTANT: Doar din option_types CURENTE ale produsului (ignoră opțiuni obsolete)
    execute(<<~SQL)
      UPDATE variants
      SET options_digest = subq.calculated_digest
      FROM (
        SELECT ovv.variant_id,
               string_agg(ovv.option_value_id::text, '-' ORDER BY ovv.option_value_id) AS calculated_digest
        FROM option_value_variants ovv
        JOIN variants v ON v.id = ovv.variant_id
        JOIN option_values ov ON ov.id = ovv.option_value_id
        JOIN product_option_types pot
          ON pot.product_id = v.product_id
         AND pot.option_type_id = ov.option_type_id
        GROUP BY ovv.variant_id
      ) subq
      WHERE variants.id = subq.variant_id
    SQL

    # 3b. Nullify digest pentru variante care au DOAR opțiuni obsolete
    # (nu au intrat în subq-ul de mai sus, dar pot avea digest vechi greșit)
    execute(<<~SQL)
      UPDATE variants v
      SET options_digest = NULL
      WHERE v.options_digest IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM option_value_variants ovv
          JOIN option_values ov ON ov.id = ovv.option_value_id
          JOIN product_option_types pot
            ON pot.product_id = v.product_id
           AND pot.option_type_id = ov.option_type_id
          WHERE ovv.variant_id = v.id
        )
    SQL

    # 4. PREFLIGHT: Digest duplicate (pe variante ACTIVE)
    # ALINIAT cu idx_unique_active_options_per_product (status = 0)
    digest_duplicates = execute(<<~SQL).to_a
      SELECT product_id, options_digest, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants
      WHERE options_digest IS NOT NULL AND status = 0
      GROUP BY product_id, options_digest HAVING COUNT(*) > 1
    SQL
    if digest_duplicates.any?
      digest_duplicates.each { |r| puts "Digest dup: Product #{r['product_id']}, '#{r['options_digest']}' - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix digest duplicates manually!" if Rails.env.production?
    end

    # 5. CLEANUP: Dezactivează default active duplicate (păstrează primul)
    execute(<<~SQL)
      UPDATE variants SET status = 1
      WHERE id IN (
        SELECT v.id FROM variants v
        INNER JOIN (
          SELECT product_id, MIN(id) as keep_id FROM variants
          WHERE status = 0 AND options_digest IS NULL
          GROUP BY product_id HAVING COUNT(*) > 1
        ) dups ON v.product_id = dups.product_id
        WHERE v.status = 0 AND v.options_digest IS NULL AND v.id != dups.keep_id
      )
    SQL

    # 6. CLEANUP: Fix NULL/negative price/stock
    execute("UPDATE variants SET stock = 0 WHERE stock < 0 OR stock IS NULL")
    execute("UPDATE variants SET price = 0 WHERE price < 0 OR price IS NULL")

    # 7. CLEANUP ORFANI (pentru FK-uri în M3)
    # 7a. Orfani option_value_variants
    execute(<<~SQL)
      DELETE FROM option_value_variants ovv
      WHERE NOT EXISTS (SELECT 1 FROM variants v WHERE v.id = ovv.variant_id)
         OR NOT EXISTS (SELECT 1 FROM option_values ov WHERE ov.id = ovv.option_value_id)
    SQL

    # 7b. Șterge doar variantele orfane care NU sunt referențiate de comenzi
    execute(<<~SQL)
      DELETE FROM variants v
      WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.id = v.product_id)
        AND NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.variant_id = v.id)
    SQL

    # 7c. Dacă au rămas variante orfane dar folosite în comenzi -> ABORT în prod
    orphans_used = execute(<<~SQL).to_a
      SELECT v.id, v.product_id, COUNT(oi.id) as order_items_count
      FROM variants v
      JOIN order_items oi ON oi.variant_id = v.id
      LEFT JOIN products p ON p.id = v.product_id
      WHERE p.id IS NULL
      GROUP BY v.id, v.product_id
    SQL
    if orphans_used.any?
      orphans_used.each { |r| puts "Orphan variant used in orders: variant #{r['id']} product_id #{r['product_id']} order_items #{r['order_items_count']}" }
      raise "ABORT: Orphan variants referenced by orders. Fix data (restore products or reattach)!" if Rails.env.production?
    end

    # 7d. Order items care pointează la variantă inexistentă (setează NULL, nu șterge)
    execute(<<~SQL)
      UPDATE order_items oi
      SET variant_id = NULL
      WHERE variant_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM variants v WHERE v.id = oi.variant_id)
    SQL
  end
end
```

### M3: Constraints & Indexes

```ruby
class M3AddVariantsConstraints < ActiveRecord::Migration[7.0]
  def change
    # === UNIQUE INDEXES ===

    # SKU unic per produs
    add_index :variants, [:product_id, :sku], unique: true,
              name: 'idx_unique_sku_per_product', if_not_exists: true

    # Digest unic per produs (doar pentru variante ACTIVE cu opțiuni)
    add_index :variants, [:product_id, :options_digest], unique: true,
              where: "options_digest IS NOT NULL AND status = 0",
              name: 'idx_unique_active_options_per_product', if_not_exists: true

    # Maxim 1 default ACTIV per produs (permite multiple inactive/draft)
    add_index :variants, [:product_id], unique: true,
              where: "options_digest IS NULL AND status = 0",
              name: 'idx_unique_active_default_variant', if_not_exists: true

    # External SKU unic global
    add_index :variants, :external_sku, unique: true,
              where: "external_sku IS NOT NULL",
              name: 'idx_unique_external_sku', if_not_exists: true

    # === CHECK CONSTRAINTS ===

    unless constraint_exists?(:variants, 'chk_variants_price_positive')
      add_check_constraint :variants, 'price IS NOT NULL AND price >= 0',
                           name: 'chk_variants_price_positive'
    end
    unless constraint_exists?(:variants, 'chk_variants_stock_positive')
      add_check_constraint :variants, 'stock IS NOT NULL AND stock >= 0',
                           name: 'chk_variants_stock_positive'
    end

    # === JOIN TABLE ===

    add_index :option_value_variants, [:variant_id, :option_value_id], unique: true,
              name: 'idx_unique_ovv', if_not_exists: true
    add_index :option_value_variants, :variant_id, name: 'idx_ovv_variant', if_not_exists: true
    add_index :option_value_variants, :option_value_id, name: 'idx_ovv_option_value', if_not_exists: true

    # === FOREIGN KEYS ===

    unless foreign_key_exists?(:option_value_variants, :variants)
      add_foreign_key :option_value_variants, :variants, on_delete: :cascade
    end
    unless foreign_key_exists?(:option_value_variants, :option_values)
      add_foreign_key :option_value_variants, :option_values, on_delete: :restrict
    end
    unless foreign_key_exists?(:variants, :products)
      add_foreign_key :variants, :products, on_delete: :restrict
    end
    unless foreign_key_exists?(:order_items, :variants)
      add_foreign_key :order_items, :variants, on_delete: :nullify
    end

    # === PERFORMANCE & INTEGRITY ===

    add_index :product_option_types, [:product_id, :option_type_id], unique: true,
              name: 'idx_unique_product_option_type', if_not_exists: true
    add_index :product_option_types, :product_id, name: 'idx_pot_product', if_not_exists: true
    add_index :option_values, :option_type_id, name: 'idx_ov_type', if_not_exists: true
  end

  private

  def constraint_exists?(table, name)
    query = <<~SQL
      SELECT 1 FROM pg_constraint
      WHERE conname = '#{name}'
        AND conrelid = '#{table}'::regclass
    SQL
    ActiveRecord::Base.connection.select_value(query).present?
  end
end
```

---

## 2. MODELE

### Variant

```ruby
class Variant < ApplicationRecord
  # ATENȚIE: active = 0 pentru indexuri parțiale - NU SCHIMBA!
  enum :status, { active: 0, inactive: 1 }, default: :active

  belongs_to :product
  has_many :option_value_variants, dependent: :destroy
  has_many :option_values, through: :option_value_variants
  has_many :order_items, dependent: :nullify

  validates :sku, presence: true, uniqueness: { scope: :product_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  # FIX 9: Adăugat presence: true pentru aliniere cu invarianta #7
  validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Validare conflict la activare SAU schimbare digest pe variantă activă
  # (transformă 500 în mesaj user-friendly)
  validate :no_active_digest_conflict, if: -> { active? && (will_save_change_to_status? || will_save_change_to_options_digest?) }

  before_validation :normalize_identifiers
  # ATENȚIE: NU sincronizăm digest în callbacks! Se face explicit în servicii.

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

  def deactivate!
    inactive!
  end

  def activate!
    active!
  end

  def default_variant?
    options_digest.nil?
  end

  # Calculează digest direct din DB (evită cache-ul Rails)
  # IMPORTANT: Doar din option_types CURENTE ale produsului (ignoră opțiuni obsolete)
  # IMPORTANT: Query direct ProductOptionType, NU product.option_type_ids (cached!)
  def compute_digest_from_db
    allowed_type_ids = ProductOptionType.where(product_id: product_id).pluck(:option_type_id)
    option_value_variants
      .joins(:option_value)
      .where(option_values: { option_type_id: allowed_type_ids })
      .order(:option_value_id)
      .pluck(:option_value_id)
      .join('-')
      .presence
  end

  private

  def normalize_identifiers
    self.options_digest = nil if options_digest.is_a?(String) && options_digest.strip.empty?
    self.external_sku = external_sku.strip.presence if external_sku.is_a?(String)
    self.sku = sku.strip if sku.is_a?(String)
  end

  # V5.2.1: Query direct cu Variant.where(product_id:) - evită cache-ul asociației product.variants
  # Folosim Variant.statuses[:active] pentru mapping explicit (robust la refactor enum)
  def no_active_digest_conflict
    scope = Variant.where(product_id: product_id, status: Variant.statuses[:active]).where.not(id: id)

    conflict = if options_digest.nil?
      scope.where(options_digest: nil).exists?
    else
      scope.where(options_digest: options_digest).exists?
    end

    errors.add(:status, "Există deja o variantă activă cu această combinație") if conflict
  end
end
```

### OptionValueVariant

```ruby
class OptionValueVariant < ApplicationRecord
  belongs_to :variant
  belongs_to :option_value

  # ATENȚIE: NU sincronizăm digest în callbacks!
  # Digest-ul se calculează explicit în servicii, în aceeași tranzacție.
end
```

### Product

```ruby
class Product < ApplicationRecord
  has_many :variants, dependent: :restrict_with_error
  has_many :product_option_types, dependent: :destroy
  has_many :option_types, through: :product_option_types

  def archive!
    transaction do
      variants.active.update_all(status: 1)
      update!(archived: true, archived_at: Time.current)
    end
  end
end
```

---

## 3. SERVICII

### Variants::CreateOrReactivateService

```ruby
module Variants
  class CreateOrReactivateService
    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true)

    def initialize(product)
      @product = product
    end

    def call(option_value_ids, attributes = {})
      option_value_ids = sanitize_ids(option_value_ids)
      digest = option_value_ids.empty? ? nil : option_value_ids.join('-')
      desired_status = normalize_status(attributes[:status] || attributes["status"])

      return invalid("Unele opțiuni nu aparțin produsului") unless valid_option_values?(option_value_ids)

      # FIX 10 (V5.1): Dacă se cere explicit draft (inactive), creează MEREU unul nou
      # Conform invariantei #9: multiple draft-uri cu același digest = permis
      # Trade-off: poate genera multe draft-uri; dacă e problemă UX, soluția e în UI
      if desired_status == :inactive
        return create_new(option_value_ids, attributes)
      end

      # Flow normal pentru activare/reactivare
      existing = find_existing_variant(digest)

      if existing
        handle_existing(existing, attributes)
      else
        create_new(option_value_ids, attributes)
      end
    rescue ActiveRecord::RecordNotUnique => e
      handle_unique_violation(e, digest)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, variant: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    end

    private

    def handle_unique_violation(exception, digest)
      msg = exception.cause&.message.to_s

      # Diferențiază indexul care a cauzat conflictul
      if msg.include?('idx_unique_sku_per_product')
        return Result.new(success: false, variant: nil, action: :invalid,
                          error: "SKU deja folosit pentru acest produs")
      end

      if msg.include?('idx_unique_external_sku')
        return Result.new(success: false, variant: nil, action: :invalid,
                          error: "External SKU deja folosit")
      end

      if msg.include?('idx_unique_active_options_per_product')
        return Result.new(success: false, variant: nil, action: :conflict,
                          error: "Există deja o variantă activă cu această combinație de opțiuni")
      end

      if msg.include?('idx_unique_active_default_variant')
        return Result.new(success: false, variant: nil, action: :conflict,
                          error: "Există deja o variantă default activă pentru acest produs")
      end

      # Race condition generică pe digest - încearcă să găsească varianta existentă
      handle_race_condition(exception, digest)
    end

    def sanitize_ids(input)
      Array(input).map { |x| x.to_s.strip }.reject(&:empty?).map(&:to_i).reject(&:zero?).uniq.sort
    end

    def valid_option_values?(ids)
      return true if ids.empty?

      # Verifică că TOATE ID-urile există
      rows = OptionValue.where(id: ids).pluck(:id, :option_type_id)
      return false if rows.size != ids.size # unele ID-uri nu există

      type_ids = rows.map(&:last)

      # Verifică maxim 1 valoare per option_type (opțional dar recomandat)
      return false if type_ids.size != type_ids.uniq.size

      # Verifică că type-urile aparțin produsului (din DB, nu cache!)
      allowed = ProductOptionType.where(product_id: @product.id).pluck(:option_type_id)
      (type_ids - allowed).empty?
    end

    def find_existing_variant(digest)
      if digest.nil?
        @product.variants.find_by(options_digest: nil, status: :active) ||
          @product.variants.where(options_digest: nil).order(:id).first
      else
        # IMPORTANT: Preferă varianta activă, apoi cel mai vechi draft (determinism)
        @product.variants.find_by(options_digest: digest, status: :active) ||
          @product.variants.where(options_digest: digest).order(:id).first
      end
    end

    def handle_existing(existing, attributes)
      # Respectă desired_status din attributes (nu forța activare)
      desired_status = normalize_status(attributes[:status] || attributes["status"])

      if existing.active?
        Result.new(success: false, variant: existing, action: :already_exists,
                   error: "Combinația există deja și e activă (SKU: #{existing.sku})")
      else
        existing.update!(attributes.merge(status: desired_status))
        Result.new(success: true, variant: existing, action: :reactivated, error: nil)
      end
    end

    def create_new(option_value_ids, attributes)
      # Păstrează statusul dorit (default: active)
      desired_status = normalize_status(attributes[:status] || attributes["status"])

      @product.transaction do
        # IMPORTANT: Creează INACTIVE temporar ca să nu lovești idx_unique_active_default_variant
        # (la insert options_digest e NULL, ar conflicta cu alt default activ)
        variant = @product.variants.create!(attributes.merge(status: :inactive, options_digest: nil))
        option_value_ids.each { |id| variant.option_value_variants.create!(option_value_id: id) }

        # Calculează digest și setează statusul final ATOMIC
        new_digest = option_value_ids.empty? ? nil : option_value_ids.join('-')
        variant.update!(options_digest: new_digest, status: desired_status)

        Result.new(success: true, variant: variant, action: :created, error: nil)
      end
    end

    def handle_race_condition(exception, digest)
      existing = find_existing_variant(digest)
      if existing
        Result.new(success: false, variant: existing, action: :race_condition,
                   error: "Combinația a fost creată de alt proces")
      else
        raise exception
      end
    end

    def invalid(message)
      Result.new(success: false, variant: nil, action: :invalid, error: message)
    end

    # Normalizează status din orice input (integer/string/symbol/nil)
    def normalize_status(val)
      return :active if val.nil? || (val.respond_to?(:empty?) && val.empty?)
      return Variant.statuses.key(val)&.to_sym || :active if val.is_a?(Integer)
      s = val.to_s
      Variant.statuses.key?(s) ? s.to_sym : :active
    end
  end
end
```

### Variants::UpdateOptionsService

```ruby
module Variants
  class UpdateOptionsService
    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true)

    def initialize(variant)
      @variant = variant
      @product = variant.product
    end

    def call(new_option_value_ids)
      new_option_value_ids = sanitize_ids(new_option_value_ids)
      new_digest = new_option_value_ids.empty? ? nil : new_option_value_ids.join('-')

      unless valid_option_values?(new_option_value_ids)
        return Result.new(success: false, variant: @variant, action: :invalid,
                         error: "Unele opțiuni nu aparțin acestui produs")
      end

      # Verifică conflict doar pentru variante ACTIVE
      if @variant.active?
        conflict = @product.variants.where.not(id: @variant.id)
                           .find_by(options_digest: new_digest, status: :active)
        if conflict
          return Result.new(success: false, variant: conflict, action: :conflict,
                           error: "Există deja o variantă activă cu această combinație (SKU: #{conflict.sku})")
        end
      end

      @variant.transaction do
        @variant.option_value_variants.destroy_all
        new_option_value_ids.each { |id| @variant.option_value_variants.create!(option_value_id: id) }

        # Calculează și setează digest EXPLICIT în aceeași tranzacție
        new_digest = new_option_value_ids.empty? ? nil : new_option_value_ids.join('-')
        @variant.update!(options_digest: new_digest)
      end

      Result.new(success: true, variant: @variant, action: :updated, error: nil)
    rescue ActiveRecord::RecordNotUnique => e
      # Index unic a blocat - există deja o variantă activă cu acest digest
      Result.new(success: false, variant: @variant, action: :conflict,
                 error: "Există deja o variantă activă cu această combinație")
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, variant: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    end

    private

    def sanitize_ids(input)
      Array(input).map { |x| x.to_s.strip }.reject(&:empty?).map(&:to_i).reject(&:zero?).uniq.sort
    end

    def valid_option_values?(ids)
      return true if ids.empty?

      # Verifică că TOATE ID-urile există
      rows = OptionValue.where(id: ids).pluck(:id, :option_type_id)
      return false if rows.size != ids.size # unele ID-uri nu există

      type_ids = rows.map(&:last)

      # Verifică maxim 1 valoare per option_type (opțional dar recomandat)
      return false if type_ids.size != type_ids.uniq.size

      # Verifică că type-urile aparțin produsului (din DB, nu cache!)
      allowed = ProductOptionType.where(product_id: @product.id).pluck(:option_type_id)
      (type_ids - allowed).empty?
    end
  end
end
```

### Products::UpdateOptionTypesService

```ruby
module Products
  class UpdateOptionTypesService
    def initialize(product)
      @product = product
    end

    def call(new_option_type_ids)
      @product.transaction do
        # Lock produsul pentru a preveni crearea de variante noi în paralel
        @product.lock!
        @product.option_type_ids = new_option_type_ids

        # Lock toate variantele existente pentru reconciliere
        variants = @product.variants.lock.to_a

        # 1) Calculează new_digest pentru fiecare
        new_digest_by_id = {}
        variants.each do |v|
          new_digest_by_id[v.id] = v.compute_digest_from_db
        end

        # 2) Decide cine rămâne ACTIVE per digest (max 1, cel mai mic id)
        keep_active_ids = []
        variants.group_by { |v| new_digest_by_id[v.id] }.each do |_digest, group|
          active_in_group = group.select(&:active?)
          if active_in_group.any?
            keep_active_ids << active_in_group.min_by(&:id).id
          end
        end

        # 3) Deactivează înainte de update digest (evită conflict pe indexuri unice)
        deactivated_ids = []
        variants.each do |v|
          next unless v.active?
          next if keep_active_ids.include?(v.id)
          v.update_column(:status, Variant.statuses[:inactive])
          deactivated_ids << v.id
        end

        # 4) Acum e safe să scrii digest-urile (inactive nu intră în indexul parțial)
        variants.each do |v|
          nd = new_digest_by_id[v.id]
          v.update_column(:options_digest, nd) if v.options_digest != nd
        end

        { success: true, deactivated_count: deactivated_ids.size, deactivated_ids: deactivated_ids }
      end
    end
  end
end
```

### Checkout::FinalizeService

```ruby
module Checkout
  class FinalizeService
    class VariantUnavailableError < StandardError; end
    class InsufficientStockError < StandardError; end
    class AlreadyFinalizedError < StandardError; end

    def initialize(order)
      @order = order
    end

    def call
      @order.transaction do
        # GUARD ATOMIC: lock! + verificare status (idempotent, fără status nou)
        @order.lock!
        raise AlreadyFinalizedError, "Comanda a fost deja procesată" unless @order.status == 'pending'

        # FIX 12: Lock order_items pentru a preveni modificări concurente
        # V5.2.1: order(:id) => ordine stabilă de lock / reduce riscul de deadlock
        # Convenție: orice cod care modifică order_items trebuie order.lock! înainte
        items = @order.order_items.lock.order(:id).to_a

        # Verifică că toate item-urile au variantă validă
        if items.any? { |i| i.variant_id.nil? }
          raise VariantUnavailableError, "Comanda conține item fără variantă"
        end

        # Sort pentru a evita deadlock
        items_by_variant = items.group_by(&:variant_id)
        sorted_ids = items_by_variant.keys.compact.sort

        sorted_ids.each do |variant_id|
          variant_items = items_by_variant[variant_id]
          total_qty = variant_items.sum(&:quantity)

          # UPDATE ATOMIC cu status + stock check
          rows = Variant
            .where(id: variant_id, status: :active)
            .where('stock >= ?', total_qty)
            .update_all(['stock = stock - ?', total_qty])

          if rows == 0
            variant = Variant.find_by(id: variant_id)
            raise VariantUnavailableError, "Varianta nu e disponibilă" unless variant&.active?
            raise InsufficientStockError, "Stoc insuficient pentru '#{variant.sku}'"
          end

          # Snapshot pentru istoric
          variant = Variant.find(variant_id)
          variant_items.each { |item| snapshot_item(item, variant) }
        end

        @order.update!(status: 'confirmed')
      end
    end

    private

    def snapshot_item(item, variant)
      # Salvează TOATE opțiunile variantei (snapshot complet, imutabil)
      # NU filtrăm pe option_types curente - comanda reflectă ce s-a cumpărat
      options_text = variant.option_values.order(:id).pluck(:name).join(', ')

      item.update!(
        variant_sku: variant.sku,
        variant_options_text: options_text,
        vat_rate_snapshot: variant.vat_rate,
        line_total_gross: item.quantity * variant.price
      )
    end
  end
end
```

---

## 4. RAKE TASK: Audit

```ruby
# lib/tasks/variants.rake
namespace :variants do
  desc "Audit variants data"
  task audit: :environment do
    puts "=== VARIANTS AUDIT ==="

    sku_dups = Variant.where.not(sku: nil).group(:product_id, :sku).having('COUNT(*) > 1').count
    puts sku_dups.any? ? "❌ SKU duplicates: #{sku_dups.count}" : "✅ No SKU duplicates"

    if Variant.column_names.include?('options_digest')
      digest_dups = Variant.where(status: 0).where.not(options_digest: nil)
                           .group(:product_id, :options_digest).having('COUNT(*) > 1').count
      puts digest_dups.any? ? "❌ Active digest duplicates: #{digest_dups.count}" : "✅ No active digest duplicates"
    end

    puts Variant.where('stock < 0').exists? ? "❌ Negative stock" : "✅ No negative stock"
    puts Variant.where('price < 0').exists? ? "❌ Negative price" : "✅ No negative price"
    puts Variant.where(stock: nil).exists? ? "❌ NULL stock" : "✅ No NULL stock"
    puts Variant.where(price: nil).exists? ? "❌ NULL price" : "✅ No NULL price"

    # BONUS: Produse cu option_type care are multiple valori per variantă
    multi_value_types = ActiveRecord::Base.connection.execute(<<~SQL).to_a
      SELECT v.product_id, ov.option_type_id, v.id as variant_id, COUNT(*) as val_count
      FROM option_value_variants ovv
      JOIN variants v ON v.id = ovv.variant_id
      JOIN option_values ov ON ov.id = ovv.option_value_id
      GROUP BY v.product_id, ov.option_type_id, v.id
      HAVING COUNT(*) > 1
    SQL
    puts multi_value_types.any? ? "⚠️  Variants with multiple values per option_type: #{multi_value_types.size}" : "✅ No multi-value option_types"

    # BONUS: Comenzi confirmate cu variant_id NULL (date legacy problematice)
    if OrderItem.column_names.include?('variant_id')
      null_variants_confirmed = OrderItem.joins(:order)
                                         .where(orders: { status: 'confirmed' })
                                         .where(variant_id: nil).count
      puts null_variants_confirmed > 0 ? "⚠️  Confirmed orders with NULL variant_id: #{null_variants_confirmed}" : "✅ No confirmed orders with NULL variant_id"
    end

    puts "=== END AUDIT ==="
  end
end
```

---

## 5. INVARIANTE FINALE

```
1. O COMBINAȚIE ACTIVĂ = O SINGURĂ VARIANTĂ ACTIVĂ (unicitate pe active)
2. MAXIM 1 DEFAULT ACTIV PER PRODUS (digest NULL + status active)
3. COMBINAȚIA POATE FI SCHIMBATĂ ORICÂND (admin are libertate)
4. CUMPĂRABIL (UI/filtrare) = active + complete + stock > 0
4b. CHECKOUT PERMITE = active + stock >= qty (complete e opțional pentru flexibilitate)
5. STOCUL NU POATE FI DEPĂȘIT (checkout atomic)
6. COMANDA = IMUTABILĂ (snapshot)
7. PRICE/STOCK OBLIGATORIU NOT NULL ȘI >= 0 (validat în Rails + CHECK în DB)
8. DIGEST SE CALCULEAZĂ EXPLICIT ÎN SERVICII (atomic, în aceeași tranzacție)
9. MULTIPLE DRAFT-URI CU ACELAȘI DIGEST = PERMIS (dar max 1 ACTIVE)
```

---

## 6. POLICY: Concurență pe Orders / OrderItems (V5.2.1)

**Scop:** Prevenirea race conditions între checkout finalize și orice alt cod care adaugă/șterge/modifică order_items.

### Regula 1 — Lock order înainte de orice modificare pe order_items

Orice cod care modifică `order_items` (add/remove/change quantity/variant/price snapshots etc.) **trebuie** să ruleze într-o tranzacție și să facă `order.lock!` **înainte** de a atinge `order_items`.

**Motiv:** `Checkout::FinalizeService` rulează în tranzacție, face `order.lock!` și apoi blochează `order_items`. Dacă alt cod modifică items fără să respecte aceeași ordine, riști inconsistențe sau deadlock-uri.

### Regula 2 — Ordine stabilă de lock

Când blochezi `order_items`, folosește o ordine stabilă:
```ruby
order.order_items.lock.order(:id).to_a
```

**Motiv:** Reduce riscul de deadlock în situații concurente (ordine predictibilă de lock).

### Regula 3 — Checkout finalize este "source of truth" pentru stock decrement

`Checkout::FinalizeService` este **singurul** loc care are voie să scadă stocul, atomic, pe baza item-urilor blocate.

### Pattern acceptat (pseudo-code)

```ruby
order.transaction do
  order.lock!
  items = order.order_items.lock.order(:id).to_a
  # ... modificări pe items ...
end
```

### Checklist de regresii (verificare non-breaking)

1. **Create draft** cu `status: :inactive` de 3 ori pe același digest → trebuie să rezulte 3 variante inactive
2. **Activate** una dintre ele → dacă există deja activă cu digestul, trebuie să primești conflict (index/validare)
3. **Finalize** două checkout-uri concurente pe aceeași variantă cu stoc limitat → unul trece, unul dă `InsufficientStockError`
4. **Order snapshot**: după confirmare, modificarea variantei să nu afecteze `order_items` snapshot
5. **Change variant**: ai item A (variant X, qty 2) și item B (variant Y, qty 3). Schimbi item A pe variant Y → trebuie să rezulte un singur item cu variant Y și qty 5

### Anti-patterns (INTERZISE)

1. **Modifici `order_items` fără `order.lock!` înainte**
   - Exemplu greșit: `order.order_items.create!(...) / update! / destroy!` fără `order.transaction { order.lock! ... }`
   - Risc: race condition cu `Checkout::FinalizeService` sau deadlock-uri

2. **Decrement de stoc în alt loc decât `Checkout::FinalizeService`**
   - Exemplu greșit: „rezervare stoc la add-to-cart", „scade stoc la update quantity"
   - Risc: dublu decrement, inconsistențe la concurență, "stock leak"

3. **Lock în ordine inversă față de policy**
   - Exemplu greșit: lock pe `order_items` înainte de `order.lock!`
   - Risc: crește probabilitatea de deadlock în scenarii concurente

### Best practices (ACCEPTAT / recomandat)

- **Pattern standard** pentru orice update pe items (add/remove/change qty/variant):
```ruby
order.transaction do
  order.lock!
  items = order.order_items.lock.order(:id).to_a
  # ... modificări pe items ...
  # (fără stock decrement aici)
end
```

- **Clarificare: ce e OK să faci în afara finalize**
  - Este OK să citești stocul pentru UI / validări (ex. „afișează out of stock", „dezactivează butonul")
  - Nu este OK să modifici stocul în afara `Checkout::FinalizeService`

- **Clarificare: scopul `order(:id)` la lock**
  - `order(:id)` oferă ordine stabilă de lock pentru rândurile din `order_items`, ceea ce reduce riscul de deadlock în concurență
  - Nu e despre "determinism business", ci despre lock ordering

### Reguli pentru servicii noi care ating Orders / OrderItems

**Regula 0 — Identifică intenția (read vs write)**
- READ-only (OK fără lock): afișare în UI, calcule, validări "soft", preview totals
- WRITE (OBLIGATORIU lock): orice create/update/destroy pe `order_items` sau câmpuri de snapshot

**Regula 1 — Pattern unic pentru write**

Orice service/controller/job care modifică `order_items` trebuie să folosească exact acest pattern:
```ruby
order.transaction do
  order.lock!
  items = order.order_items.lock.order(:id).to_a
  # ... modificări pe items ...
end
```

**Regula 2 — Checkout finalize rămâne "source of truth" pentru stoc**
- Service-urile care modifică `order_items` **nu scad stocul**
- Singurul loc care face decrement atomic de stoc = `Checkout::FinalizeService`

**Regula 3 — Orice logică nouă trebuie să respecte "same lock order"**
- Dacă un service nou are nevoie să atingă și alte tabele "sensibile" (ex. payments, shipments etc.):
  1. `order.lock!`
  2. `order_items.lock.order(:id)`
  3. abia apoi restul operațiilor

### Checklist rapid pentru PR review

Bifează înainte de merge:
- [ ] Orice modificare pe `order_items` este în `order.transaction` + `order.lock!` înainte
- [ ] Când se blochează `order_items`, există `order(:id)`
- [ ] Nu există decrement de stoc în afara `Checkout::FinalizeService`
- [ ] Nu există lock-uri în ordine inversă (`order_items` înainte de `order.lock!`)
- [ ] Testele existente pe checkout/stock/snapshot rămân verzi

### Helper: Orders::ConcurrencyPolicy (centralizare pattern)

```ruby
# app/services/orders/concurrency_policy.rb
module Orders
  module ConcurrencyPolicy
    # Policy V5.2.1:
    # - întotdeauna order.lock! înainte de orice modificare pe order_items
    # - lock order_items cu ordine stabilă: order(:id)
    # - NU atinge stocul aici (rămâne exclusiv în Checkout::FinalizeService)
    def with_locked_items!(order)
      order.transaction do
        order.lock!
        items = order.order_items.lock.order(:id).to_a
        yield(items)
      end
    end
  end
end
```

### Exemple de servicii care respectă policy-ul V5.2.1

#### 1) Orders::AddItemService (merge dacă există deja aceeași variantă)

```ruby
# app/services/orders/add_item_service.rb
module Orders
  class AddItemService
    include Orders::ConcurrencyPolicy

    Result = Struct.new(:success, :order_item, :action, :error, keyword_init: true)

    def initialize(order)
      @order = order
    end

    def call(variant_id:, quantity:)
      variant_id = variant_id.to_i
      quantity   = quantity.to_i

      return Result.new(success: false, action: :invalid, error: "Quantity invalid") if quantity <= 0
      return Result.new(success: false, action: :invalid, error: "Variant invalid")  if variant_id <= 0
      return Result.new(success: false, action: :invalid, error: "Variant not found") unless Variant.exists?(variant_id)
      return Result.new(success: false, action: :invalid, error: "Order not editable") unless @order.status == "pending"

      with_locked_items!(@order) do |items|
        existing = items.find { |i| i.variant_id == variant_id }

        if existing
          existing.update!(quantity: existing.quantity + quantity)
          return Result.new(success: true, order_item: existing, action: :merged, error: nil)
        end

        item = @order.order_items.create!(variant_id: variant_id, quantity: quantity)
        Result.new(success: true, order_item: item, action: :created, error: nil)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, order_item: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    rescue => e
      Result.new(success: false, order_item: nil, action: :error, error: e.message)
    end
  end
end
```

#### 2) Orders::UpdateQuantityService (update sau remove dacă qty <= 0)

```ruby
# app/services/orders/update_quantity_service.rb
module Orders
  class UpdateQuantityService
    include Orders::ConcurrencyPolicy

    Result = Struct.new(:success, :order_item, :action, :error, keyword_init: true)

    def initialize(order)
      @order = order
    end

    def call(order_item_id:, quantity:)
      order_item_id = order_item_id.to_i
      quantity      = quantity.to_i

      return Result.new(success: false, action: :invalid, error: "Order item invalid") if order_item_id <= 0
      return Result.new(success: false, action: :invalid, error: "Order not editable") unless @order.status == "pending"

      with_locked_items!(@order) do |items|
        item = items.find { |i| i.id == order_item_id }
        return Result.new(success: false, action: :not_found, error: "Item not found") unless item

        if quantity <= 0
          item.destroy!
          return Result.new(success: true, order_item: nil, action: :removed, error: nil)
        end

        item.update!(quantity: quantity)
        Result.new(success: true, order_item: item, action: :updated, error: nil)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, order_item: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    rescue => e
      Result.new(success: false, order_item: nil, action: :error, error: e.message)
    end
  end
end
```

#### 3) Orders::RemoveItemService

```ruby
# app/services/orders/remove_item_service.rb
module Orders
  class RemoveItemService
    include Orders::ConcurrencyPolicy

    Result = Struct.new(:success, :action, :error, keyword_init: true)

    def initialize(order)
      @order = order
    end

    def call(order_item_id:)
      order_item_id = order_item_id.to_i

      return Result.new(success: false, action: :invalid, error: "Order item invalid") if order_item_id <= 0
      return Result.new(success: false, action: :invalid, error: "Order not editable") unless @order.status == "pending"

      with_locked_items!(@order) do |items|
        item = items.find { |i| i.id == order_item_id }
        return Result.new(success: false, action: :not_found, error: "Item not found") unless item

        item.destroy!
        Result.new(success: true, action: :deleted, error: nil)
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      Result.new(success: false, action: :invalid, error: e.record.errors.full_messages.to_sentence)
    rescue => e
      Result.new(success: false, action: :error, error: e.message)
    end
  end
end
```

#### 4) Orders::ChangeItemVariantService (swap variant_id cu merge)

```ruby
# app/services/orders/change_item_variant_service.rb
module Orders
  class ChangeItemVariantService
    include Orders::ConcurrencyPolicy

    Result = Struct.new(:success, :order_item, :action, :error, keyword_init: true)

    def initialize(order)
      @order = order
    end

    def call(order_item_id:, target_variant_id:)
      order_item_id     = order_item_id.to_i
      target_variant_id = target_variant_id.to_i

      return Result.new(success: false, action: :invalid, error: "Order item invalid") if order_item_id <= 0
      return Result.new(success: false, action: :invalid, error: "Target variant invalid") if target_variant_id <= 0
      return Result.new(success: false, action: :invalid, error: "Variant not found") unless Variant.exists?(target_variant_id)
      return Result.new(success: false, action: :invalid, error: "Order not editable") unless @order.status == "pending"

      with_locked_items!(@order) do |items|
        item = items.find { |i| i.id == order_item_id }
        return Result.new(success: false, action: :not_found, error: "Item not found") unless item

        # no-op dacă e deja aceeași variantă
        if item.variant_id == target_variant_id
          return Result.new(success: true, order_item: item, action: :no_change, error: nil)
        end

        # Dacă există deja alt item cu target_variant_id, fă merge (evită duplicate)
        existing_target = items.find { |i| i.variant_id == target_variant_id }

        if existing_target
          existing_target.update!(quantity: existing_target.quantity + item.quantity)
          item.destroy!
          return Result.new(success: true, order_item: existing_target, action: :merged, error: nil)
        end

        item.update!(variant_id: target_variant_id)
        Result.new(success: true, order_item: item, action: :changed, error: nil)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, order_item: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    rescue => e
      Result.new(success: false, order_item: nil, action: :error, error: e.message)
    end
  end
end
```

---

## 7. PAȘI DEPLOY

1. `rails variants:audit` - verifică starea
2. `rails db:migrate` (M1) - adaugă coloane
3. `rails db:migrate` (M2) - cleanup
4. `rails db:migrate` (M3) - constraints
5. Deploy cod
6. `rails variants:audit` - verificare finală

---

## 8. COMPARAȚIE CU PLATFORME

| Acțiune | WooCommerce | Shopify | Solidus | V5.2.1 |
|---------|-------------|---------|---------|------|
| Creare variantă | ✅ | ✅ | ✅ | ✅ |
| Dezactivare | ✅ | ✅ | ✅ | ✅ |
| Reactivare | ✅ | ✅ | ✅ | ✅ |
| Schimbare preț/stock | ✅ | ✅ | ✅ | ✅ |
| Schimbare combinație | ✅ | ✅ | ✅ | ✅ |
| Default pe produs cu opțiuni | ✅ | ✅ | ✅ | ✅ |
| Multiple draft-uri | ✅ | ✅ | ✅ | ✅ |
| Checkout atomic | ✅ | ✅ | ✅ | ✅ |
| Comenzi imutabile | ✅ | ✅ | ✅ | ✅ |

**IDENTIC!** ✅


Planul V5.2.1 e complet și gata de implementare.


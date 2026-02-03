# PLAN VARIANTE V8.0.2 - Implementation Ready + Multi-Source Feeds + Multi-Account + Hardened + Deadlock-Safe + Lock-Order-Hardened + Fail-Fast + Runtime-Verified + DRY + Nested-Tx-Safe + DB-Portable + Defensive-Guards + Multi-DB-Safe + Xact-Lock-Anchored + Serialization-Tested + De-Flaked + Observability-Ready + Bugfix-Hardened + Idempotency-Hardened + Transaction-Guard-Hardened

> **V8.0.2 Changelog:**
> - **Fix 4**: Metric drift - folosește `VariantSyncConfig.increment_legacy_lock_counter` în loc de StatsD direct
> - **Fix 5**: Idempotency hardening - `create_or_link_new` face lookup pe `:conflict` când variant e nil
> - **Fix 6**: Normalizare `external_id` - `.to_s.strip.presence` (consistent cu `external_sku`)
> - **Fix 7**: `transaction_open_on?` helper - fallback la `open_transactions` dacă `transaction_open?` nu există
> - **Fix 8**: `handle_unique_violation` - returnează `:conflict` în loc de `:linked` când mapping există dar pentru alt variant
> - **Fix 9**: M1 preflight - verifică tipul coloanei `variants.status` înainte de migrare
>
> **V8.0.1 Changelog:**
> - **Fix 1**: `create_or_link_new` - guard `.persisted?` + return `:linked` pentru `:race_condition`
> - **Fix 2**: `update_existing` - `with_variant_transaction_if_needed` pentru multi-DB row-lock safety
> - **Fix 3**: Extract `Variants::OptionValueValidator` - DRY pentru `valid_option_values_for_product?`

## Filozofie

**Admin poate:** Creare/dezactivare/reactivare variantă, schimbare preț/stock/SKU/combinație - oricând.

**Sistemul protejează:**
- Unicitate variantă activă per combinație
- Checkout atomic (stoc, status)
- Snapshot imutabil comenzi
- Price/stock NOT NULL și >= 0
- Identificatori externi unici per sursă (ERP, marketplace, furnizori)

---

## 1. MIGRĂRI

### M1: Add Columns

```ruby
class M1AddVariantsColumns < ActiveRecord::Migration[7.0]
  def change
    # FIX 9 (V8.0.2): Preflight check pentru variants.status
    # Dacă coloana există deja, verificăm că tipul e compatibil cu enum integer.
    # Previne erori opace mai târziu (M3 CHECK, model enum) când tipul e string/boolean/etc.
    if column_exists?(:variants, :status)
      col = connection.columns(:variants).find { |c| c.name == 'status' }
      if col
        # Tipuri acceptate pentru Rails enum (integer-backed)
        allowed_types = [:integer, :bigint]
        unless allowed_types.include?(col.type)
          raise <<~MSG.squish
            ABORT M1: variants.status exists with type #{col.type.inspect},
            but this migration expects integer (for Rails enum 0=active, 1=archived).
            Manual intervention required: either drop the column, rename it,
            or migrate existing data to integer format before running this migration.
          MSG
        end
      end
    else
      add_column :variants, :status, :integer, null: false, default: 0
    end

    # REVERSIBLE: change_column condițional nu e reversibil automat
    if column_exists?(:variants, :options_digest)
      col = connection.columns(:variants).find { |c| c.name == 'options_digest' }
      reversible do |dir|
        dir.up { change_column :variants, :options_digest, :text if col && col.type != :text }
        # dir.down e no-op intenționat (nu știm tipul original)
      end
    else
      add_column :variants, :options_digest, :text
    end
    unless column_exists?(:variants, :external_sku)
      add_column :variants, :external_sku, :string
    end
    add_index :variants, :status, if_not_exists: true

    unless column_exists?(:order_items, :variant_sku)
      add_column :order_items, :variant_sku, :string
    end
    # REVERSIBLE: change_column condițional nu e reversibil automat
    if column_exists?(:order_items, :variant_options_text)
      col = connection.columns(:order_items).find { |c| c.name == 'variant_options_text' }
      reversible do |dir|
        dir.up { change_column :order_items, :variant_options_text, :text if col && col.type != :text }
      end
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

```
═══════════════════════════════════════════════════════════════════════════
H4: ATENȚIE - M2 POATE FI HEAVY PE TABELE MARI
═══════════════════════════════════════════════════════════════════════════

Această migrare execută:
- Multiple UPDATE-uri pe întregul tabel variants
- DELETE-uri cu subquery-uri pe option_value_variants
- Aggregări cu array_agg/string_agg

PE TABELE CU MILIOANE DE RÂNDURI, POATE:
- Ține lock-uri exclusive minute întregi
- Bloca alte operații pe aceste tabele
- Cauza timeout-uri la aplicație
- Genera WAL masiv (replication lag)

RECOMANDĂRI PENTRU PROD:

1. RULEAZĂ ÎN MAINTENANCE WINDOW
   - Anunță downtime sau "degraded performance"
   - Preferabil când traficul e minim

2. MONITORIZEAZĂ LOCK WAITS
   SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock';
   SELECT * FROM pg_locks WHERE NOT granted;

3. DACĂ TABELUL E MARE (>1M rows), CONSIDERĂ BATCHING:

   # În loc de UPDATE global:
   Variant.where(sku: nil).find_in_batches(batch_size: 10_000) do |batch|
     Variant.where(id: batch.map(&:id)).update_all("sku = 'VAR-' || id")
     sleep 0.1  # Dă timp replication-ului să țină pasul
   end

4. TESTEAZĂ PE CLONE/STAGING CU DATE REALE
   - Măsoară timpul efectiv
   - Verifică impact pe metrics (latency, error rate)

5. BACKUP ÎNAINTE
   pg_dump -Fc database_name > backup_before_m2.dump
═══════════════════════════════════════════════════════════════════════════
```

```ruby
class M2CleanupVariantsData < ActiveRecord::Migration[7.0]
  def up
    # POSTGRES-ONLY: Această migrare folosește sintaxă specifică Postgres
    # (BTRIM, NULLIF, array_agg, ctid, string_agg). În test cu SQLite, skip.
    unless connection.adapter_name =~ /postgres/i
      say "Skipping M2 - Postgres-only migration (current adapter: #{connection.adapter_name})"
      return
    end

    # 1. Normalizare
    execute "UPDATE variants SET options_digest = NULLIF(BTRIM(options_digest), '')"
    execute "UPDATE variants SET external_sku = NULLIF(BTRIM(external_sku), '')"
    execute "UPDATE variants SET sku = BTRIM(sku) WHERE sku IS NOT NULL"
    execute "UPDATE variants SET sku = 'VAR-' || id WHERE sku IS NULL OR sku = ''"

    # 2. PREFLIGHT: SKU duplicate
    sku_duplicates = execute(<<~SQL).to_a
      SELECT product_id, sku, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants WHERE sku IS NOT NULL
      GROUP BY product_id, sku HAVING COUNT(*) > 1
    SQL
    if sku_duplicates.any?
      sku_duplicates.each { |r| puts "SKU dup: Product #{r['product_id']}, SKU '#{r['sku']}' - IDs: #{r['variant_ids']}" }
      # FAIL-FAST: Pică în toate mediile, nu doar production.
      # M3 va eșua oricum cu eroare SQL generică dacă există duplicate.
      # Mai bine pici aici cu mesaj clar decât mai târziu cu mesaj opac.
      raise "ABORT: Fix SKU duplicates manually!"
    end

    # 2b. PREFLIGHT: external_sku duplicate
    ext_sku_duplicates = execute(<<~SQL).to_a
      SELECT external_sku, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants WHERE external_sku IS NOT NULL
      GROUP BY external_sku HAVING COUNT(*) > 1
    SQL
    if ext_sku_duplicates.any?
      ext_sku_duplicates.each { |r| puts "External SKU dup: '#{r['external_sku']}' - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix external_sku duplicates manually!"
    end

    # 2c. PREFLIGHT: Variante cu multiple valori pe același option_type
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
      raise "ABORT: Variants have multiple values for same option_type. Fix data first."
    end

    # 2d. DEDUPE join tables
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

    # 3. BACKFILL: Calculează digest
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

    # 3b. Nullify digest pentru variante cu doar opțiuni obsolete
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

    # 4. PREFLIGHT: Digest duplicate (active)
    digest_duplicates = execute(<<~SQL).to_a
      SELECT product_id, options_digest, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants
      WHERE options_digest IS NOT NULL AND status = 0
      GROUP BY product_id, options_digest HAVING COUNT(*) > 1
    SQL
    if digest_duplicates.any?
      digest_duplicates.each { |r| puts "Digest dup: Product #{r['product_id']}, '#{r['options_digest']}' - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix digest duplicates manually!"
    end

    # 5. CLEANUP: Dezactivează default active duplicate
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

    # 6b. PREFLIGHT: status invalid (în afara enum 0/1)
    invalid_status = execute(<<~SQL).to_a
      SELECT status, COUNT(*) as cnt, array_agg(id ORDER BY id) as variant_ids
      FROM variants
      WHERE status NOT IN (0, 1)
      GROUP BY status
    SQL
    if invalid_status.any?
      invalid_status.each { |r| puts "Invalid status #{r['status']}: #{r['cnt']} variants - IDs: #{r['variant_ids']}" }
      raise "ABORT: Fix invalid status values manually!"
    end

    # 7. CLEANUP ORFANI
    execute(<<~SQL)
      DELETE FROM option_value_variants ovv
      WHERE NOT EXISTS (SELECT 1 FROM variants v WHERE v.id = ovv.variant_id)
         OR NOT EXISTS (SELECT 1 FROM option_values ov WHERE ov.id = ovv.option_value_id)
    SQL

    execute(<<~SQL)
      DELETE FROM variants v
      WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.id = v.product_id)
        AND NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.variant_id = v.id)
    SQL

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
      raise "ABORT: Orphan variants referenced by orders. Fix data!"
    end

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
    # ═══════════════════════════════════════════════════════════════════════════
    # UNIVERSAL INDEXES (funcționează pe orice DB)
    # ═══════════════════════════════════════════════════════════════════════════

    # Basic unique index (fără WHERE clause)
    add_index :variants, [:product_id, :sku], unique: true,
              name: 'idx_unique_sku_per_product', if_not_exists: true

    # JOIN TABLE INDEXES
    add_index :option_value_variants, [:variant_id, :option_value_id], unique: true,
              name: 'idx_unique_ovv', if_not_exists: true
    add_index :option_value_variants, :variant_id, name: 'idx_ovv_variant', if_not_exists: true
    add_index :option_value_variants, :option_value_id, name: 'idx_ovv_option_value', if_not_exists: true

    # FOREIGN KEYS (universal)
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

    # PERFORMANCE INDEXES (universal)
    add_index :product_option_types, [:product_id, :option_type_id], unique: true,
              name: 'idx_unique_product_option_type', if_not_exists: true
    add_index :product_option_types, :product_id, name: 'idx_pot_product', if_not_exists: true
    add_index :option_values, :option_type_id, name: 'idx_ov_type', if_not_exists: true

    # ═══════════════════════════════════════════════════════════════════════════
    # POSTGRES-ONLY: Partial indexes + CHECK constraints
    # SQLite/MySQL nu suportă partial indexes sau CHECK constraints în același mod
    # ═══════════════════════════════════════════════════════════════════════════
    return unless postgres?

    # PARTIAL UNIQUE INDEXES (Postgres-only)
    add_index :variants, [:product_id, :options_digest], unique: true,
              where: "options_digest IS NOT NULL AND status = 0",
              name: 'idx_unique_active_options_per_product', if_not_exists: true

    add_index :variants, [:product_id], unique: true,
              where: "options_digest IS NULL AND status = 0",
              name: 'idx_unique_active_default_variant', if_not_exists: true

    add_index :variants, :external_sku, unique: true,
              where: "external_sku IS NOT NULL",
              name: 'idx_unique_external_sku', if_not_exists: true

    # CHECK CONSTRAINTS (Postgres-only - constraint_exists? folosește pg_constraint)
    unless constraint_exists?(:variants, 'chk_variants_price_positive')
      add_check_constraint :variants, 'price IS NOT NULL AND price >= 0',
                           name: 'chk_variants_price_positive'
    end
    unless constraint_exists?(:variants, 'chk_variants_stock_positive')
      add_check_constraint :variants, 'stock IS NOT NULL AND stock >= 0',
                           name: 'chk_variants_stock_positive'
    end
    unless constraint_exists?(:variants, 'chk_variants_status_enum')
      add_check_constraint :variants, 'status IN (0, 1)',
                           name: 'chk_variants_status_enum'
    end
  end

  private

  def postgres?
    connection.adapter_name =~ /postgres/i
  end

  def constraint_exists?(table, name)
    # Postgres-only: folosește pg_constraint catalog
    # ROBUST: Folosim `connection` (nu ActiveRecord::Base.connection) pentru multi-db safety
    # și `quote` pentru a evita SQL injection (chiar dacă input-ul nu e user-provided)
    query = <<~SQL
      SELECT 1
      FROM pg_constraint
      WHERE conname = #{connection.quote(name)}
        AND conrelid = #{connection.quote(table.to_s)}::regclass
      LIMIT 1
    SQL
    connection.select_value(query).present?
  end
end
```

### M4: External IDs Mapping Table (pentru feed-uri multiple + multi-account)

```ruby
class M4CreateVariantExternalIds < ActiveRecord::Migration[7.0]
  def change
    # ═══════════════════════════════════════════════════════════════════════════
    # UNIVERSAL: Table creation + indexes (funcționează pe orice DB)
    # ═══════════════════════════════════════════════════════════════════════════

    create_table :variant_external_ids do |t|
      # index: false - evităm index duplicat (adăugăm manual mai jos cu nume explicit)
      t.references :variant, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :source, null: false         # ex: "erp", "emag", "supplier_x"
      t.string :source_account, null: false, default: 'default'  # ex: "emag_ro_1", "erp_company_a"
      t.string :external_id, null: false    # ID-ul din sursa externă
      t.string :external_sku                # SKU-ul din sursa externă (opțional)

      t.timestamps
    end

    # Unicitate per sursă + cont + external_id
    # Permite: (emag, emag_ro_1, 123) și (emag, emag_ro_2, 123) să coexiste
    add_index :variant_external_ids, [:source, :source_account, :external_id], unique: true,
              name: 'idx_unique_source_account_external_id'

    # Pentru lookup rapid după variant (index explicit cu nume consistent)
    add_index :variant_external_ids, :variant_id, name: 'idx_vei_variant'

    # Pentru căutare după source (când vrei toate variantele din ERP etc.)
    add_index :variant_external_ids, :source, name: 'idx_vei_source'

    # Pentru căutare după source + account
    add_index :variant_external_ids, [:source, :source_account], name: 'idx_vei_source_account'

    # ═══════════════════════════════════════════════════════════════════════════
    # POSTGRES-ONLY: CHECK constraints cu regex și btrim()
    # Pe non-Postgres, validările Rails din model asigură aceeași integritate
    # ═══════════════════════════════════════════════════════════════════════════
    return unless connection.adapter_name =~ /postgres/i

    # CHECK: source trebuie să fie lowercase (normalizare la nivel DB)
    # Format: lowercase letter + alphanumeric/underscore, max 50 chars
    add_check_constraint :variant_external_ids,
      "source ~ '^[a-z][a-z0-9_]{0,49}$'",
      name: 'chk_vei_source_format'

    # CHECK: source_account trebuie să fie lowercase
    add_check_constraint :variant_external_ids,
      "source_account ~ '^[a-z][a-z0-9_]{0,49}$'",
      name: 'chk_vei_source_account_format'

    # CHECK: external_id nu poate fi empty/whitespace
    add_check_constraint :variant_external_ids,
      "btrim(external_id) <> ''",
      name: 'chk_vei_external_id_not_empty'

    # CHECK: external_id normalizat (fără leading/trailing whitespace)
    add_check_constraint :variant_external_ids,
      "external_id = btrim(external_id)",
      name: 'chk_vei_external_id_normalized'
  end
end
```

### M5: Backfill External IDs din external_sku existent (opțional)

```ruby
class M5BackfillVariantExternalIds < ActiveRecord::Migration[7.0]
  def up
    # POSTGRES-ONLY: Folosește btrim() și ON CONFLICT (Postgres 9.5+)
    # Pe non-Postgres, skip - datele se vor popula prin VariantSyncService
    unless connection.adapter_name =~ /postgres/i
      say "Skipping M5 - Postgres-only migration (current adapter: #{connection.adapter_name})"
      return
    end

    # Dacă ai deja external_sku populat, îl migrezi ca sursă "legacy" + account "default"
    execute(<<~SQL)
      INSERT INTO variant_external_ids (variant_id, source, source_account, external_id, external_sku, created_at, updated_at)
      SELECT id, 'legacy', 'default', btrim(external_sku), btrim(external_sku), NOW(), NOW()
      FROM variants
      WHERE external_sku IS NOT NULL AND btrim(external_sku) <> ''
      ON CONFLICT (source, source_account, external_id) DO NOTHING
    SQL
  end

  def down
    # POSTGRES-ONLY
    return unless connection.adapter_name =~ /postgres/i

    execute("DELETE FROM variant_external_ids WHERE source = 'legacy' AND source_account = 'default'")
  end
end
```

---

## 2. MODELE

### IdSanitizer (Shared Helper - DRY pentru sanitize_ids)

```ruby
# app/models/concerns/id_sanitizer.rb
#
# Shared helper pentru sanitizarea ID-urilor.
# Centralizat aici pentru a evita drift între servicii.
# FAIL-FAST: Input invalid ridică ArgumentError, nu "silent drop".
#
# SINGLE-SOURCE: Logica e definită O SINGURĂ DATĂ în ClassMethods.
# Instance method-ul delegă la class method pentru zero drift.

module IdSanitizer
  extend ActiveSupport::Concern

  # Instance method delegă la class method (SINGLE-SOURCE pattern)
  def sanitize_ids(input)
    self.class.sanitize_ids(input)
  end
  private :sanitize_ids

  module ClassMethods
    # Sanitizează un array de IDs pentru operații pe variante/opțiuni.
    # FAIL-FAST semantics:
    # - nil / "" / " " → ignorate (drop)
    # - "abc" / "1.5"  → ArgumentError (Integer parse fail)
    # - "0x10" / "1_000" → ArgumentError (H1: doar decimal strict)
    # - 0 / -1         → ArgumentError explicit
    # - "123" / 123    → OK
    #
    # H1 HARDENING: Integer() în Ruby acceptă forme "surpriză":
    # - Integer("0x10") → 16 (hex)
    # - Integer("0b101") → 5 (binary)
    # - Integer("0o17") → 15 (octal)
    # - Integer("1_000") → 1000 (underscore separator)
    # Dacă ID-urile vin din feed-uri externe, acestea pot fi foot-guns.
    # Validăm strict: doar cifre decimale (opțional cu leading/trailing whitespace).
    #
    # @param input [Array, nil] Array de ID-uri (poate fi nil)
    # @return [Array<Integer>] Array sortat de ID-uri pozitive unice
    # @raise [ArgumentError] dacă un ID nu e valid
    STRICT_DECIMAL_REGEX = /\A[1-9]\d*\z/.freeze

    def sanitize_ids(input)
      Array(input).map { |x|
        s = x.to_s.strip
        next nil if s.empty?

        # H1: Validare strictă - doar cifre decimale, fără hex/octal/binary/underscore
        # Permite doar: "1", "123", "999999" etc.
        # Respinge: "0x10", "0b101", "0o17", "1_000", "01" (leading zero)
        unless s.match?(STRICT_DECIMAL_REGEX)
          raise ArgumentError, "ID must be decimal digits only (no hex/octal/underscore), got: #{s.inspect}"
        end

        id = Integer(s)  # Acum e safe - am validat formatul
        raise ArgumentError, "ID must be positive integer, got: #{id}" unless id > 0
        id
      }.compact.uniq.sort
    end
  end
end
```

### AdvisoryLockKey (Shared Helper)

```ruby
# app/models/concerns/advisory_lock_key.rb
#
# Shared helper pentru advisory lock key generation.
# Centralizat aici pentru a evita drift între servicii.
# NOTA: Acest modul nu folosește Zlib direct, deci nu are nevoie de `require 'zlib'`.
# REGULA: Orice fișier care apelează Zlib.crc32() trebuie să aibă `require 'zlib'` local.

module AdvisoryLockKey
  extend ActiveSupport::Concern

  private

  # DB-PORTABLE: Advisory locks sunt Postgres-only
  # Pe alte DB-uri (SQLite, MySQL), returnăm false și skip-uim lock-ul
  #
  # MULTI-DB SAFETY: Folosim advisory_lock_connection pentru a obține
  # conexiunea corectă (poate fi override în clasa care include concern-ul)
  def supports_pg_advisory_locks?
    advisory_lock_connection.adapter_name =~ /postgres/i
  end

  # Conexiunea pe care se execută advisory lock-urile.
  # DEFAULT: VariantExternalId.connection (modelul principal pentru mapping-uri)
  # OVERRIDE: În servicii/modele care folosesc altă conexiune, suprascrie această metodă
  #
  # NOTĂ: Folosim VariantExternalId.connection și nu ActiveRecord::Base.connection
  # pentru a fi safe în scenarii multi-db (role switching, sharding, etc.)
  def advisory_lock_connection
    VariantExternalId.connection
  end

  # PORTABLE GUARD: Verifică dacă conexiunea are tranzacție deschisă
  # FALLBACK: Unele adaptere AR (mai vechi, custom, sau multi-DB) pot să nu implementeze
  # `transaction_open?`. În acest caz, fallback la `open_transactions > 0`.
  #
  # NOTĂ: `open_transactions` returnează nivelul de nesting (0 = fără tranzacție),
  # pe când `transaction_open?` e mai precis (ține cont și de savepoints).
  # Preferăm `transaction_open?` când e disponibil, fallback altfel.
  def transaction_open_on?(conn)
    if conn.respond_to?(:transaction_open?)
      conn.transaction_open?
    elsif conn.respond_to?(:open_transactions)
      conn.open_transactions.to_i > 0
    else
      # Dacă nici unul nu e disponibil, presupunem că e OK (să nu blocăm la runtime)
      # dar logăm warning pentru debugging
      Rails.logger.warn(
        "[AdvisoryLockKey] Connection #{conn.class} does not respond to transaction_open? or open_transactions"
      )
      true
    end
  end

  # FAIL-FAST GUARD: Verifică că suntem într-o tranzacție pe conexiunea corectă
  # pg_advisory_xact_lock NECESITĂ o tranzacție deschisă pe aceeași conexiune.
  # Fără tranzacție, lock-ul se eliberează imediat (tranzacție implicită) și NU serializează nimic.
  #
  # Apelează această metodă la începutul oricărui acquire_*_lock pentru a prinde bug-uri
  # de tip "tranzacție pe altă conexiune" instant în dev/test, nu silent fail în prod.
  def assert_transaction_open_on_lock_connection!
    return unless supports_pg_advisory_locks?

    unless transaction_open_on?(advisory_lock_connection)
      # SAFE-NAV: pool/db_config/name pot fi nil în test adapters sau config-uri custom
      # Evităm NoMethodError în timpul construirii mesajului de eroare
      db_name = advisory_lock_connection.pool&.db_config&.name || "unknown"
      raise RuntimeError, <<~MSG.squish
        pg_advisory_xact_lock requires an open transaction on advisory_lock_connection.
        Current connection (#{db_name}) has no open transaction.
        Ensure you call this from within VariantExternalId.transaction { ... } block.
      MSG
    end
  end

  # Convertește CRC32 (unsigned 32-bit) la signed int32 pentru Postgres
  # pg_advisory_xact_lock(int, int) cere int4 semnat (-2^31 .. 2^31-1)
  # CRC32 returnează 0..2^32-1, deci valori >= 2^31 ar da "integer out of range"
  def int32(u)
    u &= 0xffff_ffff
    u >= 0x8000_0000 ? u - 0x1_0000_0000 : u
  end
end
```

### VariantSyncConfig (Feature Flags + Observability)

```ruby
# config/initializers/variant_sync.rb
#
# Feature flags și configurare pentru Imports::VariantSyncService.
# Permite controlul gradual al dual-lock deprecation.

Rails.application.configure do
  # ═══════════════════════════════════════════════════════════════════════════
  # DUAL-LOCK DEPRECATION CONTROL
  # ═══════════════════════════════════════════════════════════════════════════
  #
  # CONTEXT: În V7.9.7 am introdus un nou format de advisory lock (2 chei int32)
  # pentru a reduce collision space. Pentru rolling deploy safety, am păstrat
  # și legacy lock-ul (1 cheie bigint) - "dual-lock".
  #
  # CRITERIU DE ELIMINARE (RF2):
  # 1. Confirmă că 100% din fleet e pe V7.9.7+ (via deploy tooling/monitoring)
  # 2. Setează VARIANT_SYNC_DUAL_LOCK_ENABLED=false în staging
  # 3. Monitorizează 7 zile - dacă nu apar probleme de concurență, continuă
  # 4. Setează VARIANT_SYNC_DUAL_LOCK_ENABLED=false în prod
  # 5. Monitorizează 14 zile - verifică variant_sync.legacy_lock_call = 0
  # 6. Dacă legacy_lock_call > 0, există noduri vechi care încă emit legacy lock
  # 7. Când legacy_lock_call = 0 timp de 14+ zile, șterge codul legacy
  #
  # METRICI (RF2):
  # - variant_sync.dual_lock_call  = volumul TOTAL (normal să fie >0 când flag=true)
  # - variant_sync.legacy_lock_call = DOAR legacy lock (CRITERIUL de deprecation)
  #
  # ROLLBACK: Dacă apar probleme după dezactivare, setează dual_lock_enabled=true
  # ═══════════════════════════════════════════════════════════════════════════

  # CASE-INSENSITIVE parsing: "true", "TRUE", "True" toate funcționează
  # .to_s.strip.downcase previne surprize din ops/devops config
  config.x.variant_sync.dual_lock_enabled = ENV.fetch('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'true').to_s.strip.downcase == 'true'
end

# Modul helper pentru acces ușor la config
module VariantSyncConfig
  class << self
    def dual_lock_enabled?
      Rails.configuration.x.variant_sync.dual_lock_enabled
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # METRICI DUAL-LOCK (RF2)
    # ═══════════════════════════════════════════════════════════════════════════
    #
    # Avem DOUĂ metrici separate:
    #
    # 1. variant_sync.dual_lock_call
    #    - Contorizează volumul total de operații când dual_lock e activ
    #    - Utilă pentru a vedea cât trafic procesezi
    #    - Va fi >0 cât timp flag-ul e true (normal)
    #
    # 2. variant_sync.legacy_lock_call
    #    - Contorizează DOAR apelurile legacy lock (din acquire_external_id_lock_legacy)
    #    - CRITERIU DE DEPRECATION: Când VARIANT_SYNC_DUAL_LOCK_ENABLED=false,
    #      această metrică ar trebui să fie 0.
    #    - Dacă e >0 după dezactivare = există noduri vechi (V7.9.6) în fleet
    # ═══════════════════════════════════════════════════════════════════════════

    # Metric pentru volumul dual-lock (nu e criteriu de deprecation)
    def increment_dual_lock_counter
      StatsD.increment('variant_sync.dual_lock_call') if defined?(StatsD)
    end

    # Metric pentru legacy lock - ACEASTA e criteriul de deprecation
    # Emis din acquire_external_id_lock_legacy în fiecare serviciu
    def increment_legacy_lock_counter
      StatsD.increment('variant_sync.legacy_lock_call') if defined?(StatsD)
    end
  end
end

# ═══════════════════════════════════════════════════════════════════════════
# BOOT-TIME LOG: Status dual-lock (o singură dată la startup)
# ═══════════════════════════════════════════════════════════════════════════
Rails.application.config.after_initialize do
  if VariantSyncConfig.dual_lock_enabled?
    Rails.logger.info(
      "[variant_sync] dual_lock_enabled=true (legacy lock ACTIVE for rolling deploy safety). " \
      "To disable: set VARIANT_SYNC_DUAL_LOCK_ENABLED=false after fleet is 100% >=V7.9.7"
    )
  else
    Rails.logger.warn(
      "[variant_sync] dual_lock_enabled=false (legacy lock DISABLED). " \
      "If stable 14+ days, remove *_legacy methods and this config."
    )
  end
end
```

### Variant

```ruby
class Variant < ApplicationRecord
  # IMPORTANT (deadlock safety):
  # Updates care modifică DOAR price/stock/sku NU trebuie să atingă product
  # (fără touch: true, fără callbacks care updatează product).
  # Altfel creăm ordonare V→P și deadlock cu fluxurile P→V (archive!, UpdateOptionTypesService).
  #
  # TEST HINT: Adaugă un test de regresie care verifică că Variant.update(:price)
  # nu declanșează niciun query pe products (via test log inspection sau query counter).

  enum :status, { active: 0, inactive: 1 }, default: :active

  belongs_to :product
  has_many :option_value_variants, dependent: :destroy
  has_many :option_values, through: :option_value_variants
  has_many :order_items, dependent: :nullify
  has_many :variant_external_ids, dependent: :destroy

  validates :sku, presence: true, uniqueness: { scope: :product_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0 }

  validate :no_active_digest_conflict, if: :should_validate_active_digest_conflict?

  before_validation :normalize_identifiers

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

  # Găsește sau creează external ID pentru o sursă + cont
  # IMPORTANT: Normalizăm ÎNAINTE de find_or_create_by! pentru a evita RecordNotUnique
  # când before_validation normalizează și găsește un rând existent post-normalizare
  #
  # DRY: Folosim VariantExternalId.normalize_lookup pentru a avea O SINGURĂ sursă
  # a adevărului pentru normalizare (zero drift între Variant și VariantExternalId)
  #
  # RACE CONDITION: Chiar și cu normalizare, find_or_create_by! poate genera
  # RecordNotUnique când două procese încearcă simultan să creeze același mapping.
  # requires_new: true creează un SAVEPOINT - dacă RecordNotUnique apare, doar
  # savepoint-ul face rollback, nu și tranzacția exterioară.
  def find_or_create_external_id!(source:, external_id:, source_account: 'default', external_sku: nil)
    # DRY: Normalizare via VariantExternalId.normalize_lookup (single source of truth)
    normalized = VariantExternalId.normalize_lookup(
      source: source,
      external_id: external_id,
      source_account: source_account
    )

    VariantExternalId.transaction(requires_new: true) do
      variant_external_ids.find_or_create_by!(normalized) do |vei|
        vei.external_sku = external_sku&.to_s&.strip.presence
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # Race condition: alt proces a creat mapping-ul între find și create
    # IMPORTANT: Facem lookup GLOBAL (nu pe asociație) pentru a găsi mapping-ul
    # chiar dacă aparține altei variante. Apoi verificăm variant_id.
    existing = VariantExternalId.find_by!(normalized)

    # DEFENSIVE CHECK: Mapping-ul trebuie să pointeze la această variantă.
    # Dacă aparține altei variante = conflict (external_id deja folosit).
    # Fără acest guard, am fi căutat în asociație și am fi primit RecordNotFound (opac).
    if existing.variant_id != id
      raise ActiveRecord::RecordNotUnique,
        "External ID #{external_id} already mapped to variant #{existing.variant_id}, " \
        "cannot map to variant #{id}"
    end

    existing
  end

  private

  # Rulează validarea dacă record-ul VA FI activ după save
  # și se schimbă status sau digest.
  def should_validate_active_digest_conflict?
    (will_save_change_to_status? || will_save_change_to_options_digest?) && will_be_active_after_save?
  end

  # Folosim predicate-ul enum pentru a evita probleme cu type casting
  # active? e mai "Rails-native" și nu depinde de string literal
  def will_be_active_after_save?
    active?
  end

  def normalize_identifiers
    self.options_digest = nil if options_digest.is_a?(String) && options_digest.strip.empty?
    self.external_sku = external_sku.strip.presence if external_sku.is_a?(String)
    self.sku = sku.strip if sku.is_a?(String)
  end

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

### VariantExternalId

```ruby
class VariantExternalId < ApplicationRecord
  belongs_to :variant

  validates :source, presence: true
  validates :source_account, presence: true
  validates :external_id, presence: true, uniqueness: { scope: [:source, :source_account] }

  # Format: lowercase, alfanumeric + underscore, 1-50 caractere
  # Exemple valide: "erp", "emag", "supplier_foo", "legacy_2024"
  # Exemple invalide: "ERP" (uppercase), "my-source" (dash), "" (empty)
  SOURCE_FORMAT = /\A[a-z][a-z0-9_]{0,49}\z/

  validates :source, format: {
    with: SOURCE_FORMAT,
    message: "must be lowercase alphanumeric with underscores, start with letter, max 50 chars"
  }
  validates :source_account, format: {
    with: SOURCE_FORMAT,
    message: "must be lowercase alphanumeric with underscores, start with letter, max 50 chars"
  }

  before_validation :normalize_values

  # Găsește varianta după sursă + cont + external_id
  # IMPORTANT: Normalizează argumentele pentru a evita miss-uri din cauza
  # whitespace sau case mismatch (datele în DB sunt deja normalizate)
  def self.find_variant(source:, external_id:, source_account: 'default')
    attrs = normalize_lookup(source: source, external_id: external_id, source_account: source_account)
    find_by(attrs)&.variant
  end

  # Găsește mapping-ul
  # IMPORTANT: Normalizează argumentele (vezi find_variant)
  def self.find_mapping(source:, external_id:, source_account: 'default')
    attrs = normalize_lookup(source: source, external_id: external_id, source_account: source_account)
    find_by(attrs)
  end

  # Lista variantelor pentru un source + account
  # IMPORTANT: Normalizează argumentele
  def self.for_source(source, source_account: nil)
    normalized_source = source.to_s.strip.downcase
    scope = where(source: normalized_source)
    if source_account
      normalized_account = source_account.to_s.strip.downcase.presence || 'default'
      scope = scope.where(source_account: normalized_account)
    end
    scope
  end

  # Helper: normalizează argumentele de lookup identic cu normalize_values
  # Previne miss-uri când caller-ul pasează " ERP " în loc de "erp"
  def self.normalize_lookup(source:, external_id:, source_account: 'default')
    {
      source: source.to_s.strip.downcase,
      source_account: source_account.to_s.strip.downcase.presence || 'default',
      external_id: external_id.to_s.strip
    }
  end

  private

  def normalize_values
    self.source = source.to_s.strip.downcase if source.present?
    self.source_account = source_account.to_s.strip.downcase.presence || 'default'
    # NORMALIZATION FIX (V8.0.2): Aplicăm .to_s.strip.presence necondiționat pentru
    # a transforma whitespace-only (" ") în nil. Astfel validarea presence pică corect,
    # iar mesajele de eroare și debug sunt consistente cu DB checks (btrim).
    self.external_id = external_id.to_s.strip.presence
    # NORMALIZATION FIX: Nu folosim `if external_sku.present?` pentru că " " (whitespace-only)
    # e considerat blank? (deci present? returnează FALSE), și guard-ul `if external_sku.present?`
    # ar fi SKIP-uit normalizarea, lăsând " " să ajungă în DB.
    # Cu `.to_s.strip.presence` aplicat necondiționat, whitespace-only devine nil corect.
    self.external_sku = external_sku.to_s.strip.presence
  end
end
```

### OptionValueVariant

```ruby
class OptionValueVariant < ApplicationRecord
  belongs_to :variant
  belongs_to :option_value
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
      # DEADLOCK-SAFE: Lock pe product ÎNAINTE de variants
      # Respectă ordinea canonică P → V (la fel ca toate serviciile pe produs)
      lock!

      # IMPORTANT: Nu folosim direct .lock.update_all() pentru că update_all
      # poate lua lock-urile în ordine nedeterministă (dictată de plan).
      # În schimb: SELECT FOR UPDATE în ordine, apoi UPDATE pe IDs deja blocate.
      locked_variant_ids = variants.order(:id).lock.pluck(:id)
      Variant.where(id: locked_variant_ids).update_all(status: Variant.statuses[:inactive]) if locked_variant_ids.any?

      update!(archived: true, archived_at: Time.current)
    end
  end
end
```

---

## 3. SERVICII

### Variants::OptionValueValidator (NOU - V8.0.1)

```ruby
# app/services/variants/option_value_validator.rb
# DRY: Validare opțiuni extrasă din CreateOrReactivateService și UpdateOptionsService
# pentru a elimina duplicarea și riscul de drift.
module Variants
  module OptionValueValidator
    # Verifică că toate option_value_ids:
    # 1. Există în DB
    # 2. Au option_type-uri distincte (nu 2 valori din același tip)
    # 3. Aparțin unor option_types asociate produsului
    #
    # @param product [Product] produsul pentru care validăm
    # @param ids [Array<Integer>] IDs de OptionValue
    # @return [Boolean] true dacă toate validările trec
    def valid_option_values_for_product?(product, ids)
      return true if ids.empty?

      rows = OptionValue.where(id: ids).pluck(:id, :option_type_id)
      return false if rows.size != ids.size  # unele IDs nu există

      type_ids = rows.map(&:last)
      return false if type_ids.size != type_ids.uniq.size  # duplicate pe același tip

      allowed = ProductOptionType.where(product_id: product.id).pluck(:option_type_id)
      (type_ids - allowed).empty?  # toate tipurile sunt asociate produsului
    end
  end
end
```

### Variants::CreateOrReactivateService

```ruby
module Variants
  class CreateOrReactivateService
    include IdSanitizer  # Shared helper pentru sanitize_ids
    include OptionValueValidator  # DRY: validare opțiuni (V8.0.1)

    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true)

    # Atribute permise pentru update (allowlist)
    # NOTE: external_sku NU e inclus - pentru feed-uri folosește variant_external_ids
    PERMITTED_ATTRS = %i[sku price stock vat_rate].freeze

    def initialize(product)
      @product = product
    end

    def call(option_value_ids, attributes = {})
      option_value_ids = sanitize_ids(option_value_ids)

      # Lock pe product pentru a serializa cu UpdateOptionTypesService
      # și a evita race conditions pe option_types/digest
      #
      # IMPORTANT: requires_new: true creează SAVEPOINT când suntem apelați
      # dintr-o tranzacție externă (ex: VariantSyncService). Fără el, dacă apare
      # RecordNotUnique și facem rescue, tranzacția exterioară devine "poisoned"
      # și toate operațiile ulterioare vor pica cu "current transaction is aborted".
      @product.transaction(requires_new: true) do
        @product.lock!

        digest = option_value_ids.empty? ? nil : option_value_ids.join('-')
        desired_status = normalize_status(attributes[:status] || attributes["status"])

        return invalid("Unele opțiuni nu aparțin produsului") unless valid_option_values_for_product?(@product, option_value_ids)

        if desired_status == :inactive
          return create_new(option_value_ids, attributes)
        end

        existing = find_existing_variant(digest)

        if existing
          handle_existing(existing, attributes)
        else
          create_new(option_value_ids, attributes)
        end
      end
    rescue ActiveRecord::RecordNotUnique => e
      handle_unique_violation(e, option_value_ids.empty? ? nil : option_value_ids.join('-'))
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, variant: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    rescue ArgumentError => e
      # FAIL-FAST dar fără 500: sanitize_ids ridică ArgumentError pe input invalid
      Result.new(success: false, variant: nil, action: :invalid, error: e.message)
    end

    private

    def handle_unique_violation(exception, digest)
      msg = exception.cause&.message.to_s
      msg = exception.message.to_s if msg.strip.empty?

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

      handle_race_condition(exception, digest)
    end

    # sanitize_ids e definit în IdSanitizer concern
    # valid_option_values_for_product? e definit în OptionValueValidator concern (V8.0.1)

    # NOTE: query direct pe Variant ca să evităm cache-ul asociației @product.variants
    def find_existing_variant(digest)
      scope = Variant.where(product_id: @product.id)
      if digest.nil?
        scope.find_by(options_digest: nil, status: :active) ||
          scope.where(options_digest: nil).order(:id).first
      else
        scope.find_by(options_digest: digest, status: :active) ||
          scope.where(options_digest: digest).order(:id).first
      end
    end

    def handle_existing(existing, attributes)
      desired_status = normalize_status(attributes[:status] || attributes["status"])
      # Folosește allowlist pentru atribute permise
      safe_attrs = attributes.slice(*PERMITTED_ATTRS, *PERMITTED_ATTRS.map(&:to_s))

      if existing.active?
        Result.new(success: false, variant: existing, action: :already_exists,
                   error: "Combinația există deja și e activă (SKU: #{existing.sku})")
      else
        existing.update!(safe_attrs.merge(status: desired_status))
        Result.new(success: true, variant: existing, action: :reactivated, error: nil)
      end
    end

    def create_new(option_value_ids, attributes)
      desired_status = normalize_status(attributes[:status] || attributes["status"])
      # Folosește allowlist pentru atribute permise
      safe_attrs = attributes.slice(*PERMITTED_ATTRS, *PERMITTED_ATTRS.map(&:to_s))

      # Tranzacția externă (din call) deja ține lock pe product
      variant = @product.variants.create!(safe_attrs.merge(status: :inactive, options_digest: nil))
      option_value_ids.each { |id| variant.option_value_variants.create!(option_value_id: id) }

      new_digest = option_value_ids.empty? ? nil : option_value_ids.join('-')
      variant.update!(options_digest: new_digest, status: desired_status)

      Result.new(success: true, variant: variant, action: :created, error: nil)
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

    def normalize_status(val)
      return :active if val.nil? || (val.respond_to?(:empty?) && val.empty?)
      return Variant.statuses.key(val)&.to_sym || :active if val.is_a?(Integer)
      s = val.to_s
      # Handle string numeric ("0", "1") from forms/JSON
      if s.match?(/\A\d+\z/)
        return Variant.statuses.key(s.to_i)&.to_sym || :active
      end
      Variant.statuses.key?(s) ? s.to_sym : :active
    end
  end
end
```

### Variants::UpdateOptionsService

```ruby
module Variants
  class UpdateOptionsService
    include IdSanitizer  # Shared helper pentru sanitize_ids
    include OptionValueValidator  # DRY: validare opțiuni (V8.0.1)

    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true)

    def initialize(variant)
      @variant = variant
      @product = variant.product
    end

    def call(new_option_value_ids)
      new_option_value_ids = sanitize_ids(new_option_value_ids)

      # Lock pe product pentru a serializa cu UpdateOptionTypesService
      # requires_new: true - vezi comentariul din CreateOrReactivateService
      @product.transaction(requires_new: true) do
        @product.lock!
        @variant.lock!

        # Validare sub lock pentru a evita race condition pe option_types
        unless valid_option_values_for_product?(@product, new_option_value_ids)
          return Result.new(success: false, variant: @variant, action: :invalid,
                           error: "Unele opțiuni nu aparțin acestui produs")
        end

        new_digest = new_option_value_ids.empty? ? nil : new_option_value_ids.join('-')

        # NOTE: query direct pe Variant ca să evităm cache-ul asociației product.variants
        if @variant.active?
          conflict = Variant.where(product_id: @product.id)
                            .where.not(id: @variant.id)
                            .find_by(options_digest: new_digest, status: :active)
          if conflict
            return Result.new(success: false, variant: conflict, action: :conflict,
                             error: "Există deja o variantă activă cu această combinație (SKU: #{conflict.sku})")
          end
        end

        @variant.option_value_variants.destroy_all
        new_option_value_ids.each { |id| @variant.option_value_variants.create!(option_value_id: id) }

        @variant.update!(options_digest: new_digest)
      end

      Result.new(success: true, variant: @variant, action: :updated, error: nil)
    rescue ActiveRecord::RecordNotUnique => e
      Result.new(success: false, variant: @variant, action: :conflict,
                 error: "Există deja o variantă activă cu această combinație")
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, variant: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    rescue ArgumentError => e
      # FAIL-FAST dar fără 500: sanitize_ids ridică ArgumentError pe input invalid
      Result.new(success: false, variant: @variant, action: :invalid, error: e.message)
    end

    private

    # sanitize_ids e definit în IdSanitizer concern
    # valid_option_values_for_product? e definit în OptionValueValidator concern (V8.0.1)
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
        @product.lock!
        @product.option_type_ids = new_option_type_ids

        # DEADLOCK-SAFE: Lock variante în ordine stabilită (ORDER BY id)
        # Asta previne cicluri cu Checkout care ia lock-uri tot în ordine id
        variants = @product.variants.order(:id).lock.to_a
        variant_ids = variants.map(&:id)

        # PERFORMANCE: Bulk digest într-un singur query (elimină N+1)
        allowed_type_ids = ProductOptionType.where(product_id: @product.id).pluck(:option_type_id)

        digest_map = compute_digest_map(variant_ids, allowed_type_ids)

        new_digest_by_id = {}
        variant_ids.each { |id| new_digest_by_id[id] = digest_map[id].presence }

        keep_active_ids = []
        variants.group_by { |v| new_digest_by_id[v.id] }.each do |_digest, group|
          active_in_group = group.select(&:active?)
          if active_in_group.any?
            keep_active_ids << active_in_group.min_by(&:id).id
          end
        end

        deactivated_ids = []
        variants.each do |v|
          next unless v.active?
          next if keep_active_ids.include?(v.id)
          v.update_column(:status, Variant.statuses[:inactive])
          deactivated_ids << v.id
        end

        variants.each do |v|
          nd = new_digest_by_id[v.id]
          v.update_column(:options_digest, nd) if v.options_digest != nd
        end

        { success: true, deactivated_count: deactivated_ids.size, deactivated_ids: deactivated_ids }
      end
    end

    private

    # DB-PORTABLE: Calculează digest map cu fallback pentru non-Postgres
    # Postgres: folosește string_agg (performant, single query)
    # SQLite/MySQL: fallback Ruby (N+1, dar funcțional pentru teste/dev)
    def compute_digest_map(variant_ids, allowed_type_ids)
      return {} if variant_ids.empty? || allowed_type_ids.empty?

      if postgres?
        # PERFORMANT: Single query cu string_agg
        OptionValueVariant
          .joins(:option_value)
          .where(variant_id: variant_ids, option_values: { option_type_id: allowed_type_ids })
          .group(:variant_id)
          .pluck(
            :variant_id,
            Arel.sql("string_agg(option_value_variants.option_value_id::text, '-' ORDER BY option_value_variants.option_value_id)")
          )
          .to_h
      else
        # FALLBACK: Ruby-based pentru SQLite/MySQL (funcțional, nu performant)
        # OK pentru teste și dev, dar în prod ar trebui să fie Postgres
        OptionValueVariant
          .joins(:option_value)
          .where(variant_id: variant_ids, option_values: { option_type_id: allowed_type_ids })
          .group_by(&:variant_id)
          .transform_values { |ovvs| ovvs.map(&:option_value_id).sort.join('-') }
      end
    end

    def postgres?
      @product.class.connection.adapter_name =~ /postgres/i
    end
  end
end
```

### Imports::VariantSyncService (NOU - pentru feed-uri externe)

```ruby
require 'zlib'

module Imports
  class VariantSyncService
    include AdvisoryLockKey  # Shared helper pentru int32()
    include IdSanitizer      # Shared helper pentru sanitize_ids

    Result = Struct.new(:success, :variant, :action, :error, keyword_init: true)

    # @param source [String] Sursa feed-ului (ex: "erp", "emag")
    # @param source_account [String] Contul/instanța din sursă (ex: "emag_ro_1", "erp_company_a")
    def initialize(source:, source_account: 'default')
      @source = source.to_s.strip.downcase
      @source_account = source_account.to_s.strip.downcase.presence || 'default'
    end

    # Sincronizează o variantă din feed extern
    # Găsește după (source, source_account, external_id) sau creează
    #
    # IDEMPOTENT: Dacă varianta există deja (chiar și creată manual/alt feed),
    # va crea mapping-ul și va returna success.
    #
    # HARDENED:
    # - Advisory lock pe (source, source_account, external_id) pentru serializare
    # - Verificare product mismatch când mapping există
    # - Warning dacă opțiunile din feed diferă de cele existente
    def call(external_id:, product:, option_value_ids: [], attributes: {})
      return invalid("external_id obligatoriu") if external_id.blank?
      return invalid("product obligatoriu") unless product

      external_id = external_id.to_s.strip
      option_value_ids = sanitize_ids(option_value_ids)

      # HARDENING: Advisory lock pentru a serializa importul pe cheia externă
      # Previne race condition între workeri care procesează același external_id
      #
      # CRITICAL (Multi-DB Safety): Folosim VariantExternalId.transaction, NU ActiveRecord::Base.transaction
      # pg_advisory_xact_lock este transaction-scoped PE CONEXIUNEA pe care se execută.
      # Dacă tranzacția e pe altă conexiune decât advisory_lock_connection, lock-ul se eliberează
      # imediat (tranzacție implicită) și NU serializează nimic.
      VariantExternalId.transaction do
        acquire_external_id_lock(external_id)

        # Caută mapping existent (sub lock)
        existing_mapping = VariantExternalId.find_mapping(
          source: @source,
          source_account: @source_account,
          external_id: external_id
        )

        if existing_mapping
          update_existing(existing_mapping, product, option_value_ids, attributes)
        else
          create_or_link_new(product, external_id, option_value_ids, attributes)
        end
      end
    rescue ActiveRecord::RecordNotUnique => e
      handle_unique_violation(e, external_id, product)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, variant: e.record, action: :invalid,
                 error: e.record.errors.full_messages.to_sentence)
    rescue ArgumentError => e
      # FAIL-FAST dar fără job crash: sanitize_ids ridică ArgumentError pe input invalid
      Result.new(success: false, variant: nil, action: :invalid, error: e.message)
    end

    private

    # Advisory lock pentru serializare pe (source, source_account, external_id)
    #
    # ROLLING DEPLOY SAFETY:
    # În timpul deploy-ului gradual, workeri vechi (V7.9.6) și noi (V7.9.7) pot rula simultan.
    # Folosim DUAL-LOCK temporar: luăm atât lock-ul legacy (1 cheie) cât și cel nou (2 chei).
    # Asta garantează că:
    # - worker vechi vs worker vechi: serializează pe legacy lock
    # - worker nou vs worker nou: serializează pe ambele (noul e suficient)
    # - worker vechi vs worker nou: serializează pe legacy lock (ambii îl iau)
    #
    # ═══════════════════════════════════════════════════════════════════════════
    # MULTI-DB SAFETY: Wrapper pentru a asigura tranzacție pe conexiunea Variant
    # ═══════════════════════════════════════════════════════════════════════════
    #
    # PROBLEMĂ: În VariantExternalId.transaction, dacă Variant e pe altă conexiune,
    # variant.lock! devine "statement scoped" (se eliberează imediat), nu "transaction scoped".
    #
    # SOLUȚIE: Verificăm dacă există tranzacție pe Variant.connection:
    # - Dacă da (single-DB sau deja deschisă): no-op, executăm direct
    # - Dacă nu (multi-DB): deschidem Variant.transaction(requires_new: true)
    #
    # NOTĂ: requires_new: true creează SAVEPOINT, deci nu interferează cu
    # tranzacția VariantExternalId (care rămâne activă pentru advisory lock).
    def with_variant_transaction_if_needed
      conn = Variant.connection
      if transaction_open_on?(conn)
        yield
      else
        Variant.transaction(requires_new: true) { yield }
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # DEPRECATION TRACKING - vezi VariantSyncConfig pentru criteriul de eliminare
    # Feature flag: VARIANT_SYNC_DUAL_LOCK_ENABLED (default: true)
    # Metric: variant_sync.legacy_lock_acquired (trebuie să fie 0 pentru 14+ zile)
    # ═══════════════════════════════════════════════════════════════════════════
    def acquire_external_id_lock(external_id)
      # DB-PORTABLE: Skip advisory locks pe non-Postgres
      return unless supports_pg_advisory_locks?

      # FAIL-FAST: Verifică că suntem în tranzacție pe conexiunea corectă
      assert_transaction_open_on_lock_connection!

      if VariantSyncConfig.dual_lock_enabled?
        acquire_external_id_lock_legacy(external_id)
        VariantSyncConfig.increment_dual_lock_counter
      end
      acquire_external_id_lock_v797(external_id)
    end

    # Legacy lock (V7.9.6 și anterior) - single bigint key
    # DEPRECATION: Elimină această metodă când dual_lock_enabled = false în prod 14+ zile
    #              și legacy_lock_call metric = 0 (nu mai există noduri vechi în fleet)
    def acquire_external_id_lock_legacy(external_id)
      # Folosim varianta bigint (1 parametru) care acceptă valori > 2^31
      # ::bigint explicit pentru a elimina ambiguitate de casting
      # MULTI-DB SAFETY: advisory_lock_connection (din concern) în loc de ActiveRecord::Base.connection
      key = Zlib.crc32("#{@source}|#{@source_account}|#{external_id}")
      advisory_lock_connection.execute("SELECT pg_advisory_xact_lock(#{key}::bigint)")

      # RF2: Metrică separată pentru legacy lock - utilă pentru deprecation tracking
      # Când VARIANT_SYNC_DUAL_LOCK_ENABLED=false, această metrică ar trebui să fie 0.
      # Dacă e >0, înseamnă că există noduri vechi (V7.9.6) care încă emit legacy lock.
      VariantSyncConfig.increment_legacy_lock_counter
    end

    # New lock (V7.9.7+) - two int32 keys, reduced collision space
    # int32() din AdvisoryLockKey concern
    # MULTI-DB SAFETY: advisory_lock_connection (din concern) în loc de ActiveRecord::Base.connection
    def acquire_external_id_lock_v797(external_id)
      k1 = int32(Zlib.crc32("#{@source}|#{@source_account}"))
      k2 = int32(Zlib.crc32(external_id.to_s))
      advisory_lock_connection.execute("SELECT pg_advisory_xact_lock(#{k1}, #{k2})")
    end

    def update_existing(mapping, expected_product, incoming_option_value_ids, attributes)
      variant = mapping.variant

      # MULTI-DB SAFETY: Asigurăm că lock! și update! se execută într-o tranzacție
      # pe conexiunea Variant. În single-DB, tranzacția VariantExternalId e pe aceeași
      # conexiune și wrapper-ul e no-op. În multi-DB, previne row-lock "statement scoped".
      with_variant_transaction_if_needed do
        # CONCURRENCY STABILIZATION: Lock varianta explicit înainte de citiri
        # Deși UPDATE ia row-lock implicit, vrem să stabilizăm citirile (product_id, options_digest)
        # și să evităm warning-uri inconsistente dacă alt writer modifică între timp.
        # Lock order: A (advisory) → V (variant) - respectă ordinea canonică.
        variant.lock!

        # HARDENING: Verifică product mismatch
        # Dacă feed-ul trimite alt product pentru același external_id = eroare de configurare
        if variant.product_id != expected_product.id
          Rails.logger.error(
            "[VariantSyncService] Product mismatch for #{@source}/#{@source_account}/#{mapping.external_id}: " \
            "mapping points to product #{variant.product_id}, but feed says product #{expected_product.id}"
          )
          return Result.new(
            success: false,
            variant: variant,
            action: :product_mismatch,
            error: "External ID #{mapping.external_id} aparține produsului #{variant.product_id}, " \
                   "nu produsului #{expected_product.id}. Verifică configurarea feed-ului."
          )
        end

        # HARDENING: Warning dacă opțiunile diferă (nu blocăm, doar logăm)
        # Asta detectează feed-uri care "reuse IDs" pentru combinații diferite
        if incoming_option_value_ids.any?
          incoming_digest = incoming_option_value_ids.join('-')
          if variant.options_digest != incoming_digest
            Rails.logger.warn(
              "[VariantSyncService] Options mismatch for #{@source}/#{@source_account}/#{mapping.external_id}: " \
              "variant has digest '#{variant.options_digest}', feed sends '#{incoming_digest}'. " \
              "Ignoring incoming options (update only price/stock)."
            )
          end
        end

        # Actualizează doar price/stock (cele mai frecvente din feed-uri)
        safe_attrs = attributes.slice(:price, :stock, "price", "stock")
        variant.update!(safe_attrs) if safe_attrs.any?
      end

      Result.new(success: true, variant: variant, action: :updated, error: nil)
    end

    def create_or_link_new(product, external_id, option_value_ids, attributes)
      digest = option_value_ids.empty? ? nil : option_value_ids.join('-')

      # IMPORTANT: NU pasăm external_sku la CreateOrReactivateService
      # pentru că ar scrie în variants.external_sku (care are unique index global).
      # external_sku se salvează DOAR în variant_external_ids.
      variant_attrs = attributes.except(:external_sku, "external_sku")

      service = Variants::CreateOrReactivateService.new(product)
      result = service.call(option_value_ids, variant_attrs)

      # IDEMPOTENCY HARDENING (V8.0.2):
      # Dacă create/reactivate a eșuat cu :conflict (DB constraint pe active digest/default),
      # încercăm să găsim varianta existentă și să facem link la external_id.
      # Asta închide gaura unde importul rămânea "neancorat" și genera retry-uri inutile.
      if result.action == :conflict && result.variant.nil?
        existing = find_existing_variant_for_product(product, digest)
        if existing&.persisted?
          create_external_id_mapping!(
            existing,
            external_id,
            attributes[:external_sku] || attributes["external_sku"]
          )
          return Result.new(success: true, variant: existing, action: :linked, error: nil)
        end
      end

      # IDEMPOTENT: Creăm mapping-ul dacă avem o variantă PERSISTATĂ
      # GUARD: result.variant.persisted? previne crash pe RecordNotSaved când
      # CreateOrReactivateService returnează un record ne-salvat (ex: RecordInvalid)
      #
      # RACE_CONDITION FIX: Dacă action e :already_exists sau :race_condition,
      # mapping-ul a fost creat cu succes, deci returnăm success: true cu action: :linked.
      # Asta aliniază rezultatul cu side-effectul produs și elimină retry-uri inutile.
      if result.variant && result.variant.persisted?
        create_external_id_mapping!(
          result.variant,
          external_id,
          attributes[:external_sku] || attributes["external_sku"]
        )

        # Dacă varianta exista deja activă SAU a fost creată de alt proces (race_condition),
        # o considerăm "linked" (success) - mapping-ul a fost creat/găsit
        if result.action == :already_exists || result.action == :race_condition
          return Result.new(success: true, variant: result.variant, action: :linked, error: nil)
        end
      end

      # RF1 FIX: Normalizăm ÎNTOTDEAUNA la Imports::VariantSyncService::Result
      # CreateOrReactivateService returnează propriul Result type care e "duck-type compatible"
      # dar poate cauza probleme la: case result.class, serializări, type checking (Sorbet/RBS)
      Result.new(
        success: result.success,
        variant: result.variant,
        action: result.action,
        error: result.error
      )
    end

    # Deterministic lookup (same semantics as CreateOrReactivateService#find_existing_variant)
    # Folosit pentru idempotency hardening când create/reactivate returnează :conflict cu variant nil
    def find_existing_variant_for_product(product, digest)
      scope = Variant.where(product_id: product.id)
      if digest.nil?
        scope.find_by(options_digest: nil, status: :active) ||
          scope.where(options_digest: nil).order(:id).first
      else
        scope.find_by(options_digest: digest, status: :active) ||
          scope.where(options_digest: digest).order(:id).first
      end
    end

    def create_external_id_mapping!(variant, external_id, external_sku)
      # requires_new: true - această metodă e apelată din tranzacția principală.
      # Fără savepoint, RecordNotUnique ar "otrăvi" tranzacția și find_by! ar pica.
      VariantExternalId.transaction(requires_new: true) do
        variant.variant_external_ids.create!(
          source: @source,
          source_account: @source_account,
          external_id: external_id,
          external_sku: external_sku
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # Race condition: alt proces a creat mapping-ul între timp
      # Returnăm mapping-ul existent (safe - savepoint-ul a făcut rollback, tranzacția e ok)
      existing = VariantExternalId.find_by!(
        source: @source,
        source_account: @source_account,
        external_id: external_id
      )

      # DEFENSIVE CHECK: Mapping-ul găsit trebuie să pointeze la aceeași variantă.
      # În mod normal, advisory lock previne asta pe Postgres, dar:
      # 1. Pe non-Postgres (SQLite/MySQL) advisory lock e no-op
      # 2. Caller extern care nu folosește advisory lock
      # 3. Date corupte / edge cases neașteptate
      if existing.variant_id != variant.id
        raise ActiveRecord::RecordNotUnique,
          "External ID #{external_id} already mapped to variant #{existing.variant_id}, " \
          "cannot map to variant #{variant.id}"
      end

      existing
    end

    def handle_unique_violation(exception, external_id, expected_product)
      msg = exception.cause&.message.to_s
      msg = exception.message.to_s if msg.strip.empty?

      # DB-PORTABLE FALLBACK: Pe non-Postgres (SQLite/MySQL), mesajele de eroare
      # pot să nu conțină numele indexului. În loc să re-raise, încercăm să
      # identificăm mapping-ul existent și să returnăm un rezultat predictibil.
      #
      # Această logică e aplicată ÎNTOTDEAUNA (nu doar pe Postgres) pentru că:
      # 1. Postgres poate schimba formatul mesajului între versiuni
      # 2. SQLite/MySQL au formate diferite
      # 3. E mai safe să ai un fallback decât să pici cu eroare opacă
      known_index = msg.include?('idx_unique_source_account_external_id')

      # Indiferent dacă am identificat indexul sau nu, încercăm lookup
      existing = VariantExternalId.find_mapping(
        source: @source,
        source_account: @source_account,
        external_id: external_id
      )

      if existing
        # INVARIANT #11: External ID nu poate schimba produsul
        # Chiar și în race condition, trebuie să verificăm product mismatch
        if existing.variant.product_id != expected_product.id
          Rails.logger.error(
            "[VariantSyncService] Product mismatch (race) for #{@source}/#{@source_account}/#{external_id}: " \
            "mapping points to product #{existing.variant.product_id}, but feed says product #{expected_product.id}"
          )
          return Result.new(
            success: false,
            variant: existing.variant,
            action: :product_mismatch,
            error: "External ID #{external_id} aparține produsului #{existing.variant.product_id}, " \
                   "nu produsului #{expected_product.id}. Verifică configurarea feed-ului."
          )
        end

        # FIX 8 (V8.0.2): Returnăm :conflict în loc de :linked
        # RAȚIUNE: Am ajuns aici pentru că am primit RecordNotUnique DUPĂ ce find_mapping
        # a returnat nil (altfel n-am fi încercat INSERT). Deci cineva a creat mapping-ul
        # între timp (race condition).
        #
        # PROBLEMA CU :linked: Nu putem ști sigur dacă mapping-ul nou e pentru variant-ul
        # pe care noi încercam să-l creăm sau pentru altul (tranzacția noastră a fost rollback-uită).
        # Returnând success: true am masca un potențial conflict real.
        #
        # SOLUȚIE: Returnăm success: false cu action: :conflict. Apelantul poate:
        # 1. Reîncerca operația (va găsi mapping-ul existent și va merge pe update_existing)
        # 2. Loga și ignora dacă e idempotent job
        # 3. Escalada dacă e operație critică
        Rails.logger.warn(
          "[VariantSyncService] Race condition on external_id #{external_id}: " \
          "mapping created by concurrent worker for variant #{existing.variant_id}. Returning :conflict for safety."
        )
        return Result.new(
          success: false,
          variant: existing.variant,
          action: :conflict,
          error: "External ID #{external_id} a fost mapat concurent la varianta #{existing.variant_id}. Reîncearcă operația."
        )
      end

      # Mapping-ul NU există, deci RecordNotUnique e de la altceva (SKU, digest, etc.)
      # Dacă NU am identificat indexul, logăm pentru debugging
      unless known_index
        Rails.logger.warn(
          "[VariantSyncService] Unidentified RecordNotUnique for #{@source}/#{@source_account}/#{external_id}: #{msg}"
        )
      end

      # Returnăm conflict generic (safe fallback)
      # MESAJ CLAR: Distingem între "external_id conflict" (known_index) și "alt conflict" (necunoscut)
      error_msg = if known_index
        "External ID deja folosit pentru această sursă/cont"
      else
        "Conflict de unicitate (verifică SKU/opțiuni duplicate sau consultă log-urile pentru detalii)"
      end
      Result.new(success: false, variant: nil, action: :conflict, error: error_msg)
    end

    def invalid(message)
      Result.new(success: false, variant: nil, action: :invalid, error: message)
    end

    # sanitize_ids este acum furnizat de IdSanitizer concern
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
        @order.lock!
        raise AlreadyFinalizedError, "Comanda a fost deja procesată" unless @order.status == 'pending'

        items = @order.order_items.lock.order(:id).to_a

        if items.any? { |i| i.variant_id.nil? }
          raise VariantUnavailableError, "Comanda conține item fără variantă"
        end

        items_by_variant = items.group_by(&:variant_id)
        sorted_ids = items_by_variant.keys.compact.sort

        sorted_ids.each do |variant_id|
          variant_items = items_by_variant[variant_id]
          total_qty = variant_items.sum(&:quantity).to_i

          # OPTIMIZARE: Un singur SELECT FOR UPDATE + verificare în loc de UPDATE apoi SELECT
          # Reduce lock time și numărul de query-uri (era: UPDATE + find_by + find + lock!)
          variant = Variant.lock.find_by(id: variant_id, status: :active)
          raise VariantUnavailableError, "Varianta nu e disponibilă" unless variant

          if variant.stock < total_qty
            raise InsufficientStockError, "Stoc insuficient pentru '#{variant.sku}'"
          end

          # UPDATE pe rândul deja blocat
          variant.update_column(:stock, variant.stock - total_qty)

          # Calculăm options_text O SINGURĂ DATĂ per variant (nu per item)
          options_text = variant.option_values.order(:id).pluck(:name).join(', ')
          variant_items.each { |item| snapshot_item(item, variant, options_text) }
        end

        @order.update!(status: 'confirmed')
      end
    end

    private

    # options_text e pre-calculat o singură dată per variant (nu per item)
    def snapshot_item(item, variant, options_text)
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

### Orders::ConcurrencyPolicy (Helper)

```ruby
module Orders
  module ConcurrencyPolicy
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

### Orders::RestockService (pentru Cancel/Refund)

```ruby
module Orders
  class RestockService
    # Restockează variantele pentru o comandă anulată/refund
    # DEADLOCK-SAFE: Respectă ordinea O → I → V* (order id)
    def initialize(order)
      @order = order
    end

    def call
      @order.transaction do
        # Lock order ÎNAINTE de variante (canonic pentru domeniul comenzii)
        @order.lock!

        # Lock items în ordine stabilă
        items = @order.order_items.lock.order(:id).to_a

        # Grupează pe variant_id și sortează pentru lock order
        by_variant = items.group_by(&:variant_id)
        variant_ids = by_variant.keys.compact.sort

        # Lock variante în ordine stabilă (SELECT FOR UPDATE)
        variants = Variant.where(id: variant_ids).order(:id).lock.index_by(&:id)

        restocked = []
        variant_ids.each do |vid|
          variant = variants[vid]
          next unless variant # varianta poate fi ștearsă

          qty = by_variant[vid].sum { |i| i.quantity.to_i }
          next unless qty > 0

          # update_columns pentru a evita callbacks și validări (stocul poate deveni > max etc.)
          variant.update_columns(stock: variant.stock + qty)
          restocked << { variant_id: vid, qty: qty }
        end

        { success: true, restocked: restocked }
      end
    end
  end
end
```

### Variants::BulkLockingService (pentru bulk updates)

```ruby
module Variants
  class BulkLockingService
    extend IdSanitizer::ClassMethods  # Shared helper pentru sanitize_ids

    # DB-PORTABLE: Verifică dacă suntem pe Postgres (pentru CHECK constraints)
    # MULTI-DB SAFE: Folosim Variant.connection, nu ActiveRecord::Base.connection,
    # pentru că în setup-uri cu multiple databases, Variant poate fi pe alt DB.
    def self.postgres?
      Variant.connection.adapter_name =~ /postgres/i
    end

    # Helper pentru operații multi-variant care trebuie să respecte lock order
    # DEADLOCK-SAFE: Lock variante în ORDER BY id
    #
    # Folosește astfel:
    #   Variants::BulkLockingService.with_locked_variants(variant_ids) do |locked_variants|
    #     locked_variants.each { |v| v.update_columns(stock: new_stock) }
    #   end

    # FAIL-FAST: Folosește IdSanitizer pentru consistent behavior
    # - Integer() ridică ArgumentError pe input invalid ("abc", "1.5")
    # - Non-pozitive (0, -1) ridică ArgumentError explicit (nu silent drop)
    # - nil/blank sunt ignorate
    #
    # @param ids [Array] Array de variant IDs (se sanitizează intern)
    # @param sanitized [Boolean] Dacă true, skip sanitizare (pentru internal calls)
    #        ATENȚIE: sanitized: true e un foot-gun dacă e folosit greșit!
    #        Assertion-ul de mai jos previne bypass accidental al fail-fast.
    def self.with_locked_variants(ids, sanitized: false)
      if sanitized
        # GUARD: Previne bypass accidental al fail-fast parsing
        # Caller-ul care spune "am sanitizat deja" trebuie să fi făcut-o corect
        unless ids.is_a?(Array) && ids.all? { |x| x.is_a?(Integer) && x > 0 }
          # Limitare output pentru a evita log spam pe array-uri mari
          # BULLETPROOF: Construim preview și suffix separat pentru a evita
          # erori dacă ids nu e Array (nu are .size/.first)
          preview = ids.is_a?(Array) ? ids.first(10) : ids
          suffix  = ids.is_a?(Array) && ids.size > 10 ? "... (#{ids.size} total)" : ""
          raise ArgumentError, "sanitized: true requires Array of positive Integers, got: #{preview.inspect}#{suffix}"
        end
      else
        ids = sanitize_ids(ids)
      end
      return yield([]) if ids.empty?

      Variant.transaction do
        # Lock în ordine stabilă (SELECT FOR UPDATE cu ORDER BY id)
        locked = Variant.where(id: ids).order(:id).lock.to_a
        yield(locked)
      end
    end

    # Bulk update stock pentru un hash { variant_id => new_stock }
    # DEADLOCK-SAFE: Lock în ordine, apoi update
    # STRICT/FAIL-FAST:
    # - nil/blank KEYS sunt INTERZISE (aproape sigur bug în caller)
    # - Integer() pe values ridică ArgumentError pe input invalid
    def self.bulk_update_stock(stock_by_variant_id)
      return { success: true, updated: [] } if stock_by_variant_id.empty?

      # FAIL-FAST pe nil/blank keys (diferit de sanitize_ids care le ignoră)
      # În context bulk_update, nil key = bug în caller, nu "ignore silently"
      if stock_by_variant_id.keys.any? { |k| k.nil? || k.to_s.strip.empty? }
        raise ArgumentError, "variant_id keys must be present (nil/blank not allowed)"
      end

      ids = sanitize_ids(stock_by_variant_id.keys)
      updated = []

      # sanitized: true evită double-sanitize în with_locked_variants
      with_locked_variants(ids, sanitized: true) do |variants|
        variants.each do |v|
          new_stock = stock_by_variant_id[v.id] || stock_by_variant_id[v.id.to_s]
          next if new_stock.nil?

          new_stock = Integer(new_stock)  # FAIL-FAST: "abc" → ArgumentError

          # DB-PORTABLE: Pe non-Postgres nu avem CHECK constraint, deci validăm aici
          # pentru a păstra invarianta #7 (stock >= 0) consistent pe toate DB-urile
          if !postgres? && new_stock < 0
            raise ActiveRecord::StatementInvalid, "CHECK constraint violated: stock must be >= 0"
          end

          old_stock = v.stock  # Capturăm ÎNAINTE de update_columns
          if old_stock != new_stock
            v.update_columns(stock: new_stock)
            updated << { variant_id: v.id, old_stock: old_stock, new_stock: new_stock }
          end
        end
      end

      { success: true, updated: updated }
    end

    # Bulk update price pentru un hash { variant_id => new_price }
    # STRICT/FAIL-FAST:
    # - nil/blank KEYS sunt INTERZISE (aproape sigur bug în caller)
    # - BigDecimal() pe values ridică ArgumentError pe input invalid
    def self.bulk_update_price(price_by_variant_id)
      return { success: true, updated: [] } if price_by_variant_id.empty?

      # FAIL-FAST pe nil/blank keys
      if price_by_variant_id.keys.any? { |k| k.nil? || k.to_s.strip.empty? }
        raise ArgumentError, "variant_id keys must be present (nil/blank not allowed)"
      end

      ids = sanitize_ids(price_by_variant_id.keys)
      updated = []

      # sanitized: true evită double-sanitize în with_locked_variants
      with_locked_variants(ids, sanitized: true) do |variants|
        variants.each do |v|
          new_price = price_by_variant_id[v.id] || price_by_variant_id[v.id.to_s]
          next if new_price.nil?

          new_price = BigDecimal(new_price.to_s)  # FAIL-FAST: input invalid → error

          # DB-PORTABLE: Pe non-Postgres nu avem CHECK constraint, deci validăm aici
          # pentru a păstra invarianta #7 (price >= 0) consistent pe toate DB-urile
          if !postgres? && new_price < 0
            raise ActiveRecord::StatementInvalid, "CHECK constraint violated: price must be >= 0"
          end

          old_price = v.price  # Capturăm ÎNAINTE de update_columns
          if old_price != new_price
            v.update_columns(price: new_price)
            updated << { variant_id: v.id, old_price: old_price, new_price: new_price }
          end
        end
      end

      { success: true, updated: updated }
    end

    # Make sanitize_ids private (nu expunem ca public API)
    private_class_method :sanitize_ids
  end
end
```

### Variants::AdminExternalIdService (pentru link/unlink din admin)

```ruby
require 'zlib'

module Variants
  class AdminExternalIdService
    include AdvisoryLockKey  # Shared helper pentru int32()

    # Service pentru admin UI: link/unlink external IDs
    # DEADLOCK-SAFE: Folosește același advisory lock ca importul
    #
    # Asta previne race conditions între admin și import jobs

    def initialize(variant)
      @variant = variant
    end

    # Link o variantă la un external ID
    def link(source:, source_account: 'default', external_id:, external_sku: nil)
      # DRY: Folosim normalize_lookup pentru a avea O SINGURĂ sursă a adevărului
      # Evită drift dacă regula de normalizare se schimbă
      normalized = VariantExternalId.normalize_lookup(
        source: source,
        external_id: external_id,
        source_account: source_account
      )

      return { success: false, error: "source obligatoriu" } if normalized[:source].blank?
      return { success: false, error: "external_id obligatoriu" } if normalized[:external_id].blank?

      # CRITICAL (Multi-DB Safety): Folosim VariantExternalId.transaction
      # Vezi comentariul din VariantSyncService#call pentru detalii
      VariantExternalId.transaction do
        acquire_external_id_lock(normalized[:source], normalized[:source_account], normalized[:external_id])

        # Verifică dacă mapping-ul există deja
        existing = VariantExternalId.find_by(normalized)

        if existing
          if existing.variant_id == @variant.id
            return { success: true, action: :already_linked, mapping: existing }
          else
            return {
              success: false,
              error: "External ID deja folosit de varianta #{existing.variant_id}",
              action: :conflict
            }
          end
        end

        mapping = @variant.variant_external_ids.create!(
          **normalized,
          external_sku: external_sku&.to_s&.strip.presence
        )

        { success: true, action: :linked, mapping: mapping }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.record.errors.full_messages.to_sentence }
    rescue ActiveRecord::RecordNotUnique
      { success: false, error: "External ID deja folosit", action: :conflict }
    end

    # Unlink un external ID de la variantă
    def unlink(source:, source_account: 'default', external_id:)
      # DRY: Folosim normalize_lookup (single source of truth)
      normalized = VariantExternalId.normalize_lookup(
        source: source,
        external_id: external_id,
        source_account: source_account
      )

      # CRITICAL (Multi-DB Safety): Folosim VariantExternalId.transaction
      VariantExternalId.transaction do
        acquire_external_id_lock(normalized[:source], normalized[:source_account], normalized[:external_id])

        mapping = @variant.variant_external_ids.find_by(normalized)

        unless mapping
          return { success: false, error: "Mapping nu există", action: :not_found }
        end

        mapping.destroy!
        { success: true, action: :unlinked }
      end
    end

    private

    # ROLLING DEPLOY SAFETY: Dual-lock (consistent cu VariantSyncService)
    # Vezi VariantSyncConfig pentru criteriul de eliminare și feature flag
    def acquire_external_id_lock(source, source_account, external_id)
      # DB-PORTABLE: Skip advisory locks pe non-Postgres
      return unless supports_pg_advisory_locks?

      # FAIL-FAST: Verifică că suntem în tranzacție pe conexiunea corectă
      assert_transaction_open_on_lock_connection!

      if VariantSyncConfig.dual_lock_enabled?
        acquire_external_id_lock_legacy(source, source_account, external_id)
        VariantSyncConfig.increment_dual_lock_counter
      end
      acquire_external_id_lock_v797(source, source_account, external_id)
    end

    # Legacy lock - ::bigint explicit pentru a elimina ambiguitate de casting
    # DEPRECATION: Elimină când dual_lock_enabled = false în prod 14+ zile
    #              și legacy_lock_call metric = 0 (nu mai există noduri vechi în fleet)
    # MULTI-DB SAFETY: advisory_lock_connection (din concern) în loc de ActiveRecord::Base.connection
    def acquire_external_id_lock_legacy(source, source_account, external_id)
      key = Zlib.crc32("#{source}|#{source_account}|#{external_id}")
      advisory_lock_connection.execute("SELECT pg_advisory_xact_lock(#{key}::bigint)")

      # RF2: Metrică separată pentru legacy lock - utilă pentru deprecation tracking
      VariantSyncConfig.increment_legacy_lock_counter
    end

    # New lock - int32() din AdvisoryLockKey concern
    # MULTI-DB SAFETY: advisory_lock_connection (din concern) în loc de ActiveRecord::Base.connection
    def acquire_external_id_lock_v797(source, source_account, external_id)
      k1 = int32(Zlib.crc32("#{source}|#{source_account}"))
      k2 = int32(Zlib.crc32(external_id.to_s))
      advisory_lock_connection.execute("SELECT pg_advisory_xact_lock(#{k1}, #{k2})")
    end
  end
end
```

---

## 4. RAKE TASKS

### Audit

```ruby
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

    # External IDs audit
    if ActiveRecord::Base.connection.table_exists?('variant_external_ids')
      orphan_mappings = VariantExternalId.left_joins(:variant).where(variants: { id: nil }).count
      puts orphan_mappings > 0 ? "❌ Orphan external ID mappings: #{orphan_mappings}" : "✅ No orphan external ID mappings"

      by_source = VariantExternalId.group(:source).count
      puts "📊 External IDs by source: #{by_source}"

      by_source_account = VariantExternalId.group(:source, :source_account).count
      puts "📊 External IDs by source+account: #{by_source_account}"

      # Variante fără mapping (produse proprii)
      variants_without_mapping = Variant.left_joins(:variant_external_ids)
                                        .where(variant_external_ids: { id: nil }).count
      puts "📊 Variants without external mapping (own products): #{variants_without_mapping}"
    end

    puts "=== END AUDIT ==="
  end
end
```

---

## 5. INVARIANTE

```
1. O COMBINAȚIE ACTIVĂ = O SINGURĂ VARIANTĂ ACTIVĂ
2. MAXIM 1 DEFAULT ACTIV PER PRODUS (digest NULL + status active)
3. COMBINAȚIA POATE FI SCHIMBATĂ ORICÂND
4. CUMPĂRABIL = active + complete + stock > 0
4b. CHECKOUT PERMITE = active + stock >= qty
5. STOCUL NU POATE FI DEPĂȘIT (checkout atomic)
6. COMANDA = IMUTABILĂ (snapshot)
7. PRICE/STOCK NOT NULL ȘI >= 0
8. DIGEST SE CALCULEAZĂ EXPLICIT ÎN SERVICII
9. MULTIPLE DRAFT-URI CU ACELAȘI DIGEST = PERMIS (dar max 1 ACTIVE)
10. EXTERNAL ID UNIC PER (source, source_account) - permite multi-source + multi-account
11. UN EXTERNAL ID NU POATE SCHIMBA PRODUSUL - detectat ca :product_mismatch
12. OPȚIUNILE NU SE SCHIMBĂ LA UPDATE DIN FEED - doar price/stock (warning la mismatch)
13. LOCK ORDER CANONIC: A → P → V (în ordine id) → OVV/VEI (previne deadlock)
14. CHECKOUT LOCK ORDER: O → I → V (în ordine id) (domeniu separat, fără ciclu cu P)
```

---

## 5b. LOCK ORDERING (DEADLOCK PREVENTION)

### Ordine canonică pentru domeniul produsului
```
A (advisory) → P (product.lock!) → V* (variants în ORDER BY id) → OVV/VEI
```

### Ordine canonică pentru domeniul comenzii
```
O (order.lock!) → I (order_items.lock) → V* (variants în ORDER BY id)
```

### Matrice deadlock (toate fluxurile)

| Flow | Lock sequence | Safe cu | Note |
|------|---------------|---------|------|
| CreateOrReactivateService | P → V | toate P→V flows | |
| UpdateOptionsService | P → V | toate P→V flows | |
| UpdateOptionTypesService | P → V* (order id) | toate | |
| Product#archive! | P → V* (order id) | toate | |
| VariantSyncService (update) | A → V | P→V flows (wait only) | |
| VariantSyncService (create) | A → P → V | toate | |
| Checkout::FinalizeService | O → I → V* (order id) | toate | Domain Order |
| **Orders::RestockService** | O → I → V* (order id) | toate | Domain Order |
| **Variants::BulkLockingService** | V* (order id) | toate | V-only, fără P/O |
| **Variants::AdminExternalIdService** | A → VEI | toate | Nu ia V lock |

**Legendă:**
- `P` = product.lock!
- `V*` = variants ORDER BY id (SELECT FOR UPDATE)
- `A` = advisory lock (pg_advisory_xact_lock)
- `O` = order.lock!
- `I` = order_items.lock
- `VEI` = variant_external_ids (via FK cascade, nu lock explicit)

**Observații:**
- V*-only flows (BulkLockingService) sunt compatibile cu P→V* și O→I→V* (wait-only, fără ciclu)
- AdminExternalIdService nu ia lock pe Variant, doar pe VEI via advisory

### Pattern-uri INTERZISE (vor cauza deadlock)

```ruby
# ❌ GREȘIT: V înainte de P
variant.lock!
variant.product.lock!

# ❌ GREȘIT: P înainte de A (pe aceeași cheie externă)
product.lock!
acquire_external_id_lock(external_id)

# ❌ GREȘIT: V înainte de O (în flow de cancel/refund)
variant.lock!
order.lock!

# ❌ GREȘIT: Lock pe variante fără ordine stabilită
product.variants.lock  # ordinea e nedeterministă!

# ✅ CORECT: Lock pe variante cu ORDER BY id
product.variants.order(:id).lock
```

### REGULĂ GLOBALĂ (Cross-Domain Writers)

```
15. REGULĂ GLOBALĂ (cross-domain):
    Dacă un flow atinge atât domeniul Order cât și Product, atunci V* trebuie lock-uit ULTIMUL.

    INTERZIS:
    - V → O/I (variant lock înainte de order/items)
    - V → P   (variant lock înainte de product)

    PERMIS:
    - P → V* → (nu mai atinge O)
    - O → I → V* → (nu mai atinge P)
    - P → O → I → V* (dacă chiar trebuie ambele domenii - V* ultimul)
```

Această regulă previne introducerea accidentală de cicluri când se scriu writeri noi care ating ambele domenii.

### Design Assumptions (Isolation Level)

```
DESIGN ASSUMPTION: Isolation level = READ COMMITTED (default Rails/Postgres)

Lock-order design se bazează pe semantica Postgres pentru ORDER BY ... FOR UPDATE:
- În READ COMMITTED, ORDER BY se aplică ÎNAINTE de locking clause
- Postgres returnează rândurile în ordinea ORDER BY, apoi încearcă lock-ul
- Asta garantează că două tranzacții concurente vor încerca lock-urile în aceeași ordine

NOTĂ: Aceasta este o abordare "hardened" (runtime-verified), nu un proof formal.
- Lock ordering reduce semnificativ riscul de deadlock în practică
- Runtime tests verifică că ORDER BY este prezent în query-uri
- Dar nu avem proof formal că NU există alte căi de cod care încalcă ordinea

ATENȚIE: Dacă schimbi isolation level (SERIALIZABLE, REPEATABLE READ),
comportamentul la recheck devine diferit și design-ul ar necesita revizuire.

Testele de lock-order includ assert pe READ COMMITTED pentru a detecta
schimbări accidentale de isolation level.
```

### Notă despre variants.external_sku (legacy)

Câmpul `variants.external_sku` rămâne cu **unique index global** și este considerat **legacy/manual**:
- **NU** se mai scrie din feed-uri (folosim `variant_external_ids.external_sku`)
- Poate fi folosit pentru identificatori manuali/admin
- Dacă nu mai e nevoie de el, poate fi deprecat în viitor (drop index + column)

### Design Assumptions (Multi-DB) - H2

```
═══════════════════════════════════════════════════════════════════════════
H2: MULTI-DB ASSUMPTION - NU EXISTĂ ATOMICITATE CROSS-DB
═══════════════════════════════════════════════════════════════════════════

CONTEXT:
Codul suportă scenarii unde VariantExternalId și Variant sunt pe DB-uri diferite
(ex: sharding, database-per-service, role switching).

LIMITARE FUNDAMENTALĂ:
- VariantExternalId.transaction + Variant.transaction (pe DB-uri diferite) = NU E ACID
- "All-or-nothing" NU e garantat cross-DB
- 2PC (two-phase commit) NU e implementat

CE FACEM ÎN LOC:
1. IDEMPOTENCY: Operațiile pot fi re-rulate safe (find_or_create patterns)
2. ADVISORY LOCKS: Serializăm pe external_id pentru a reduce race conditions
3. SAVEPOINTS: Izolăm erorile DB pentru a nu "otrăvi" tranzacții externe
4. FALLBACK LOGIC: handle_unique_violation recuperează din race conditions

SCENARII DE FAILURE POSIBILE:
1. Variant creat dar mapping VEI fail → varianta există fără mapping
   RECOVERY: Re-rulează import-ul (idempotent)

2. Mapping creat dar Variant update fail → mapping pointează la date vechi
   RECOVERY: Re-rulează import-ul (update va funcționa)

3. Crash între operații → stare parțial actualizată
   RECOVERY: Re-rulează import-ul (idempotent)

RECOMANDARE PROD:
- Dacă single-DB: totul e ACID, fără griji
- Dacă multi-DB: monitorizează discrepanțe și rulează reconciliation jobs periodic
- Logurile de warning (product_mismatch, options mismatch) ajută la detectare

NU VĂ AȘTEPTAȚI LA:
- Rollback automat cross-DB
- Comportament atomic când DB-urile sunt diferite
═══════════════════════════════════════════════════════════════════════════
```

---

## 5c. TESTE DE REGRESIE (Lock Safety)

### Test: IdSanitizer unit spec (CRITICAL - single point of failure)

```ruby
# spec/models/concerns/id_sanitizer_spec.rb
#
# CRITICAL: Toate serviciile depind de acest concern.
# Orice regresie aici = bug în toate flow-urile de ID handling.

RSpec.describe IdSanitizer do
  # Test class care include concern-ul
  let(:test_class) do
    Class.new do
      extend IdSanitizer::ClassMethods
      include IdSanitizer

      # Expose private method pentru testare
      def self.test_sanitize(input)
        sanitize_ids(input)
      end

      def test_sanitize(input)
        sanitize_ids(input)
      end
    end
  end

  let(:instance) { test_class.new }

  describe ".sanitize_ids (class method)" do
    subject { test_class.test_sanitize(input) }

    context "with valid integer IDs" do
      let(:input) { [1, 2, 3] }
      it { is_expected.to eq([1, 2, 3]) }
    end

    context "with valid string IDs" do
      let(:input) { ["1", "2", "3"] }
      it { is_expected.to eq([1, 2, 3]) }
    end

    context "with mixed integer and string IDs" do
      let(:input) { [1, "2", 3] }
      it { is_expected.to eq([1, 2, 3]) }
    end

    context "with whitespace-padded strings" do
      let(:input) { [" 1 ", "  2", "3  "] }
      it { is_expected.to eq([1, 2, 3]) }
    end

    context "with nil input" do
      let(:input) { nil }
      it { is_expected.to eq([]) }
    end

    context "with empty array" do
      let(:input) { [] }
      it { is_expected.to eq([]) }
    end

    context "with nil elements (dropped silently)" do
      let(:input) { [1, nil, 3] }
      it { is_expected.to eq([1, 3]) }
    end

    context "with empty string elements (dropped silently)" do
      let(:input) { [1, "", 3] }
      it { is_expected.to eq([1, 3]) }
    end

    context "with whitespace-only elements (dropped silently)" do
      let(:input) { [1, "   ", 3] }
      it { is_expected.to eq([1, 3]) }
    end

    context "with duplicates (deduped)" do
      let(:input) { [3, 1, 2, 1, 3] }
      it { is_expected.to eq([1, 2, 3]) }
    end

    context "with unsorted input (sorted)" do
      let(:input) { [3, 1, 2] }
      it { is_expected.to eq([1, 2, 3]) }
    end

    # FAIL-FAST: non-numeric strings
    # NOTE: Nu verificăm mesajul exact al Ruby (variază între versiuni)
    # Integer("abc") poate da "invalid value for Integer" sau altă formulare
    context "with non-numeric string" do
      let(:input) { ["abc"] }
      it "raises ArgumentError (Ruby's Integer() parse failure)" do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    context "with float string" do
      let(:input) { ["1.5"] }
      it "raises ArgumentError (Ruby's Integer() parse failure)" do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    context "with mixed valid and invalid" do
      let(:input) { [1, "abc", 3] }
      it "raises ArgumentError (fail-fast, not partial success)" do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    # FAIL-FAST: non-positive integers
    context "with zero" do
      let(:input) { [0] }
      it "raises ArgumentError with explicit message" do
        expect { subject }.to raise_error(ArgumentError, /ID must be positive integer, got: 0/)
      end
    end

    context "with negative integer" do
      let(:input) { [-1] }
      it "raises ArgumentError with explicit message" do
        expect { subject }.to raise_error(ArgumentError, /ID must be positive integer, got: -1/)
      end
    end

    context "with zero as string" do
      let(:input) { ["0"] }
      it "raises ArgumentError" do
        expect { subject }.to raise_error(ArgumentError, /ID must be positive integer, got: 0/)
      end
    end

    context "with negative as string" do
      let(:input) { ["-5"] }
      it "raises ArgumentError" do
        expect { subject }.to raise_error(ArgumentError, /ID must be positive integer, got: -5/)
      end
    end

    # H1 HARDENING: Ruby Integer() acceptă forme "surpriză"
    context "with hex string (H1)" do
      let(:input) { ["0x10"] }
      it "raises ArgumentError (no hex allowed)" do
        expect { subject }.to raise_error(ArgumentError, /decimal digits only/)
      end
    end

    context "with binary string (H1)" do
      let(:input) { ["0b101"] }
      it "raises ArgumentError (no binary allowed)" do
        expect { subject }.to raise_error(ArgumentError, /decimal digits only/)
      end
    end

    context "with octal string (H1)" do
      let(:input) { ["0o17"] }
      it "raises ArgumentError (no octal allowed)" do
        expect { subject }.to raise_error(ArgumentError, /decimal digits only/)
      end
    end

    context "with underscore separator (H1)" do
      let(:input) { ["1_000"] }
      it "raises ArgumentError (no underscore allowed)" do
        expect { subject }.to raise_error(ArgumentError, /decimal digits only/)
      end
    end

    context "with leading zero (H1)" do
      let(:input) { ["0123"] }
      it "raises ArgumentError (no leading zero - could be octal)" do
        expect { subject }.to raise_error(ArgumentError, /decimal digits only/)
      end
    end
  end

  describe "#sanitize_ids (instance method)" do
    it "delegates to class method (SINGLE-SOURCE verification)" do
      input = [3, 1, 2]
      expect(instance.test_sanitize(input)).to eq(test_class.test_sanitize(input))
    end

    it "produces identical results for all edge cases" do
      edge_cases = [
        nil,
        [],
        [1, 2, 3],
        ["1", "2"],
        [1, nil, "", "  ", 2],
        [3, 1, 1, 2, 3]
      ]

      edge_cases.each do |input|
        expect(instance.test_sanitize(input)).to eq(test_class.test_sanitize(input)),
          "Mismatch for input: #{input.inspect}"
      end
    end
  end
end
```

### Test: Pattern-uri interzise în codebase

```ruby
# spec/lint/lock_safety_spec.rb
#
# IMPORTANT: Scanăm PER FIȘIER pentru a evita false positives din concatenare.
# Când concatenezi fișierele fără separator, regex-ul cu /m poate "trece"
# peste limita dintre fișiere și să detecteze pattern-uri care nu există.

RSpec.describe "Lock safety patterns" do
  # Helper: Scanează toate fișierele Ruby din app/ și returnează matches cu context
  # @param pattern [Regexp] Pattern-ul de căutat
  # @param context_chars [Integer] Caractere de context înainte/după match
  # @return [Array<Hash>] Array de { file:, match:, context: }
  def scan_app_files(pattern, context_chars: 120)
    matches = []

    Dir["app/**/*.rb"].each do |file_path|
      content = File.read(file_path)
      content.scan(pattern) do
        m = Regexp.last_match
        from = [m.begin(0) - context_chars, 0].max
        to   = [m.end(0) + context_chars, content.length].min
        matches << {
          file: file_path,
          match: m[0],
          context: content[from...to]
        }
      end
    end

    matches
  end

  # Helper: Formatează matches pentru mesajul de eroare
  def format_matches(matches)
    matches.map { |m| "#{m[:file]}:\n#{m[:context]}" }.join("\n\n---\n\n")
  end

  it "does not use product.variants.lock without order(:id)" do
    # Pattern periculos: .variants.lock sau .variants.lock! fără .order(:id)
    # IMPORTANT: Regex multiline pentru a detecta chain-uri pe mai multe linii:
    #   product.variants
    #     .lock  # <- periculos, fără order(:id)
    dangerous_pattern = /\.variants\b(?:(?!\.order\(:id\)).)*?\.lock\b/m

    matches = scan_app_files(dangerous_pattern)

    expect(matches).to be_empty,
      "Found unsafe locking pattern (variants.lock without order(:id)):\n\n#{format_matches(matches)}"
  end

  it "does not use Variant.where(...).update_all without prior lock" do
    # Pattern periculos: update_all pe multiple variante fără SELECT FOR UPDATE
    # Acesta e un heuristic - în practică, verifici manual că ai lock înainte
    dangerous_pattern = /Variant\.where\(.*\)\.update_all/

    matches = scan_app_files(dangerous_pattern)

    # Filtrează cazurile sigure (unde știi că ai lock explicit înainte)
    # În practică, fiecare match trebuie verificat manual sau whitelistat
    if matches.any?
      warn "Found Variant.where().update_all patterns - verify each has prior locking:\n\n#{format_matches(matches)}"
    end
  end

  it "does not lock variant before product (V→P ordering)" do
    # Pattern periculos: variant.lock! urmat de variant.product.lock!
    # Asta creează ordonare V→P care face deadlock cu P→V flows
    dangerous_pattern = /variant\.lock!.*variant\.product\.lock!/m

    matches = scan_app_files(dangerous_pattern)

    expect(matches).to be_empty,
      "Found V→P lock ordering (variant.lock! before product.lock!) - this causes deadlock:\n\n#{format_matches(matches)}"
  end
end
```

### Test: Dual-lock deprecation tracking (non-blocking reminder)

```ruby
# spec/config/variant_sync_config_spec.rb
#
# NON-BLOCKING: Acest test nu pică, dar oferă vizibilitate în test output
# pentru a reaminti despre dual-lock deprecation.

RSpec.describe VariantSyncConfig do
  describe "dual-lock deprecation status" do
    it "documents the current state of dual-lock feature flag" do
      # Acest test servește ca reminder vizibil în test output
      # Nu pică, dar printează status-ul curent

      if VariantSyncConfig.dual_lock_enabled?
        puts "\n" + "=" * 70
        puts "⚠️  DUAL-LOCK DEPRECATION REMINDER"
        puts "=" * 70
        puts "dual_lock_enabled = TRUE (legacy lock încă activ)"
        puts ""
        puts "CRITERIU DE ELIMINARE:"
        puts "1. 100% fleet pe V7.9.7+"
        puts "2. variant_sync.legacy_lock_call = 0 timp de 14+ zile"
        puts "3. Nicio instanță < V7.9.7 în monitoring"
        puts ""
        puts "METRICI DISPONIBILE:"
        puts "- variant_sync.dual_lock_call  = volum total (normal să fie >0)"
        puts "- variant_sync.legacy_lock_call = doar legacy (criteriu deprecation)"
        puts ""
        puts "Când criteriile sunt îndeplinite:"
        puts "1. Set VARIANT_SYNC_DUAL_LOCK_ENABLED=false"
        puts "2. Monitorizează 14 zile - legacy_lock_call ar trebui să fie 0"
        puts "3. Dacă legacy_lock_call > 0, există noduri vechi în fleet"
        puts "4. Șterge metodele *_legacy și acest flag"
        puts "=" * 70 + "\n"
      else
        puts "\n" + "=" * 70
        puts "✅ DUAL-LOCK DISABLED"
        puts "=" * 70
        puts "Legacy lock dezactivat. Dacă sunt 14+ zile fără probleme:"
        puts "→ Șterge metodele acquire_external_id_lock_legacy"
        puts "→ Șterge VariantSyncConfig și config-ul asociat"
        puts "→ Șterge acest test"
        puts "=" * 70 + "\n"
      end

      # Testul trece întotdeauna - e doar pentru vizibilitate
      expect(true).to be(true)
    end

    it "has dual_lock_enabled? method available" do
      # Guard: asigură că VariantSyncConfig există și răspunde la metodă
      # Dacă cineva șterge config-ul fără să actualizeze serviciile, testul pică
      expect(VariantSyncConfig).to respond_to(:dual_lock_enabled?)
      expect([true, false]).to include(VariantSyncConfig.dual_lock_enabled?)
    end

    it "has increment_dual_lock_counter method available" do
      # Guard: asigură că metoda de metric există
      expect(VariantSyncConfig).to respond_to(:increment_dual_lock_counter)
    end
  end
end
```

### Test: Nested Transaction Safety (V7.9.17 regression test)

```ruby
# spec/services/variants/nested_transaction_safety_spec.rb
#
# CRITICAL REGRESSION TEST: Dovedește că fix-ul requires_new: true funcționează.
#
# PROBLEMA: Când CreateOrReactivateService e apelat dintr-o tranzacție externă
# (ex: VariantSyncService) și apare RecordNotUnique care e rescue-uită,
# fără SAVEPOINT tranzacția exterioară devine "poisoned" și orice SQL ulterior
# pică cu "PG::InFailedSqlTransaction: current transaction is aborted".
#
# FIX: requires_new: true creează SAVEPOINT, izolând eroarea DB.
#
# IMPORTANT: Acest test e POSTGRES-ONLY. SQLite/MySQL au comportament diferit.
# Testele FORȚEAZĂ DB-level RecordNotUnique prin dezactivarea validărilor Rails
# (care ar prinde eroarea înainte să ajungă la DB).

RSpec.describe "Nested transaction safety", :postgres_only do
  # Skip pe non-Postgres (bug e specific Postgres "transaction aborted")
  before do
    skip "Postgres-only test" unless ActiveRecord::Base.connection.adapter_name =~ /postgres/i
  end

  # Helper: Verifică că tranzacția e încă validă (nu "poisoned")
  # Folosim uncached + select_value pentru a forța un query real la DB
  def assert_transaction_healthy!
    ActiveRecord::Base.uncached do
      ActiveRecord::Base.connection.select_value("SELECT 1")
    end
  end

  # Helper: Dezactivează TOATE UniquenessValidator-urile pentru un model/atribut
  # Asta permite ca duplicatele să ajungă la DB și să arunce RecordNotUnique
  # IMPORTANT: Stubăm toate validatoarele, nu doar primul (pot fi mai multe)
  def disable_uniqueness_validator(model, attribute)
    validators = model.validators_on(attribute)
                      .select { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }
    validators.each { |v| allow(v).to receive(:validate_each).and_return(nil) }
  end

  describe "CreateOrReactivateService - SKU duplicate (DB-level)" do
    it "does not poison outer transaction when RecordNotUnique is rescued" do
      product = create(:product)
      option_type = create(:option_type)
      option_value = create(:option_value, option_type: option_type)
      product.option_types << option_type

      # IMPORTANT: Facem existing NON-DEFAULT (cu digest != nil)
      # Astfel când call-ul vine cu [] (default), find_existing_variant(nil)
      # nu găsește nimic și service-ul încearcă INSERT cu SKU duplicat → DB RecordNotUnique
      existing = create(:variant, product: product, sku: "UNIQUE-SKU", status: :active)
      existing.option_value_ids = [option_value.id]
      existing.update_columns(options_digest: option_value.id.to_s)

      # FORȚĂM DB-level RecordNotUnique: dezactivăm validarea Rails
      disable_uniqueness_validator(Variant, :sku)

      ActiveRecord::Base.transaction do
        # Call cu [] (default variant) dar SKU duplicat
        # find_existing_variant(nil) nu găsește nimic → încearcă create → DB constraint
        result = Variants::CreateOrReactivateService.new(product).call(
          [],
          { sku: "UNIQUE-SKU" }  # SKU duplicat cu existing (care e non-default)
        )

        # Service-ul trebuie să returneze failure (din handle_unique_violation)
        expect(result.success).to be false
        expect(result.error).to eq("SKU deja folosit pentru acest produs")

        # CRITICAL: Fără requires_new: true, această linie ar pica cu
        # "PG::InFailedSqlTransaction: current transaction is aborted"
        assert_transaction_healthy!
      end
    end
  end

  describe "CreateOrReactivateService - digest conflict (DB-level)" do
    it "does not poison outer transaction when RecordNotUnique is rescued" do
      product = create(:product)
      option_type = create(:option_type)
      option_value = create(:option_value, option_type: option_type)
      product.option_types << option_type

      # Creează variantă activă cu acest digest
      existing = create(:variant, product: product, status: :active, sku: "EXISTING-SKU")
      existing.option_value_ids = [option_value.id]
      existing.update_columns(options_digest: option_value.id.to_s)

      # FORȚĂM DB-level RecordNotUnique:
      # 1. Dezactivăm validarea custom care ar detecta conflictul
      # 2. Stub-uim find_existing_variant să returneze nil (să nu găsească existing)
      allow_any_instance_of(Variant).to receive(:should_validate_active_digest_conflict?).and_return(false)
      allow_any_instance_of(Variants::CreateOrReactivateService)
        .to receive(:find_existing_variant).and_return(nil)

      ActiveRecord::Base.transaction do
        result = Variants::CreateOrReactivateService.new(product).call(
          [option_value.id],
          { sku: "NEW-SKU-#{SecureRandom.hex(4)}" }
        )

        # Service-ul trebuie să prindă RecordNotUnique și să returneze conflict
        expect(result.success).to be false
        expect(result.error).to include("variantă activă cu această combinație")

        # CRITICAL: Outer transaction încă validă
        assert_transaction_healthy!
      end
    end
  end

  describe "VariantSyncService#create_external_id_mapping! - duplicate mapping (DB-level)" do
    it "does not poison outer transaction when RecordNotUnique is rescued" do
      product = create(:product)
      variant = create(:variant, product: product)

      # Creează mapping existent
      existing_mapping = variant.variant_external_ids.create!(
        source: "shopify",
        source_account: "store1",
        external_id: "EXT-123"
      )

      # FORȚĂM DB-level RecordNotUnique: dezactivăm validarea Rails
      disable_uniqueness_validator(VariantExternalId, :external_id)

      ActiveRecord::Base.transaction do
        # CORECT: initializer-ul are doar source: și source_account:
        service = Imports::VariantSyncService.new(
          source: "shopify",
          source_account: "store1"
        )

        # Apelăm metoda privată direct (whitebox test)
        # Va încerca create! → RecordNotUnique → rescue → find_by!
        result = service.send(:create_external_id_mapping!, variant, "EXT-123", nil)

        expect(result.id).to eq(existing_mapping.id)

        # CRITICAL: Outer transaction încă validă
        # Fără savepoint în create_external_id_mapping!, find_by! ar pica
        assert_transaction_healthy!
      end
    end
  end

  describe "UpdateOptionsService - digest conflict (DB-level)" do
    it "does not poison outer transaction when RecordNotUnique is rescued" do
      product = create(:product)
      option_type = create(:option_type)
      ov1 = create(:option_value, option_type: option_type)
      ov2 = create(:option_value, option_type: option_type)
      product.option_types << option_type

      v1 = create(:variant, product: product, status: :active, sku: "V1-SKU")
      v1.option_value_ids = [ov1.id]
      v1.update_columns(options_digest: ov1.id.to_s)

      v2 = create(:variant, product: product, status: :active, sku: "V2-SKU")
      v2.option_value_ids = [ov2.id]
      v2.update_columns(options_digest: ov2.id.to_s)

      # FORȚĂM DB-level RecordNotUnique:
      # Service-ul are un check explicit care returnează :conflict înainte de DB.
      # Ca să testăm fix-ul SAVEPOINT, stub-uim active? să returneze false,
      # astfel service-ul sare peste check și încearcă update! direct.
      allow(v2).to receive(:active?).and_return(false)

      ActiveRecord::Base.transaction do
        # Încearcă să schimbi digest-ul lui v2 la cel al lui v1
        # Cu stub-ul de mai sus, va trece de check și va lovi DB index
        result = Variants::UpdateOptionsService.new(v2).call([ov1.id])

        # Ar trebui să prindă RecordNotUnique
        expect(result.success).to be false

        # CRITICAL: Outer transaction încă validă
        assert_transaction_healthy!
      end
    end
  end

  describe "Integration: VariantSyncService full flow with DB-level conflict" do
    it "does not poison outer transaction when nested service hits RecordNotUnique" do
      product = create(:product)
      option_type = create(:option_type)
      ov1 = create(:option_value, option_type: option_type)
      ov2 = create(:option_value, option_type: option_type)
      product.option_types << option_type

      # IMPORTANT: Creează variantă existentă cu digest NON-NULL (non-default)
      # și SKU specific pe care îl vom duplica
      existing = create(:variant, product: product, sku: "FEED-SKU-123", status: :active)
      existing.option_value_ids = [ov1.id]
      existing.update_columns(options_digest: ov1.id.to_s)

      # FORȚĂM DB-level RecordNotUnique pe SKU
      disable_uniqueness_validator(Variant, :sku)

      # Simulează ce face un import job: outer transaction care apelează sync
      ActiveRecord::Base.transaction do
        service = Imports::VariantSyncService.new(
          source: "test_feed",
          source_account: "account1"
        )

        # Prima sincronizare - creează o nouă variantă (digest diferit, SKU unic)
        result1 = service.call(
          external_id: "EXT-001",
          product: product,
          option_value_ids: [ov2.id],  # digest diferit de existing
          attributes: { sku: "NEW-UNIQUE-SKU", price: 100, stock: 50 }
        )
        expect(result1.success).to be true

        # A doua sincronizare - încearcă să creeze variantă cu același SKU dar digest diferit
        # CreateOrReactivateService: find_existing_variant(nil) nu găsește nimic (default)
        # → încearcă create cu SKU "FEED-SKU-123" care există deja → DB RecordNotUnique
        result2 = service.call(
          external_id: "EXT-002",
          product: product,
          option_value_ids: [],  # default variant (digest nil)
          attributes: { sku: "FEED-SKU-123", price: 200, stock: 100 }  # SKU duplicat!
        )

        # Service-ul trebuie să prindă RecordNotUnique și să returneze eroare
        # (nu :linked, pentru că nu are cum să găsească existing cu digest diferit)
        expect(result2.success).to be false
        expect(result2.error).to include("SKU")

        # CRITICAL: După ce nested service a prins RecordNotUnique,
        # outer transaction e încă validă pentru operații ulterioare
        assert_transaction_healthy!

        # Putem continua cu alte operații în aceeași tranzacție
        product.update!(updated_at: Time.current)
        assert_transaction_healthy!
      end
    end
  end
end
```

### Test: Product mismatch în race condition (Fix #1 regression test)

```ruby
# spec/services/imports/variant_sync_service_product_mismatch_spec.rb
#
# CRITICAL REGRESSION TEST: Dovedește că fix-ul pentru product mismatch în
# handle_unique_violation funcționează corect.
#
# SCENARIUL TESTAT:
# 1. Mapping există deja pentru (source, source_account, external_id) → variant_A (product_X)
# 2. Alt import încearcă să creeze mapping pentru același external_id → variant_B (product_Y)
# 3. RecordNotUnique apare (din DB sau din advisory lock pe Postgres)
# 4. handle_unique_violation găsește mapping-ul existent
# 5. TREBUIE să returneze :product_mismatch, NU :linked
#
# Fără acest fix, rezultatul era "success: true, action: :linked" care e GREȘIT:
# - Feed-ul pentru product_Y credea că a "legat" varianta cu succes
# - În realitate, external_id pointează la product_X
# - Actualizările ulterioare ar fi mers la product_X, nu la product_Y

RSpec.describe Imports::VariantSyncService, "product mismatch handling" do
  describe "#handle_unique_violation with existing mapping to different product" do
    let(:source) { 'erp' }
    let(:source_account) { 'company_a' }
    let(:external_id) { 'SHARED-EXT-123' }

    let!(:product_x) { create(:product, name: 'Product X') }
    let!(:product_y) { create(:product, name: 'Product Y') }

    let!(:variant_x) { create(:variant, product: product_x, sku: 'VAR-X') }

    # Mapping existent: external_id pointează la variant_x (din product_x)
    let!(:existing_mapping) do
      VariantExternalId.create!(
        variant: variant_x,
        source: source,
        source_account: source_account,
        external_id: external_id
      )
    end

    it "returns :product_mismatch when trying to link same external_id to different product" do
      service = described_class.new(source: source, source_account: source_account)

      # Încercăm să importăm cu același external_id dar pentru product_y
      result = service.call(
        external_id: external_id,
        product: product_y,  # DIFERIT de product_x!
        option_value_ids: [],
        attributes: { sku: 'VAR-Y-NEW', price: 100, stock: 50 }
      )

      # CRITICAL: Trebuie să fie product_mismatch, NU linked
      expect(result.success).to be false
      expect(result.action).to eq(:product_mismatch)
      expect(result.variant).to eq(variant_x)  # Returnează varianta existentă pentru debugging
      expect(result.error).to include(product_x.id.to_s)
      expect(result.error).to include(product_y.id.to_s)
    end

    it "logs error for product mismatch" do
      service = described_class.new(source: source, source_account: source_account)

      expect(Rails.logger).to receive(:error).with(/Product mismatch.*#{external_id}/)

      service.call(
        external_id: external_id,
        product: product_y,
        option_value_ids: [],
        attributes: { sku: 'VAR-Y-NEW', price: 100, stock: 50 }
      )
    end

    it "does not create new variant when product mismatch detected" do
      service = described_class.new(source: source, source_account: source_account)

      expect {
        service.call(
          external_id: external_id,
          product: product_y,
          option_value_ids: [],
          attributes: { sku: 'VAR-Y-NEW', price: 100, stock: 50 }
        )
      }.not_to change { Variant.count }
    end

    it "does not create new mapping when product mismatch detected" do
      service = described_class.new(source: source, source_account: source_account)

      expect {
        service.call(
          external_id: external_id,
          product: product_y,
          option_value_ids: [],
          attributes: { sku: 'VAR-Y-NEW', price: 100, stock: 50 }
        )
      }.not_to change { VariantExternalId.count }
    end
  end

  describe "#handle_unique_violation in race condition scenario", :postgres_only do
    # Acest test simulează scenariul de race condition:
    # Două procese încearcă simultan să creeze mapping pentru același external_id
    # dar cu produse DIFERITE.

    before do
      skip "Postgres-only test" unless ActiveRecord::Base.connection.adapter_name =~ /postgres/i
    end

    let(:source) { 'marketplace' }
    let(:source_account) { 'store_1' }
    let(:external_id) { 'RACE-EXT-456' }

    let!(:product_a) { create(:product, name: 'Product A') }
    let!(:product_b) { create(:product, name: 'Product B') }

    it "detects product mismatch even when RecordNotUnique is from concurrent insert" do
      # Creăm mapping pentru product_a (simulând că alt proces l-a creat)
      variant_a = create(:variant, product: product_a, sku: 'VAR-A')
      VariantExternalId.create!(
        variant: variant_a,
        source: source,
        source_account: source_account,
        external_id: external_id
      )

      # Dezactivăm validarea Rails pentru a forța DB-level RecordNotUnique
      allow_any_instance_of(VariantExternalId)
        .to receive(:valid?).and_return(true)

      service = described_class.new(source: source, source_account: source_account)

      # Încercăm import pentru product_b cu același external_id
      result = service.call(
        external_id: external_id,
        product: product_b,
        option_value_ids: [],
        attributes: { sku: 'VAR-B-NEW', price: 200, stock: 100 }
      )

      # CRITICAL: Chiar și în race condition, trebuie să detecteze mismatch
      expect(result.success).to be false
      expect(result.action).to eq(:product_mismatch)
    end
  end

  describe "#create_external_id_mapping! defensive check" do
    # Testează guard-ul adăugat în create_external_id_mapping!
    # care verifică că mapping-ul găsit în rescue pointează la aceeași variantă

    let(:source) { 'feed' }
    let(:source_account) { 'default' }
    let(:external_id) { 'DEFENSIVE-789' }

    let!(:product) { create(:product) }
    let!(:variant_1) { create(:variant, product: product, sku: 'V1') }
    let!(:variant_2) { create(:variant, product: product, sku: 'V2') }

    let!(:existing_mapping) do
      VariantExternalId.create!(
        variant: variant_1,
        source: source,
        source_account: source_account,
        external_id: external_id
      )
    end

    it "raises RecordNotUnique when mapping exists for different variant" do
      service = described_class.new(source: source, source_account: source_account)

      # Dezactivăm validarea Rails pentru a ajunge la DB constraint
      allow_any_instance_of(VariantExternalId)
        .to receive(:valid?).and_return(true)

      # Apelăm metoda privată direct pentru a testa guard-ul
      expect {
        service.send(:create_external_id_mapping!, variant_2, external_id, nil)
      }.to raise_error(ActiveRecord::RecordNotUnique, /already mapped to variant #{variant_1.id}/)
    end

    it "returns existing mapping when variant matches" do
      service = described_class.new(source: source, source_account: source_account)

      # Dezactivăm validarea Rails pentru a forța RecordNotUnique
      allow_any_instance_of(VariantExternalId)
        .to receive(:valid?).and_return(true)

      # Apelăm pentru aceeași variantă - ar trebui să returneze mapping-ul existent
      result = service.send(:create_external_id_mapping!, variant_1, external_id, nil)

      expect(result).to eq(existing_mapping)
    end
  end
end
```

### Test: Variant.update nu atinge product (V→P prevention)

```ruby
# spec/models/variant_spec.rb
RSpec.describe Variant do
  describe "lock safety" do
    it "updating price/stock does not touch product" do
      variant = create(:variant, price: 100, stock: 50)
      product_updated_at = variant.product.updated_at

      # Folosim freeze_time pentru a detecta touch
      travel 1.minute do
        expect {
          variant.update!(price: 150, stock: 40)
        }.not_to change { variant.product.reload.updated_at }
      end
    end

    it "updating price/stock does not query product table" do
      variant = create(:variant)

      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql] =~ /products/i }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        variant.update!(price: 200)
      end

      product_writes = queries.select { |q| q =~ /UPDATE.*products/i }
      expect(product_writes).to be_empty,
        "Variant update should not write to products table, found: #{product_writes}"
    end
  end
end
```

### Helper: Lock Order Verification (spec/support/lock_order_helper.rb)

```ruby
# spec/support/lock_order_helper.rb
#
# Helper pentru verificarea lock order în teste.
# Centralizează regex-urile pentru a le ajusta într-un singur loc.
#
# USAGE: include LockOrderHelper în spec files sau via RSpec.configure

module LockOrderHelper
  # Regex pentru ORDER BY id - strict: acceptă doar:
  # - id
  # - variants.id
  # - "variants"."id"
  # - `variants`.`id`
  # - schema.variants.id
  #
  # IMPORTANT: Nu folosim \b după quote-uri (") pentru că \b nu e word boundary
  # după caractere non-word. În schimb folosim lookahead pe delimitatori.
  # Flag /m pentru multiline (query-uri lungi pot avea newlines)
  ORDER_BY_ID = /
    order\s+by\s+
    (?:
      (?:["`]?\w+["`]?\.)?                 # schema optional (quoted sau nu)
      (?:["`]?variants["`]?\.)?            # table optional
      ["`]?id["`]?
      |
      ["`]?id["`]?
    )
    (?=\s|$|,|\)|;)                        # lookahead: delimitator (nu \b)
  /imx

  # Regex pentru FOR UPDATE - tolerant la:
  # - FOR UPDATE
  # - FOR UPDATE OF "variants"
  # - FOR UPDATE OF variants
  FOR_UPDATE = /for\s+update(?:\s+of\b[^;]*)?/im

  # Regex pentru schema queries (de exclus)
  SCHEMA_QUERY = /pg_|sqlite_master|information_schema/i

  # Regex pentru SELECT ... FROM table ... FOR UPDATE
  # Flag /m pentru multiline support
  #
  # IMPORTANT: Nu folosim \b după table name quoted - folosim lookahead pe delimitatori
  # Asta evită false positives (ex: "variants_backup" != "variants") fără să ratăm
  # SQL-ul real cu identificatori cotați ("variants"."id")
  def select_for_update_regex(table)
    escaped = Regexp.escape(table)
    /
      SELECT.*FROM\s+
      (?:["`]?\w+["`]?\.)?                 # schema optional
      ["`]?#{escaped}["`]?                 # table name
      (?=\s|$|,|\)|;)                      # lookahead: delimitator (nu \b)
      .*FOR\s+UPDATE
    /imx
  end

  # Verifică că cel puțin un query are FOR UPDATE + ORDER BY id
  # @param queries [Array<String>] Lista de SQL queries capturate
  # @param label [String] Nume pentru mesajul de eroare (ex: "variants lock")
  # @raise [RSpec::Expectations::ExpectationNotMetError] dacă nu găsește
  def expect_lock_order!(queries, label:)
    has_lock_with_order = queries.any? { |q|
      q =~ FOR_UPDATE && q =~ ORDER_BY_ID
    }

    expect(has_lock_with_order).to be(true),
      "Expected #{label} to have FOR UPDATE + ORDER BY id, got:\n#{queries.join("\n")}"
  end

  # Capturează queries pe un tabel specific cu FOR UPDATE
  # @param table [String] Numele tabelului (ex: "variants", "orders")
  # @param into [Array] Array-ul în care se adaugă query-urile capturate
  # @return [Proc] Callback pentru ActiveSupport::Notifications
  def capture_lock_queries(table, into:)
    pattern = select_for_update_regex(table)
    ->(*, payload) {
      sql = payload[:sql].to_s
      return if sql.empty?           # nil guard
      return if sql =~ SCHEMA_QUERY  # folosim return, nu next (în lambda)
      into << sql if sql =~ pattern
    }
  end

  # Skip helper pentru adapteri care nu suportă FOR UPDATE (ex: SQLite)
  def skip_unless_supports_for_update!
    unless ActiveRecord::Base.connection.respond_to?(:supports_select_for_update?) &&
           ActiveRecord::Base.connection.supports_select_for_update?
      skip "Adapter doesn't support SELECT FOR UPDATE"
    end
  end

  # Assert helper pentru READ COMMITTED isolation level
  # Lock-order hardening assumes READ COMMITTED (default Rails/Postgres)
  # Dacă cineva schimbă isolation level, testele trebuie să pice explicit
  def assert_read_committed!
    return unless ActiveRecord::Base.connection.adapter_name =~ /postgres/i

    iso = ActiveRecord::Base.connection.select_value("SHOW transaction_isolation")
    expect(iso).to match(/read committed/i),
      "Lock-order design assumes READ COMMITTED, got: #{iso}. " \
      "ORDER BY ... FOR UPDATE behavior differs in other isolation levels."
  end
end

# Includem în RSpec pentru a fi disponibil în toate testele
RSpec.configure do |config|
  config.include LockOrderHelper
end
```

### Test: BulkLockingService lock order

```ruby
# spec/services/variants/bulk_locking_service_spec.rb
RSpec.describe Variants::BulkLockingService do
  include LockOrderHelper

  describe ".with_locked_variants" do
    it "locks variants in id order regardless of input order" do
      # Skip dacă adapter-ul nu suportă FOR UPDATE (to_sql va genera SQL fără FOR UPDATE)
      skip_unless_supports_for_update!

      v1 = create(:variant)
      v2 = create(:variant)
      v3 = create(:variant)

      # Verificăm explicit că SQL-ul include ORDER BY id + FOR UPDATE
      # Asta e proprietatea care previne deadlock-ul, nu doar ordinea rezultatului
      sql = Variant.where(id: [v3.id, v1.id, v2.id]).order(:id).lock.to_sql
      expect(sql).to match(ORDER_BY_ID)
      expect(sql).to match(FOR_UPDATE)

      # Verificăm și că rezultatul e ordonat
      described_class.with_locked_variants([v3.id, v1.id, v2.id]) do |locked|
        expect(locked.map(&:id)).to eq([v1.id, v2.id, v3.id].sort)
      end
    end

    # GOLD STANDARD: Verifică SQL-ul EXECUTAT efectiv în runtime
    # Asta garantează că service-ul chiar face SELECT ... ORDER BY ... FOR UPDATE
    it "executes SELECT FOR UPDATE with ORDER BY in runtime" do
      skip_unless_supports_for_update!
      assert_read_committed!  # Lock-order hardening assumes READ COMMITTED

      v1 = create(:variant)
      v2 = create(:variant)
      v3 = create(:variant)

      executed_queries = []
      callback = capture_lock_queries("variants", into: executed_queries)

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.with_locked_variants([v3.id, v1.id, v2.id]) do |locked|
          # Consumăm rezultatul pentru a forța execuția
          locked.to_a
        end
      end

      # Trebuie să avem CEL PUȚIN un SELECT FOR UPDATE valid
      expect(executed_queries).not_to be_empty,
        "Expected at least 1 SELECT FOR UPDATE query on variants, got none"

      # Verificăm că ACELAȘI query are ambele: FOR UPDATE + ORDER BY id
      expect_lock_order!(executed_queries, label: "variants lock")
    end

    it "fails fast on negative stock (no silent clamp)" do
      variant = create(:variant, stock: 10)

      expect {
        described_class.bulk_update_stock({ variant.id => -5 })
      }.to raise_error(ActiveRecord::StatementInvalid) # DB constraint
    end

    it "fails fast on invalid stock value (no silent to_i conversion)" do
      variant = create(:variant, stock: 10)

      # "abc".to_i ar returna 0 silențios - INTERZIS
      # Integer("abc") ridică ArgumentError - CORECT (fail-fast)
      expect {
        described_class.bulk_update_stock({ variant.id => "abc" })
      }.to raise_error(ArgumentError)
    end

    it "fails fast on invalid variant id (no silent to_i conversion)" do
      # "invalid".to_i ar returna 0 - INTERZIS
      expect {
        described_class.bulk_update_stock({ "invalid" => 10 })
      }.to raise_error(ArgumentError)
    end
  end
end
```

### Test: RestockService lock order (runtime verified)

```ruby
# spec/services/orders/restock_service_spec.rb
RSpec.describe Orders::RestockService do
  include LockOrderHelper

  describe "#call" do
    # GOLD STANDARD: Verifică că RestockService respectă O → I → V* (ORDER BY id)
    # ROBUST: Verificăm ORDINE RELATIVĂ, nu secvență exactă
    #         (pot apărea query-uri auxiliare legitime între lock-uri)
    it "locks order, items, then variants in id order" do
      skip_unless_supports_for_update!
      assert_read_committed!  # Lock-order hardening assumes READ COMMITTED

      order = create(:order, status: 'confirmed')
      v1 = create(:variant, stock: 0)
      v2 = create(:variant, stock: 0)
      v3 = create(:variant, stock: 0)

      # Creăm items în ordine inversă pentru a testa sortarea
      create(:order_item, order: order, variant: v3, quantity: 1)
      create(:order_item, order: order, variant: v1, quantity: 2)
      create(:order_item, order: order, variant: v2, quantity: 1)

      lock_sequence = []
      variants_lock_queries = []

      # Pre-build regex patterns pentru performanță
      orders_lock = select_for_update_regex("orders")
      items_lock  = select_for_update_regex("order_items")
      vars_lock   = select_for_update_regex("variants")

      callback = ->(*, payload) {
        sql = payload[:sql].to_s
        return if sql.empty?         # nil guard
        return if sql =~ SCHEMA_QUERY  # return în lambda, nu next

        case sql
        when orders_lock then lock_sequence << :order
        when items_lock  then lock_sequence << :items
        when vars_lock
          lock_sequence << :variants
          variants_lock_queries << sql
        end
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.new(order).call
      end

      # Verificăm ORDINE RELATIVĂ: O înainte de I, I înainte de V
      order_idx = lock_sequence.index(:order)
      items_idx = lock_sequence.index(:items)
      variants_idx = lock_sequence.index(:variants)

      expect(order_idx).not_to be_nil, "Expected ORDER lock, got sequence: #{lock_sequence}"
      expect(items_idx).not_to be_nil, "Expected ORDER_ITEMS lock, got sequence: #{lock_sequence}"
      expect(variants_idx).not_to be_nil, "Expected VARIANTS lock, got sequence: #{lock_sequence}"

      expect(order_idx).to be < items_idx,
        "ORDER must be locked before ITEMS. Sequence: #{lock_sequence}"
      expect(items_idx).to be < variants_idx,
        "ITEMS must be locked before VARIANTS. Sequence: #{lock_sequence}"

      # Verificăm că ACELAȘI query are FOR UPDATE + ORDER BY id
      expect_lock_order!(variants_lock_queries, label: "variants lock")

      # Verificăm că stocul a fost restockat
      expect(v1.reload.stock).to eq(2)
      expect(v2.reload.stock).to eq(1)
      expect(v3.reload.stock).to eq(1)
    end
  end
end
```

### Test: Product#archive! lock order (runtime verified)

```ruby
# spec/models/product_spec.rb
RSpec.describe Product do
  include LockOrderHelper

  describe "#archive!" do
    # ROBUST: Verificăm ORDINE RELATIVĂ (P înainte de V), nu secvență exactă
    it "locks product then variants in id order" do
      skip_unless_supports_for_update!
      assert_read_committed!  # Lock-order hardening assumes READ COMMITTED

      product = create(:product)
      v1 = create(:variant, product: product, status: :active)
      v2 = create(:variant, product: product, status: :active)
      v3 = create(:variant, product: product, status: :active)

      lock_sequence = []
      variants_lock_queries = []

      # Pre-build regex patterns pentru performanță
      products_lock = select_for_update_regex("products")
      vars_lock     = select_for_update_regex("variants")

      callback = ->(*, payload) {
        sql = payload[:sql].to_s
        return if sql.empty?         # nil guard
        return if sql =~ SCHEMA_QUERY  # return în lambda, nu next

        case sql
        when products_lock then lock_sequence << :product
        when vars_lock
          lock_sequence << :variants
          variants_lock_queries << sql
        end
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        product.archive!
      end

      # Verificăm ORDINE RELATIVĂ: P înainte de V
      product_idx = lock_sequence.index(:product)
      variants_idx = lock_sequence.index(:variants)

      expect(product_idx).not_to be_nil, "Expected PRODUCT lock, got sequence: #{lock_sequence}"
      expect(variants_idx).not_to be_nil, "Expected VARIANTS lock, got sequence: #{lock_sequence}"

      expect(product_idx).to be < variants_idx,
        "PRODUCT must be locked before VARIANTS. Sequence: #{lock_sequence}"

      # Verificăm că ACELAȘI query are FOR UPDATE + ORDER BY id
      expect_lock_order!(variants_lock_queries, label: "variants lock")

      # Verificăm că variantele sunt inactive
      expect(v1.reload).to be_inactive
      expect(v2.reload).to be_inactive
      expect(v3.reload).to be_inactive
      expect(product.reload).to be_archived
    end
  end
end
```

### Test: Advisory lock transaction guard (V7.9.23 regression test)

```ruby
# spec/services/imports/variant_sync_service_advisory_lock_guard_spec.rb
#
# CRITICAL REGRESSION TEST: Dovedește că guard-ul assert_transaction_open_on_lock_connection!
# prinde corect apelurile de advisory lock fără tranzacție deschisă.
#
# VALOARE: Transformă un bug de concurență silent (lock se eliberează imediat)
# în crash determinist în dev/test.

RSpec.describe "Advisory lock transaction guard", :postgres_only do
  before do
    skip "Postgres-only test" unless ActiveRecord::Base.connection.adapter_name =~ /postgres/i
  end

  describe Imports::VariantSyncService do
    it "raises RuntimeError when acquire_external_id_lock called outside transaction" do
      service = described_class.new(source: 'test', source_account: 'default')

      # Apelăm direct metoda privată, FĂRĂ tranzacție
      # Guard-ul trebuie să detecteze lipsa tranzacției și să pice
      expect {
        service.send(:acquire_external_id_lock, 'EXT-123')
      }.to raise_error(RuntimeError, /requires an open transaction/)
    end

    it "does NOT raise when called inside VariantExternalId.transaction" do
      service = described_class.new(source: 'test', source_account: 'default')

      # Cu tranzacție pe conexiunea corectă, nu trebuie să pice
      expect {
        VariantExternalId.transaction do
          service.send(:acquire_external_id_lock, 'EXT-123')
          raise ActiveRecord::Rollback # Nu vrem efecte laterale
        end
      }.not_to raise_error
    end

    it "raises when transaction is on wrong connection (ActiveRecord::Base)" do
      # IMPORTANT: Acest test verifică scenariul care a cauzat bug-ul original
      # Tranzacția e pe ActiveRecord::Base, dar lock-ul verifică VariantExternalId.connection

      # Skip dacă ambele share-uiesc aceeași conexiune (single-db setup)
      if ActiveRecord::Base.connection == VariantExternalId.connection
        skip "Single-DB setup - connections are shared, guard won't trigger"
      end

      service = described_class.new(source: 'test', source_account: 'default')

      expect {
        ActiveRecord::Base.transaction do
          service.send(:acquire_external_id_lock, 'EXT-123')
        end
      }.to raise_error(RuntimeError, /requires an open transaction/)
    end
  end

  describe Variants::AdminExternalIdService do
    let(:variant) { create(:variant) }

    it "raises RuntimeError when acquire_external_id_lock called outside transaction" do
      service = described_class.new(variant)

      expect {
        service.send(:acquire_external_id_lock, 'test', 'default', 'EXT-456')
      }.to raise_error(RuntimeError, /requires an open transaction/)
    end

    it "does NOT raise when called inside VariantExternalId.transaction" do
      service = described_class.new(variant)

      expect {
        VariantExternalId.transaction do
          service.send(:acquire_external_id_lock, 'test', 'default', 'EXT-456')
          raise ActiveRecord::Rollback
        end
      }.not_to raise_error
    end
  end
end
```

### Test: Advisory lock serialization (concurrency test)

```ruby
# spec/services/imports/variant_sync_service_serialization_spec.rb
#
# CRITICAL CONCURRENCY TEST: Dovedește că advisory lock-ul chiar serializează
# accesul concurent la același external_id.
#
# MECANISM:
# - T1 intră în tranzacție, ia lock, semnalizează și așteaptă
# - T2 încearcă să ia același lock și trebuie să stea blocat
# - T1 eliberează, T2 continuă
# - Verificăm că T2 nu a avansat înainte de T1

RSpec.describe "Advisory lock serialization", :postgres_only do
  before do
    skip "Postgres-only test" unless ActiveRecord::Base.connection.adapter_name =~ /postgres/i
  end

  let(:source) { 'serialization_test' }
  let(:source_account) { 'default' }
  let(:external_id) { "SHARED-EXT-#{SecureRandom.hex(4)}" }

  it "serializes concurrent calls on same (source, source_account, external_id)" do
    t1_locked = Queue.new
    t1_can_release = Queue.new
    results = Queue.new

    t1 = Thread.new do
      VariantExternalId.transaction do
        service = Imports::VariantSyncService.new(source: source, source_account: source_account)
        service.send(:acquire_external_id_lock, external_id)

        t1_locked << :locked
        results << { thread: :t1, event: :lock_acquired, time: Time.now.to_f }

        # Așteaptă semnal să elibereze (sau timeout)
        Timeout.timeout(5) { t1_can_release.pop }
        results << { thread: :t1, event: :releasing, time: Time.now.to_f }
      end
      results << { thread: :t1, event: :released, time: Time.now.to_f }
    end

    t2 = Thread.new do
      # Așteaptă ca T1 să ia lock-ul
      Timeout.timeout(5) { t1_locked.pop }
      results << { thread: :t2, event: :attempting_lock, time: Time.now.to_f }

      VariantExternalId.transaction do
        service = Imports::VariantSyncService.new(source: source, source_account: source_account)
        service.send(:acquire_external_id_lock, external_id)

        results << { thread: :t2, event: :lock_acquired, time: Time.now.to_f }
      end
    end

    # Dă timp lui T2 să încerce lock-ul (va sta blocat)
    sleep 0.1

    # Verifică că T2 încă așteaptă (nu a luat lock-ul)
    events_so_far = []
    events_so_far << results.pop(true) while results.size > 0 rescue nil
    t2_locked_early = events_so_far.any? { |e| e[:thread] == :t2 && e[:event] == :lock_acquired }
    expect(t2_locked_early).to be(false), "T2 should NOT have acquired lock while T1 holds it"

    # Eliberează T1
    t1_can_release << :release

    # Așteaptă ambele thread-uri
    [t1, t2].each { |t| t.join(10) }

    # Colectează toate rezultatele
    all_events = events_so_far
    all_events << results.pop(true) while results.size > 0 rescue nil

    # Sortează după timestamp
    all_events.sort_by! { |e| e[:time] }

    # Verifică ordinea: T1 lock_acquired < T2 lock_acquired
    t1_lock_time = all_events.find { |e| e[:thread] == :t1 && e[:event] == :lock_acquired }&.dig(:time)
    t2_lock_time = all_events.find { |e| e[:thread] == :t2 && e[:event] == :lock_acquired }&.dig(:time)

    expect(t1_lock_time).to be < t2_lock_time,
      "T1 should acquire lock before T2. Events: #{all_events.inspect}"

    # Verifică că T1 a eliberat înainte ca T2 să ia lock-ul
    t1_release_time = all_events.find { |e| e[:thread] == :t1 && e[:event] == :released }&.dig(:time)
    expect(t1_release_time).to be < t2_lock_time,
      "T1 should release before T2 acquires. Events: #{all_events.inspect}"
  end

  it "does NOT block when different external_ids are used" do
    external_id_1 = "EXT-A-#{SecureRandom.hex(4)}"
    external_id_2 = "EXT-B-#{SecureRandom.hex(4)}"

    t1_locked = Queue.new
    t1_can_release = Queue.new
    t2_locked = Queue.new

    t1 = Thread.new do
      VariantExternalId.transaction do
        service = Imports::VariantSyncService.new(source: source, source_account: source_account)
        service.send(:acquire_external_id_lock, external_id_1)
        t1_locked << :locked
        # Așteaptă semnalul să se termine (după ce T2 confirmă că a luat lock-ul)
        Timeout.timeout(5) { t1_can_release.pop }
      end
    end

    t2 = Thread.new do
      # Așteaptă ca T1 să ia lock-ul
      Timeout.timeout(5) { t1_locked.pop }

      # T2 folosește ALT external_id - nu trebuie să stea blocat
      VariantExternalId.transaction do
        service = Imports::VariantSyncService.new(source: source, source_account: source_account)
        service.send(:acquire_external_id_lock, external_id_2)
        # Semnalează că am luat lock-ul ÎNAINTE ca T1 să se termine
        t2_locked << :locked
      end
    end

    # Așteptăm ca T2 să ia lock-ul (în timp ce T1 încă ține lock-ul său)
    t2_got_lock = Timeout.timeout(5) { t2_locked.pop } rescue nil

    # Acum permite T1 să se termine
    t1_can_release << :release

    [t1, t2].each { |t| t.join(10) }

    # ASSERTION: T2 a luat lock-ul în timp ce T1 încă ținea lock-ul său
    # Dacă ar fi fost blocate pe același lock, T2 nu ar fi putut să facă push în t2_locked
    # până când T1 nu termina tranzacția (dar T1 aștepta t1_can_release care vine DUPĂ t2_locked)
    expect(t2_got_lock).to eq(:locked),
      "T2 should acquire different lock while T1 still holds its lock (no blocking)"
  end
end
```

---

## 6. PAȘI DEPLOY

### Faza 1: Core (M1-M3)
1. `rails variants:audit` - verifică starea
2. `rails db:migrate` (M1) - adaugă coloane
3. `rails db:migrate` (M2) - cleanup
4. `rails db:migrate` (M3) - constraints
5. Deploy cod (modele + servicii existente)
6. `rails variants:audit` - verificare

### Faza 2: External IDs (M4-M5) - când ai nevoie de feed-uri multiple
1. `rails db:migrate` (M4) - tabel variant_external_ids
2. `rails db:migrate` (M5) - backfill din external_sku existent
3. Deploy cod (VariantExternalId model + Imports::VariantSyncService)
4. Actualizează importerii să folosească VariantSyncService
5. `rails variants:audit` - verificare finală

---

## 7. GHID IMPORT FEED-URI

### Pattern recomandat pentru import

```ruby
# Exemplu: import din ERP (compania A)
class Erp::VariantImportJob
  def perform(feed_data, erp_company: 'company_a')
    # source_account identifică instanța/compania din ERP
    sync_service = Imports::VariantSyncService.new(
      source: 'erp',
      source_account: erp_company  # ex: "company_a", "company_b"
    )

    feed_data.each do |item|
      product = find_or_create_product(item[:product_code])

      result = sync_service.call(
        external_id: item[:erp_variant_id],  # ID-ul stabil din ERP
        product: product,
        option_value_ids: map_options(item[:options]),
        attributes: {
          sku: item[:sku],
          price: item[:price],
          stock: item[:stock],
          external_sku: item[:erp_sku]  # SKU-ul din ERP (pentru debug/audit)
        }
      )

      case result.action
      when :created
        Rails.logger.info "Created variant #{result.variant.id} from ERP #{item[:erp_variant_id]}"
      when :updated
        Rails.logger.info "Updated variant #{result.variant.id} from ERP #{item[:erp_variant_id]}"
      when :linked
        Rails.logger.info "Linked existing variant #{result.variant.id} to ERP #{item[:erp_variant_id]}"
      when :reactivated
        Rails.logger.info "Reactivated variant #{result.variant.id} from ERP #{item[:erp_variant_id]}"
      else
        Rails.logger.error "Failed to sync ERP #{item[:erp_variant_id]}: #{result.error}"
      end
    end
  end
end

# Exemplu: import din eMAG (cont România 1)
class Emag::VariantImportJob
  def perform(feed_data)
    sync_service = Imports::VariantSyncService.new(
      source: 'emag',
      source_account: 'ro_store_1'  # sau 'ro_store_2' pentru alt cont
    )

    feed_data.each do |item|
      # ... similar cu ERP
    end
  end
end
```

### Avantaje față de external_sku global unic

| Problemă | Cu external_sku global | Cu variant_external_ids |
|----------|------------------------|-------------------------|
| Două surse cu același ID | ❌ Conflict | ✅ OK (surse diferite) |
| Două conturi eMAG cu același ID | ❌ Conflict | ✅ OK (source_account diferit) |
| Mai multe ID-uri per variantă | ❌ Imposibil | ✅ OK (multiple mappings) |
| Schimbare sursă | ❌ Trebuie șters ID-ul vechi | ✅ Adaugi mapping nou |
| Debug/audit per sursă | ❌ Dificil | ✅ `group(:source).count` |
| Produse proprii (fără feed) | ❌ Trebuie external_sku fals | ✅ Fără mapping, e OK |
| Link variantă existentă la feed nou | ❌ Manual/risky | ✅ Automat (action: :linked) |

### Exemplu scenarii multi-account

```ruby
# Scenariul: Ai două conturi eMAG (RO store 1 și RO store 2)
# Ambele au un produs cu external_id = "12345"

# Import din eMAG store 1
sync1 = Imports::VariantSyncService.new(source: 'emag', source_account: 'ro_store_1')
sync1.call(external_id: '12345', product: product_a, ...)
# → Creează mapping: (emag, ro_store_1, 12345) → variant_id: 100

# Import din eMAG store 2 (același external_id, dar alt cont!)
sync2 = Imports::VariantSyncService.new(source: 'emag', source_account: 'ro_store_2')
sync2.call(external_id: '12345', product: product_b, ...)
# → Creează mapping: (emag, ro_store_2, 12345) → variant_id: 200

# FĂRĂ source_account, al doilea import ar fi picat cu conflict!
```

### Produse proprii vs feed-uri

```ruby
# Produs propriu (creat manual în admin, fără feed)
variant = Variants::CreateOrReactivateService.new(product).call(
  [option_value_1, option_value_2],
  { sku: 'MANUAL-001', price: 100, stock: 50 }
)
# → Varianta există, DAR nu are niciun mapping în variant_external_ids
# → Importurile nu o vor "vedea" și nu o vor modifica accidental

# Mai târziu, dacă vrei să o legi la un feed:
variant.variant.find_or_create_external_id!(
  source: 'erp',
  source_account: 'company_a',
  external_id: 'ERP-12345'
)
# → Acum feed-ul ERP o va găsi și actualiza
```



Raspuns de la gpt despre aceasta versiune:

Verdict: V7.9.25 e OK de deploy pe Postgres conform checklist-ului și cu cele 4 red-flaguri închise. ✅

Ultimele “sanity checks” (non-blocking, dar merită bifate rapid)

Aliniază peste tot numele metricii: în snippet-uri încă apare pe alocuri legacy_lock_acquired, dar acum contorul e variant_sync.dual_lock_call. Dacă ai lăsat acel text în comentarii/spec output, nu afectează runtime, dar poate induce în eroare în ops. (Aș face un “search & replace” ca să fie 100% consistent.)

Confirmă compatibilitatea de rollback: migrațiile sunt additive, dar constrângerile/indexurile noi pot face un downgrade la cod vechi riscant (cod vechi ar putea încerca să scrie date care acum sunt respinse). Practic, “rollback” sănătos = redeploy cu cod fix, nu întoarcere la versiuni care nu respectă noile invariants.

Runbook de deploy (exact ce ai în plan, cu focus pe riscuri)

Faza 1 (M1–M3)

rails variants:audit (baseline)

rails db:migrate (M1 → M2 → M3)

M2 e fail-fast pe duplicate/multi-value, deci dacă trece, ai semnal bun că M3 nu va crăpa “opac”.

Deploy cod V7.9.25

rails variants:audit din nou (post-constraints)

Faza 2 (M4–M5) doar când pornești multi-source/multi-account feeds.

Ce aș monitoriza imediat după deploy

Erori de unicitate pe variant_external_ids (în special idx_unique_source_account_external_id) → ar trebui să fie rare, iar fallback-ul tău să le transforme în rezultate deterministe.

product_mismatch (log + return :product_mismatch) → dacă apare, e semnal de feed/config greșit, nu bug de concurență.

Deadlock-uri Postgres (deadlock detected) → cu lock-order hardening + ORDER BY id ar trebui să scadă, nu să crească.

variant_sync.dual_lock_call ca volum (nu criteriu de eliminare), plus planul de dezactivare a dual-lock după ce fleet e 100% pe versiunea compatibilă.

Dacă ai bifat și consistența numelui de metrică în doc/spec output, eu aș zice: GO deploy V8.0.0.

---

## 8. OBSERVABILITY & DEBUGGABILITY

### Debuggability Score: 58 / 100

**De ce nu e mai sus:** Ai deja fail-fast și mesaje explicite în multe locuri (plus log-uri în VariantSyncService și counter pentru dual-lock), dar acoperirea invariants→(log+metric+mesaj) e incompletă: multe flow-uri critice nu emit nici log semantic, nici metric, iar când se întâmplă ceva rău (deadlock/timeout/RecordNotUnique/StatementInvalid) contextul e adesea doar SQL / stacktrace, nu "ce invariant s-a rupt".

### Breakdown (rapid)

| Aspect | Scor | Notă |
|--------|------|------|
| Mesaje explicite (user/job-facing) | 16/20 | Bun în servicii; mai slab la excepții DB brute |
| Log-uri semantice | 18/30 | Bun în VariantSyncService; lipsesc în create/update/checkout/bulk/admin |
| Metrici/counters | 10/30 | Ai doar dual-lock; restul aproape zero |
| Corelare (request/job IDs, context consistent) | 6/10 | Inconsistent / absent |
| Noise control (sampling/rate limit) | 8/10 | Ai flag pentru dual lock; restul neplanificat |

---

### 8.1 "Contract" minim de observabilitate (ca să nu derapeze)

#### A) Schema de log (consistentă peste tot)

Folosește un format stabil (chiar și dacă e text, păstrează chei):

| Cheie | Descriere | Când |
|-------|-----------|------|
| `event` | Nume semantic | Întotdeauna |
| `invariant` | Ex: `inv_01_unique_active_digest` | La orice violație/warning |
| `action` | `created/updated/linked/conflict/invalid/etc.` | La orice operație |
| `product_id`, `variant_id`, `order_id` | După caz | Întotdeauna când disponibil |
| `digest` | Sau `digest_present=true` dacă e sensibil | La operații pe variante |
| `source`, `source_account`, `external_id` | Pentru feed-uri | La import/sync |
| `lock_domain` + `lock_wait_ms` | Când blochezi | La orice lock >0ms |
| `error_class`, `db_constraint/index` | Când e excepție DB | La orice eroare |
| `request_id` / `job_id` | Tagging din middleware/job | Întotdeauna |

**NU schimbi funcționalitatea:** doar adaugi `Rails.logger.(info|warn|error)` + context.

#### B) Metric naming (StatsD-friendly, fără dependențe noi)

Prefix unic: `variants.` / `imports.variant_sync.` / `checkout.` / `orders.`

**Exemple:**
- `variants.create.created`, `variants.create.conflict`, `variants.create.invalid`
- `imports.variant_sync.product_mismatch`, `imports.variant_sync.options_mismatch`
- `checkout.finalize.insufficient_stock`, `checkout.finalize.variant_unavailable`
- `locks.wait_ms` (timing) per flow: `imports.variant_sync.lock_wait_ms`, `checkout.finalize.lock_wait_ms`

---

### 8.2 Matrice Invariants → (Log + Metric + Mesaj Explicit)

Mai jos: unde pui log/metric și ce trebuie să spună (mesajul din log, nu SQL generic).

**Notă:** "mesaj explicit" = log message semantic ("SKU duplicate pentru product X"), chiar dacă excepția DB e opacă.

#### INV #1 / #2 / #9 — Unicitate variantă activă (digest & default)

**Unde:**
- `Variant#no_active_digest_conflict` (la `errors.add`)
- `CreateOrReactivateService#handle_unique_violation` + `#handle_race_condition`
- `UpdateOptionsService` (conflict check + rescue `RecordNotUnique`)
- `Products::UpdateOptionTypesService` (când dezactivezi extra active)

**Log (mesaj):**
```
event=variants.unique_active_violation invariant=inv_01 action=conflict product_id=... digest=... existing_variant_id=... attempted_variant_id=...
```

Pentru default: `... invariant=inv_02 digest=nil ...`

**Metric:**
- `variants.unique_active.conflict += 1`
- `variants.unique_default.conflict += 1`
- `variants.race_condition += 1`

---

#### INV #3 / #8 — Digest calculat explicit & schimbare combinație

**Unde:**
- `CreateOrReactivateService#create_new` (după `variant.update!(options_digest: ...)`)
- `UpdateOptionsService` (după update)
- `UpdateOptionTypesService` (după recalc / `update_column`)

**Log:**
```
event=variants.digest_updated invariant=inv_08 product_id=... variant_id=... old_digest=... new_digest=... reason=(create|update_options|option_types_change)
```

**Metric:**
- `variants.digest_updated += 1`
- `variants.option_types.recomputed += 1`

---

#### INV #4 / #4b — Purchasable & checkout eligibility

**Unde (real):**
- `Checkout::FinalizeService` (când variant e nil / inactive / stock insuficient)
- Opțional: în controller/job care apelează checkout (dacă există)

**Log:**
```
event=checkout.variant_unavailable invariant=inv_04b order_id=... variant_id=... reason=(missing|inactive|not_found)
event=checkout.insufficient_stock invariant=inv_04b order_id=... variant_id=... sku=... requested_qty=... stock=...
```

**Metric:**
- `checkout.finalize.variant_unavailable += 1`
- `checkout.finalize.insufficient_stock += 1`

---

#### INV #5 — Stoc atomic (nu depășim stocul)

**Unde:**
- `Checkout::FinalizeService` imediat înainte și după `variant.update_column(:stock, ...)`

**Log:**
```
event=checkout.stock_decremented invariant=inv_05 order_id=... variant_id=... sku=... before=... delta=-total_qty after=...
```

**Metric:**
- `checkout.finalize.stock_decremented += 1`

---

#### INV #6 — Snapshot imutabil comenzi

**Unde:**
- `Checkout::FinalizeService#snapshot_item`

**Log:**
- La începutul finalize: `event=checkout.snapshot_begin invariant=inv_06 order_id=... items=...`
- La final: `event=checkout.snapshot_done invariant=inv_06 order_id=...`
- Dacă `variant_id.nil?`: `event=checkout.snapshot_missing_variant invariant=inv_06 order_id=... order_item_ids=[...]`

**Metric:**
- `checkout.snapshot.missing_variant += 1`
- `checkout.snapshot.success += 1`

---

#### INV #7 — Price/stock NOT NULL și >= 0

**Unde:**
- Variant validation failure paths (în servicii, în rescue `RecordInvalid`)
- `Variants::BulkLockingService` (când arunci `StatementInvalid` sau `ArgumentError`)
- Migrarea M2 (unde "fixezi" datele) — log de audit

**Log:**
```
event=variants.validation_failed invariant=inv_07 model=Variant errors="..." product_id=... variant_id=...
event=variants.bulk_check_violation invariant=inv_07 field=(stock|price) variant_id=... value=... adapter=...
```

**Metric:**
- `variants.inv_07.violation += 1`
- `variants.bulk.invalid_input += 1`

---

#### INV #10 / #11 / #12 — External IDs: unicitate + product mismatch + opțiuni "read-only" la update feed

**Unde (ai deja o parte):**
- `VariantSyncService#update_existing` (product mismatch + options mismatch)
- `VariantSyncService#handle_unique_violation` (fallback)
- `Variants::AdminExternalIdService#link` (conflict/already_linked/not_found)

**Log (întărește + completează):**
- Product mismatch (ai deja): adaugă și `event=imports.variant_sync.product_mismatch invariant=inv_11 ...`
- Options mismatch (ai deja warn): adaugă `invariant=inv_12` + `variant_id` + `incoming_digest` + `current_digest`
- On success paths (created/linked/updated): `event=imports.variant_sync.success action=... invariant=inv_10 source=... account=... external_id=... product_id=... variant_id=...`

**Metric:**
- `imports.variant_sync.product_mismatch += 1`
- `imports.variant_sync.options_mismatch += 1`
- `imports.variant_sync.linked += 1`, `...created += 1`, `...updated += 1`, `...invalid += 1`, `...conflict += 1`
- `variants.admin_external_id.conflict += 1`, `...linked += 1`, `...unlinked += 1`

---

#### INV #13 / #14 / #15 — Lock order & deadlock safety (observabilitate runtime)

Aici nu vrei doar "știm teoretic", ci să poți răspunde la: **"unde stă blocat?"**

**Unde:**
- În fiecare flow cu lock-uri:
  - `CreateOrReactivateService`, `UpdateOptionsService`, `UpdateOptionTypesService`, `Product#archive!`, `VariantSyncService`, `Checkout::FinalizeService`, `Orders::RestockService`, `BulkLockingService`
- În jurul apelurilor care blochează (`lock!`, `.lock` query, `pg_advisory_xact_lock`)

**Ce adaugi:**
1. **Timing lock wait** (monotonic time înainte/după fiecare lock important)
2. **Log WARN** dacă `lock_wait_ms > prag` (ex: 200ms / 500ms / 1000ms)
3. **Metric timing:** `*.lock_wait_ms` (histogram/timing), plus counter `*.lock_wait_slow`

**Log template:**
```
event=locks.wait lock_domain=product invariant=inv_13 flow=variants.create_or_reactivate product_id=... lock_wait_ms=...
event=locks.wait lock_domain=advisory invariant=inv_13 flow=imports.variant_sync source=... account=... external_id=... lock_wait_ms=...
event=locks.wait lock_domain=order invariant=inv_14 flow=checkout.finalize order_id=... lock_wait_ms=...
```

**Deadlock/timeout:**
Adaugă rescue doar pentru log + metric, apoi re-raise (behavior-preserving):
- `ActiveRecord::Deadlocked`
- `ActiveRecord::LockWaitTimeout` (dacă există în stack-ul tău)
- `PG::TRDeadlockDetected` / `PG::LockNotAvailable` (prin `exception.cause`)

**Log:**
```
event=db.deadlock invariant=inv_13 flow=... product_id=... variant_ids=[...] error_class=...
event=db.lock_timeout invariant=inv_13 flow=... lock_domain=... wait_ms=...
```

**Metric:**
- `db.deadlock += 1`
- `db.lock_timeout += 1`

---

### 8.3 Găuri concrete (cele mai "scumpe" la debugging acum)

| Flow | Problema | Impact |
|------|----------|--------|
| **Checkout** | Ai excepții custom bune, dar zero log + zero metric | Când apare în prod, ai doar stacktrace și "pending/confirmed" fără context |
| **Create/Update variants** | Serviciile returnează Result, dar nu emit evenimente observabile | Nu știi dacă a fost created/reactivated/conflict/invalid/race_condition |
| **Bulk updates** | Când crapă pe input invalid sau check-violation | Nu ai "cine a trimis" + ce variantă + ce valoare |
| **AdminExternalIdService** | Acțiuni sensibile (link/unlink) fără log/metric | Greu de audit |
| **Lock wait** | Design-ul e bun, dar fără lock timing | Nu știi dacă ai blocaj "advisory vs product vs variants vs order" |

---

### 8.4 Observability Pack (implementation-ready, fără schimbări funcționale)

#### A) Evenimente obligatorii pe fiecare service (1 linie pe rezultat)

- `...success` (info)
- `...invalid` (warn)
- `...conflict` (warn)
- `...exception` (error, cu `error_class` + `cause` + `db_constraint/index` dacă se poate)

**Exemplu (CreateOrReactivateService):**

La final de `call` (înainte de return):
```ruby
Rails.logger.info(
  "event=variants.create_or_reactivate.result " \
  "action=#{result.action} success=#{result.success} " \
  "product_id=#{@product.id} variant_id=#{result.variant&.id} " \
  "digest=#{result.variant&.options_digest || 'nil'}"
)
StatsD.increment("variants.create_or_reactivate.#{result.action}") if defined?(StatsD)
```

#### B) Lock timing (doar pe lock-urile mari)

- Advisory lock (`pg_advisory_xact_lock`)
- `product.lock!`, `order.lock!`, `variant.lock!`
- SELECT FOR UPDATE pe variants în bulk (măcar un timing pe query-ul principal)

**Pattern:**
```ruby
def with_lock_timing(domain:, flow:, context: {})
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  wait_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)

  if wait_ms > 200  # prag configurabil
    Rails.logger.warn(
      "event=locks.wait_slow lock_domain=#{domain} flow=#{flow} " \
      "lock_wait_ms=#{wait_ms} #{context.map { |k,v| "#{k}=#{v}" }.join(' ')}"
    )
  end

  StatsD.timing("#{flow}.lock_wait_ms", wait_ms) if defined?(StatsD)
  result
end
```

#### C) "Invariant code" în fiecare log critic

Cheie scurtă: `inv_01`, `inv_11`, etc.

Asta permite:
- Grep rapid
- Dashboards "violations per invariant"
- Alerting precis

#### D) Rate limit / sampling pentru zgomot

- Pentru feed updates (`VariantSyncService#update_existing`), log success sampled (ex: 1% sau doar când se schimbă efectiv price/stock)
- Log-urile warn/error (mismatch/conflict) NU se samplează

---

### 8.5 Alerting minim (ca să "știi ce s-a întâmplat" în 2 minute)

| Condiție | Acțiune | De ce |
|----------|---------|-------|
| `imports.variant_sync.product_mismatch > 0` în 5m | **PAGE** | Invarianta #11, grav |
| `db.deadlock > 0` în 5m | **ALERT** | Lock-order breach sau neașteptat |
| `checkout.finalize.insufficient_stock` spike | **ALERT** | Poate feed lag / oversell |
| `variants.unique_active.conflict` spike | **ALERT** | Posibil bug nou / concurență neacoperită |
| `locks.wait_slow` spike (per domain) | **ALERT** | Îți spune unde e "blocajul" |

---

### 8.6 Exemplu: Observability pentru CreateOrReactivateService

```ruby
module Variants
  class CreateOrReactivateService
    include IdSanitizer
    include ObservabilityHelpers  # NOU: concern cu log/metric helpers

    # ... cod existent ...

    def call(option_value_ids, attributes = {})
      option_value_ids = sanitize_ids(option_value_ids)

      @product.transaction(requires_new: true) do
        lock_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @product.lock!
        record_lock_wait(:product, lock_start, product_id: @product.id)

        digest = option_value_ids.empty? ? nil : option_value_ids.join('-')
        desired_status = normalize_status(attributes[:status] || attributes["status"])

        return log_and_return(invalid("Unele opțiuni nu aparțin produsului"), :invalid) unless valid_option_values?(option_value_ids)

        # ... restul logicii ...
      end
    rescue ActiveRecord::RecordNotUnique => e
      result = handle_unique_violation(e, option_value_ids.empty? ? nil : option_value_ids.join('-'))
      log_and_return(result, :conflict)
    rescue ActiveRecord::RecordInvalid => e
      result = Result.new(success: false, variant: e.record, action: :invalid,
                         error: e.record.errors.full_messages.to_sentence)
      log_and_return(result, :invalid)
    end

    private

    def log_and_return(result, level = :info)
      log_result(
        event: 'variants.create_or_reactivate.result',
        action: result.action,
        success: result.success,
        product_id: @product.id,
        variant_id: result.variant&.id,
        digest: result.variant&.options_digest,
        error: result.error,
        level: level
      )
      increment_metric("variants.create_or_reactivate.#{result.action}")
      result
    end

    # ... alte metode private ...
  end
end
```

---

### 8.7 Concern: ObservabilityHelpers

```ruby
# app/models/concerns/observability_helpers.rb
#
# Shared helpers pentru logging semantic și metrici.
# Include în servicii pentru a avea log/metric consistent.

module ObservabilityHelpers
  extend ActiveSupport::Concern

  private

  # Log semantic cu format consistent
  def log_result(event:, action:, success:, level: :info, **context)
    msg = "event=#{event} action=#{action} success=#{success} " +
          context.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')

    case level
    when :error then Rails.logger.error(msg)
    when :warn  then Rails.logger.warn(msg)
    else Rails.logger.info(msg)
    end
  end

  # Metrică simplă (StatsD)
  def increment_metric(name, value = 1, tags: {})
    StatsD.increment(name, value, tags: tags) if defined?(StatsD)
  end

  # Timing pentru lock wait
  def record_lock_wait(domain, start_time, **context)
    wait_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    if wait_ms > lock_wait_threshold
      Rails.logger.warn(
        "event=locks.wait_slow lock_domain=#{domain} " \
        "lock_wait_ms=#{wait_ms} #{context.map { |k,v| "#{k}=#{v}" }.join(' ')}"
      )
    end

    StatsD.timing("locks.#{domain}.wait_ms", wait_ms) if defined?(StatsD)
    wait_ms
  end

  def lock_wait_threshold
    ENV.fetch('LOCK_WAIT_THRESHOLD_MS', 200).to_i
  end
end
```

---

### 8.8 Dashboard Recommendations

**Panel 1: Operații pe variante**
- `variants.create_or_reactivate.*` (stacked bar per action)
- `variants.update_options.*`
- `variants.digest_updated`

**Panel 2: Import/Sync Health**
- `imports.variant_sync.*` (stacked bar: created/updated/linked/conflict/invalid)
- `imports.variant_sync.product_mismatch` (red alert line)
- `imports.variant_sync.options_mismatch` (yellow alert line)

**Panel 3: Checkout Health**
- `checkout.finalize.*` (success rate)
- `checkout.finalize.insufficient_stock` (alert line)
- `checkout.finalize.variant_unavailable` (alert line)

**Panel 4: Lock Contention**
- `locks.*.wait_ms` (p50, p95, p99)
- `locks.wait_slow` (counter per domain)
- `db.deadlock` (red alert)

**Panel 5: Invariant Violations**
- Toate metricile cu `*.conflict`, `*.violation`, `*.mismatch`
- Group by invariant code pentru quick triage

---

### 8.9 Roadmap Observability (next steps)

| Priority | Task | Impact |
|----------|------|--------|
| **P0** | Adaugă log semantic + metric în Checkout::FinalizeService | Cel mai critic flow, zero observability acum |
| **P0** | Adaugă log_and_return în CreateOrReactivateService | Cel mai frecvent apelat |
| **P1** | Lock timing pe product.lock! și advisory locks | Detectează contention issues |
| **P1** | Deadlock/timeout rescue + metric în toate serviciile cu locks | Alerting proactiv |
| **P2** | AdminExternalIdService audit logging | Compliance / troubleshooting |
| **P2** | BulkLockingService logging cu variant IDs | Debugging batch operations |
| **P3** | Sampling pentru success logs în high-volume flows | Reduce noise |
| **P3** | Request/Job ID correlation în toate log-urile | Tracing cross-service |



iata ce a spus gpt:
Da — cele 3 patch-uri sunt aplicate corect în V8.0.1, exact pe bug-urile pe care le-am marcat:

✅ Patch 1 — create_or_link_new (crash + contract)

Ai bifat ambele:

guard result.variant.persisted? → elimină scenariul “record ne-salvat” → RecordNotSaved.

:race_condition → :linked (success true) când mapping-ul e creat → aliniază răspunsul cu side-effectul și elimină retry-uri inutile.

Implementarea ta din VariantSyncService#create_or_link_new e corectă.

✅ Patch 2 — multi-DB row-lock safety

with_variant_transaction_if_needed există și e folosit în update_existing astfel încât:

în single DB: e no-op (ai deja tranzacție pe aceeași conexiune).

în multi DB: variant.lock! + variant.update! se întâmplă într-o tranzacție reală pe Variant.connection (nu “statement-scoped”).

Asta e fix-ul corect pentru problema clasică “tranzacție pe conexiune greșită”.

✅ Patch 3 — DRY validator

Ai eliminat duplicarea și ai centralizat validarea.

Observație minoră (non-blocking): modulul tău OptionValueValidator e definit ca mixin (metodă de instanță) și e inclus în servicii — e OK. Doar ai grijă ca fișierul să fie în path-ul Zeitwerk corect (app/services/variants/option_value_validator.rb) și să respecte naming-ul (ceea ce pare că ai).

2 “sanity checks” rămase (non-blocking, dar merită fixate ca să nu inducă ops în eroare)
1) Metrcă dual-lock: nume + semnificație (documentație inconsistentă)

În cod:

counter-ul pe care îl incrementezi e variant_sync.dual_lock_call.

În comentarii/spec output încă apar pe alocuri:

legacy_lock_acquired și chiar criteriul “trebuie să fie 0”.

Asta e inconsistent pentru că:

dual_lock_call nu poate fi 0 cât timp dual_lock_enabled=true (îl incrementezi fix când dual lock e ON).

Ce aș face (mic și clar, fără să schimbi funcționalitatea):

fie faci search&replace în doc/spec ca să zică explicit:
“variant_sync.dual_lock_call = volum, NU criteriu de eliminare”

fie adaugi încă 1 counter separat (dacă chiar vrei criteriu):

variant_sync.legacy_lock_acquired incrementat în acquire_external_id_lock_legacy

(opțional) variant_sync.v797_lock_acquired în lock-ul nou
Asta îți permite să vezi dacă legacy e încă folosit după ce oprești dual-lock.

2) Verdict/versiune în mesajele “GPT” citate

Textul citat spune “V7.9.25 … GO deploy V8.0.0”, dar tu ești pe V8.0.1.
Nu e bug tehnic, doar riscul ca cineva să facă paste în runbook și să se încurce.

Verdict actualizat

GO deploy pentru V8.0.1 pe Postgres (din perspectiva celor 3 bug-uri fixate + lock safety).
Singurele lucruri pe care le-aș mai “șlefui” înainte de a-l numi 100% “ops-friendly” sunt cele 2 de mai sus (metric naming + text/version consistency).

Dacă vrei, îți pot da un checklist ultra-scurt “pre-deploy / post-deploy monitoring” adaptat exact la ce ai deja (migrări M1–M5 + serviciile de import/admin/checkout) — fără să adaug observability pack complet.  
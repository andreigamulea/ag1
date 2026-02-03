# FAZA 3 - Servicii Restante + Product#archive! + Rake Audit

**Prerequisite:** FAZA 2 completa (289 teste pass, 0 failures)

**Sursa:** PLAN_VARIANTE9.md (sectiunile 3 si 4)

---

## CE EXISTA DEJA (din FAZA 1 + FAZA 2)

| Component | Status | Nota |
|-----------|--------|------|
| M4 migrare (variant_external_ids) | DONE | Tabel + indexi + CHECK constraints in schema.rb |
| VariantExternalId model | DONE | app/models/variant_external_id.rb |
| Imports::VariantSyncService | DONE | 11 teste (FIX 8.1 aplicat) |
| Checkout::FinalizeService | DONE | 7 teste (FIX 8.6 aplicat) |
| Orders::RestockService | DONE | 7 teste (FIX 8.7 aplicat) |

---

## CE TREBUIE IMPLEMENTAT IN FAZA 3

| # | Component | Tip | Teste Est. | Hardening |
|---|-----------|-----|------------|-----------|
| 1 | Variants::BulkLockingService | Service | ~8 | V* ORDER BY id, fail-fast, DB-portable |
| 2 | Variants::AdminExternalIdService | Service | ~8 | Advisory lock dual, normalize_lookup DRY |
| 3 | VariantExternalId.normalize_lookup | Model method | ~4 | Single source of truth normalizare |
| 4 | Product#archive! | Model method | ~5 | Lock order P -> V* (ORDER BY id) |
| 5 | Rake task variants:audit | Task | ~3 | Audit complet DB |
| 6 | Teste robustete (R1-R4) | Cross-cutting | ~14 | Idempotency, boundary, side-effects, stare mixta |
| **TOTAL** | **5 componente + robustete** | | **~42 teste** | |

---

## 1. Variants::BulkLockingService

**Fisier:** `app/services/variants/bulk_locking_service.rb`
**Teste:** `spec/services/variants/bulk_locking_service_spec.rb`

**Sursa:** PLAN_VARIANTE9.md linia 1906-2047

### Cod (din PLAN_VARIANTE9.md):

```ruby
module Variants
  class BulkLockingService
    extend IdSanitizer::ClassMethods  # Shared helper pentru sanitize_ids

    # DB-PORTABLE: Verifică dacă suntem pe Postgres (pentru CHECK constraints)
    def self.postgres?
      Variant.connection.adapter_name =~ /postgres/i
    end

    # DEADLOCK-SAFE: Lock variante in ORDER BY id
    # @param ids [Array] Array de variant IDs (se sanitizeaza intern)
    # @param sanitized [Boolean] Daca true, skip sanitizare
    def self.with_locked_variants(ids, sanitized: false)
      if sanitized
        unless ids.is_a?(Array) && ids.all? { |x| x.is_a?(Integer) && x > 0 }
          preview = ids.is_a?(Array) ? ids.first(10) : ids
          suffix  = ids.is_a?(Array) && ids.size > 10 ? "... (#{ids.size} total)" : ""
          raise ArgumentError, "sanitized: true requires Array of positive Integers, got: #{preview.inspect}#{suffix}"
        end
      else
        ids = sanitize_ids(ids)
      end
      return yield([]) if ids.empty?

      Variant.transaction do
        locked = Variant.where(id: ids).order(:id).lock.to_a
        yield(locked)
      end
    end

    # Bulk update stock: { variant_id => new_stock }
    # FAIL-FAST: Integer() pe values, nil keys = ArgumentError
    def self.bulk_update_stock(stock_by_variant_id)
      return { success: true, updated: [] } if stock_by_variant_id.empty?

      if stock_by_variant_id.keys.any? { |k| k.nil? || k.to_s.strip.empty? }
        raise ArgumentError, "variant_id keys must be present (nil/blank not allowed)"
      end

      ids = sanitize_ids(stock_by_variant_id.keys)
      updated = []

      with_locked_variants(ids, sanitized: true) do |variants|
        variants.each do |v|
          new_stock = stock_by_variant_id[v.id] || stock_by_variant_id[v.id.to_s]
          next if new_stock.nil?

          new_stock = Integer(new_stock)  # FAIL-FAST

          if !postgres? && new_stock < 0
            raise ActiveRecord::StatementInvalid, "CHECK constraint violated: stock must be >= 0"
          end

          old_stock = v.stock
          if old_stock != new_stock
            v.update_columns(stock: new_stock)
            updated << { variant_id: v.id, old_stock: old_stock, new_stock: new_stock }
          end
        end
      end

      { success: true, updated: updated }
    end

    # Bulk update price: { variant_id => new_price }
    def self.bulk_update_price(price_by_variant_id)
      return { success: true, updated: [] } if price_by_variant_id.empty?

      if price_by_variant_id.keys.any? { |k| k.nil? || k.to_s.strip.empty? }
        raise ArgumentError, "variant_id keys must be present (nil/blank not allowed)"
      end

      ids = sanitize_ids(price_by_variant_id.keys)
      updated = []

      with_locked_variants(ids, sanitized: true) do |variants|
        variants.each do |v|
          new_price = price_by_variant_id[v.id] || price_by_variant_id[v.id.to_s]
          next if new_price.nil?

          new_price = BigDecimal(new_price.to_s)  # FAIL-FAST

          if !postgres? && new_price < 0
            raise ActiveRecord::StatementInvalid, "CHECK constraint violated: price must be >= 0"
          end

          old_price = v.price
          if old_price != new_price
            v.update_columns(price: new_price)
            updated << { variant_id: v.id, old_price: old_price, new_price: new_price }
          end
        end
      end

      { success: true, updated: updated }
    end

    private_class_method :sanitize_ids
  end
end
```

### Teste necesare:

1. `with_locked_variants` - locks in id order (SQL verification)
2. `with_locked_variants` - yields locked variants sorted by id
3. `with_locked_variants` - yields empty array for empty ids
4. `with_locked_variants` - sanitized: true guard (ArgumentError pe invalid input)
5. `bulk_update_stock` - updates stock for multiple variants
6. `bulk_update_stock` - fails fast on negative stock (DB constraint / portable guard)
7. `bulk_update_stock` - fails fast on invalid stock value ("abc")
8. `bulk_update_stock` - fails fast on invalid variant id ("invalid")

### Lock order:
- V* (ORDER BY id) - compatibil cu P->V* si O->I->V*

---

## 2. Variants::AdminExternalIdService

**Fisier:** `app/services/variants/admin_external_id_service.rb`
**Teste:** `spec/services/variants/admin_external_id_service_spec.rb`

**Sursa:** PLAN_VARIANTE9.md linia 2049-2176

**Dependinta:** VariantExternalId.normalize_lookup (trebuie adaugat la model)

### Cod (din PLAN_VARIANTE9.md):

```ruby
require 'zlib'

module Variants
  class AdminExternalIdService
    include AdvisoryLockKey

    def initialize(variant)
      @variant = variant
    end

    # Link o varianta la un external ID
    def link(source:, source_account: 'default', external_id:, external_sku: nil)
      normalized = VariantExternalId.normalize_lookup(
        source: source,
        external_id: external_id,
        source_account: source_account
      )

      return { success: false, error: "source obligatoriu" } if normalized[:source].blank?
      return { success: false, error: "external_id obligatoriu" } if normalized[:external_id].blank?

      VariantExternalId.transaction do
        acquire_external_id_lock(normalized[:source], normalized[:source_account], normalized[:external_id])

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

    # Unlink un external ID de la varianta
    def unlink(source:, source_account: 'default', external_id:)
      normalized = VariantExternalId.normalize_lookup(
        source: source,
        external_id: external_id,
        source_account: source_account
      )

      VariantExternalId.transaction do
        acquire_external_id_lock(normalized[:source], normalized[:source_account], normalized[:external_id])

        mapping = @variant.variant_external_ids.find_by(normalized)

        unless mapping
          return { success: false, error: "Mapping nu exista", action: :not_found }
        end

        mapping.destroy!
        { success: true, action: :unlinked }
      end
    end

    private

    # ROLLING DEPLOY SAFETY: Dual-lock (consistent cu VariantSyncService)
    def acquire_external_id_lock(source, source_account, external_id)
      return unless supports_pg_advisory_locks?

      assert_transaction_open_on_lock_connection!

      if VariantSyncConfig.dual_lock_enabled?
        acquire_external_id_lock_legacy(source, source_account, external_id)
        VariantSyncConfig.increment_dual_lock_counter
      end
      acquire_external_id_lock_v797(source, source_account, external_id)
    end

    def acquire_external_id_lock_legacy(source, source_account, external_id)
      key = Zlib.crc32("#{source}|#{source_account}|#{external_id}")
      advisory_lock_connection.execute("SELECT pg_advisory_xact_lock(#{key}::bigint)")
      VariantSyncConfig.increment_legacy_lock_counter
    end

    def acquire_external_id_lock_v797(source, source_account, external_id)
      k1 = int32(Zlib.crc32("#{source}|#{source_account}"))
      k2 = int32(Zlib.crc32(external_id.to_s))
      advisory_lock_connection.execute("SELECT pg_advisory_xact_lock(#{k1}, #{k2})")
    end
  end
end
```

### Teste necesare:

1. `link` - creates new mapping successfully
2. `link` - returns :already_linked when same variant already mapped
3. `link` - returns :conflict when different variant already mapped
4. `link` - returns error when source is blank
5. `link` - returns error when external_id is blank
6. `link` - handles RecordNotUnique (race condition fallback)
7. `unlink` - destroys existing mapping
8. `unlink` - returns :not_found when mapping doesn't exist

### Lock order:
- A -> VEI (advisory lock, nu ia V lock)

### Advisory lock transaction guard tests:
- Deja partial in nested_transaction_safety_spec.rb
- Trebuie extins cu teste dedicate pt AdminExternalIdService (PLAN_VARIANTE9.md linia 3622-3643)

---

## 3. VariantExternalId.normalize_lookup

**Fisier:** `app/models/variant_external_id.rb` (adaugare metoda de clasa)

**Sursa:** Folosita de AdminExternalIdService pentru DRY normalizare

### Cod de adaugat:

```ruby
# Single source of truth pentru normalizare lookup params
# Folosit de AdminExternalIdService si potential de alte servicii
def self.normalize_lookup(source:, external_id:, source_account: 'default')
  {
    source: source.to_s.strip.downcase.presence,
    source_account: source_account.to_s.strip.downcase.presence || 'default',
    external_id: external_id.to_s.strip.presence
  }.compact
end
```

### Teste necesare:

1. Normalizeaza source (lowercase, strip)
2. Normalizeaza source_account (lowercase, strip, default fallback)
3. Normalizeaza external_id (strip)
4. Handle nil/blank inputs (compact removes nil keys)

---

## 4. Product#archive!

**Fisier:** `app/models/product.rb` (adaugare metoda)
**Teste:** `spec/models/product_spec.rb`

**Sursa:** PLAN_VARIANTE9.md linia 1013-1027

**NOTA:** Product NU are coloana `archived` / `archived_at` in schema.rb.
Products are `status` (string, default "active").

### Optiuni:

- **Optiunea A:** Creem migrare `add_column :products, :archived, :boolean` + `archived_at`
- **Optiunea B:** Folosim `status` existent (string) si setam "archived"
- **Optiunea C:** Skip Product#archive! daca nu exista coloanele

### Cod (adaptat - Optiunea B, folosim status existent):

```ruby
# In app/models/product.rb
def archive!
  transaction do
    lock!
    locked_variant_ids = variants.order(:id).lock.pluck(:id)
    Variant.where(id: locked_variant_ids).update_all(status: Variant.statuses[:inactive]) if locked_variant_ids.any?
    update!(status: 'archived')
  end
end

def archived?
  status == 'archived'
end
```

### Teste necesare:

1. Dezactiveaza toate variantele active
2. Seteaza product status la 'archived'
3. Lock order P -> V* (ORDER BY id) - runtime SQL verification
4. Nu afecteaza variante ale altor produse
5. Handle product fara variante

---

## 5. Rake Task variants:audit

**Fisier:** `lib/tasks/variants.rake`
**Teste:** `spec/tasks/variants_audit_spec.rb`

**Sursa:** PLAN_VARIANTE9.md linia 2182-2224

### Cod (din PLAN_VARIANTE9.md):

```ruby
namespace :variants do
  desc "Audit variants data"
  task audit: :environment do
    puts "=== VARIANTS AUDIT ==="

    sku_dups = Variant.where.not(sku: nil).group(:product_id, :sku).having('COUNT(*) > 1').count
    puts sku_dups.any? ? "SKU duplicates: #{sku_dups.count}" : "No SKU duplicates"

    if Variant.column_names.include?('options_digest')
      digest_dups = Variant.where(status: 0).where.not(options_digest: nil)
                           .group(:product_id, :options_digest).having('COUNT(*) > 1').count
      puts digest_dups.any? ? "Active digest duplicates: #{digest_dups.count}" : "No active digest duplicates"
    end

    puts Variant.where('stock < 0').exists? ? "Negative stock" : "No negative stock"
    puts Variant.where('price < 0').exists? ? "Negative price" : "No negative price"
    puts Variant.where(stock: nil).exists? ? "NULL stock" : "No NULL stock"
    puts Variant.where(price: nil).exists? ? "NULL price" : "No NULL price"

    if ActiveRecord::Base.connection.table_exists?('variant_external_ids')
      orphan_mappings = VariantExternalId.left_joins(:variant).where(variants: { id: nil }).count
      puts orphan_mappings > 0 ? "Orphan external ID mappings: #{orphan_mappings}" : "No orphan external ID mappings"

      by_source = VariantExternalId.group(:source).count
      puts "External IDs by source: #{by_source}"

      by_source_account = VariantExternalId.group(:source, :source_account).count
      puts "External IDs by source+account: #{by_source_account}"

      variants_without_mapping = Variant.left_joins(:variant_external_ids)
                                        .where(variant_external_ids: { id: nil }).count
      puts "Variants without external mapping (own products): #{variants_without_mapping}"
    end

    puts "=== END AUDIT ==="
  end
end
```

### Teste necesare:

1. Ruleaza fara erori pe DB curat
2. Detecteaza SKU duplicates
3. Detecteaza negative stock/price

---

## ORDINEA IMPLEMENTARII

1. **VariantExternalId.normalize_lookup** + teste (dependinta pt AdminExternalIdService)
2. **Variants::AdminExternalIdService** + teste
3. **Variants::BulkLockingService** + teste
4. **Product#archive!** + teste (decizie necesara: migrare sau status existent)
5. **Rake task variants:audit** + teste
6. **Advisory lock guard tests** (extindere pt AdminExternalIdService)
7. Run all tests + update documentatie

---

## TESTE DE ROBUSTETE (NON-PARANOIDE, OBLIGATORII)

### R1. Idempotency - apel dublu nu strica nimic

Fiecare operatie critica trebuie sa fie safe la apel repetat.

**Product#archive!:**
```ruby
it 'is idempotent - second call does not explode or change state' do
  product.archive!
  expect { product.archive! }.not_to raise_error
  # variantele raman inactive, product raman archived
  # nu se dubleaza side-effects
end
```

**AdminExternalIdService#link:**
```ruby
it 'returns :already_linked on second call (idempotent)' do
  service.link(source: 'erp', external_id: 'EXT-1')
  result = service.link(source: 'erp', external_id: 'EXT-1')
  expect(result[:action]).to eq(:already_linked)
end
```

**AdminExternalIdService#unlink:**
```ruby
it 'returns :not_found on second call (idempotent)' do
  service.link(source: 'erp', external_id: 'EXT-1')
  service.unlink(source: 'erp', external_id: 'EXT-1')
  result = service.unlink(source: 'erp', external_id: 'EXT-1')
  expect(result[:action]).to eq(:not_found)
end
```

**BulkLockingService:**
```ruby
it 'is idempotent - same stock value yields no changes' do
  result = BulkLockingService.bulk_update_stock({ v.id => 10 })
  expect(result[:updated]).to be_empty  # already at 10
end
```

---

### R2. Boundary: input gol dar valid - no-op fara side-effects

**BulkLockingService:**
- `with_locked_variants([])` -> yields `[]`, fara lock-uri, fara exceptii
- `bulk_update_stock({})` -> `{ success: true, updated: [] }`
- `bulk_update_price({})` -> `{ success: true, updated: [] }`

**Product#archive! fara variante:**
- Product fara variante -> seteaza status archived, fara erori

**AdminExternalIdService:**
- `link` cu source blank -> error graceful, nu exceptie

---

### R3. Nu atinge ce nu trebuie (side-effects negative)

**Product#archive!:**
```ruby
it 'does not affect variants of other products' do
  other_variant = create(:variant, product: other_product, status: :active)
  product.archive!
  expect(other_variant.reload).to be_active  # NEATINS
end
```

```ruby
it 'does not re-touch already inactive variants' do
  inactive_variant = create(:variant, product: product, status: :inactive)
  # Variantele inactive nu ar trebui sa aiba updated_at modificat
  expect { product.archive! }.not_to change { inactive_variant.reload.updated_at }
end
```

**BulkLockingService:**
```ruby
it 'does not modify variants not in the input hash' do
  result = BulkLockingService.bulk_update_stock({ v1.id => 20 })
  expect(v2.reload.stock).to eq(original_v2_stock)  # NEATINS
end
```

---

### R4. Stare mixta (date reale, nu ideale)

Testam cu stare de productie reala:
- Product cu variante mixte (active + inactive)
- Variante cu si fara external_ids
- Variante cu si fara options_digest

**Product#archive! pe stare mixta:**
```ruby
it 'handles mixed state: active + inactive variants' do
  active_v = create(:variant, product: product, status: :active)
  inactive_v = create(:variant, product: product, status: :inactive)
  # digest unic pt a evita constraint
  inactive_v.update_column(:options_digest, Digest::SHA256.hexdigest('inactive'))

  product.archive!

  expect(active_v.reload).to be_inactive   # DEZACTIVAT
  expect(inactive_v.reload).to be_inactive # RAMAS INACTIVE (nu active!)
  expect(product.reload).to be_archived
end
```

**BulkLockingService pe variante mixte:**
```ruby
it 'updates only specified variants, leaves others unchanged' do
  v_active = create(:variant, stock: 10, status: :active)
  v_inactive = create(:variant, stock: 5, status: :inactive)
  # update doar v_active
  BulkLockingService.bulk_update_stock({ v_active.id => 20 })
  expect(v_active.reload.stock).to eq(20)
  expect(v_inactive.reload.stock).to eq(5)  # NEATINS
end
```

**Rake audit pe stare mixta:**
```ruby
it 'reports correctly with mixed data (active + inactive + external_ids)' do
  # Setup cu date mixte - nu crash, output corect
end
```

---

### REZUMAT TESTE ROBUSTETE

| Categorie | Teste | Componente afectate |
|-----------|-------|---------------------|
| R1. Idempotency | ~4 | archive!, link, unlink, bulk_update |
| R2. Input gol | ~4 | BulkLocking, archive!, admin |
| R3. Nu atinge | ~3 | archive!, BulkLocking |
| R4. Stare mixta | ~3 | archive!, BulkLocking, audit |
| **TOTAL** | **~14** | |

**Total teste FAZA 3 actualizat: ~28 (componente) + ~14 (robustete) = ~42 teste**

---

## TESTE DE REFERINTA DIN PLAN_VARIANTE9.md

### BulkLockingService lock order
**Sursa:** PLAN_VARIANTE9.md linia 3338-3420
- Verifica SQL: SELECT FOR UPDATE cu ORDER BY id
- Verifica fail-fast pe negative stock si invalid input

### Product#archive! lock order (runtime verified)
**Sursa:** PLAN_VARIANTE9.md linia 3499-3561
- Verifica P -> V* lock order via SQL capture
- Verifica ca toate variantele devin inactive

### Advisory lock transaction guard
**Sursa:** PLAN_VARIANTE9.md linia 3564-3644
- Teste pt VariantSyncService SI AdminExternalIdService
- RuntimeError cand advisory lock e apelat fara tranzactie
- OK cand apelat inside VariantExternalId.transaction

### Advisory lock serialization (concurrency test)
**Sursa:** PLAN_VARIANTE9.md linia 3647-3783
- 2 thread-uri cu Queue-uri pt sincronizare
- Dovedeste ca advisory lock serializeaza accesul pe acelasi external_id
- Dovedeste ca NU blocheaza pe external_id-uri diferite
- NOTA: Test cu thread-uri - potential flaky, implementam cu grija

---

## DECIZII NECESARE INAINTE DE IMPLEMENTARE

### 1. Product#archive! - coloana `archived`
Products NU are coloanele `archived` / `archived_at` in schema.rb.
- **Optiunea A:** Creem migrare pentru `archived:boolean` + `archived_at:datetime`
- **Optiunea B:** Folosim `status` existent (string, default "active") cu valoarea "archived"
- **Optiunea C:** Skip Product#archive! (nu e necesar acum)

### 2. IdSanitizer::ClassMethods
BulkLockingService foloseste `extend IdSanitizer::ClassMethods`.
IdSanitizer concern actual trebuie verificat daca expune ClassMethods module separat.

### 3. Advisory lock serialization test
Testul cu thread-uri din PLAN_VARIANTE9.md (linia 3647-3783) poate fi flaky.
- **Optiunea A:** Implementam cu timeout-uri generoase si retry
- **Optiunea B:** Skip (avem deja teste deterministe pt advisory lock order in FAZA 2)

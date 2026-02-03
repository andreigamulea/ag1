# PLAN IMPLEMENTARE V9.0.2

> **Single source of truth pentru implementarea PLAN_VARIANTE9.md**
> Copiază codul din PLAN_VARIANTE9.md în fișierele de mai jos, în ordinea specificată.

---

## FAZA 0 — PREGĂTIRE (pre-implementare)

### Verificări preliminare

- [ ] Confirmă că ai Ruby 3.x și Rails 7.x
- [ ] Confirmă că ai Postgres (migrările M2, M3, M4, M5 au componente Postgres-only)
- [ ] Confirmă că fișierele care folosesc `Zlib.crc32` au `require 'zlib'` local:
  - `Imports::VariantSyncService`
  - `Variants::AdminExternalIdService`
- [ ] Confirmă că ai tag/helper pentru `:postgres_only` în RSpec (sau skip explicit în spec)
- [ ] Backup DB înainte de migrare: `pg_dump -Fc database_name > backup_before_migration.dump`

---

## FAZA 1 — SCHEMA CORE (M1–M3)

### Pas 1.1: Baseline audit (opțional dacă e codebase nou)
```bash
rails variants:audit  # dacă task-ul există deja
```

### Pas 1.2: Migrări DB

#### M1: Add Columns
**Fișier:** `db/migrate/YYYYMMDDHHMMSS_m1_add_variants_columns.rb`

```bash
rails generate migration M1AddVariantsColumns
```

Copiază codul din PLAN_VARIANTE9.md secțiunea "### M1: Add Columns"

**Verificare post-M1:**
- [ ] Coloana `variants.status` există (integer, default 0)
- [ ] Coloana `variants.options_digest` există (text)
- [ ] Coloana `variants.external_sku` există (string)
- [ ] Coloanele `order_items.*` există (variant_sku, variant_options_text, vat_rate_snapshot, currency, line_total_gross, tax_amount)
- [ ] Index pe `variants.status` există

---

#### M2: Cleanup & Preflight (⚠️ HEAVY - maintenance window)
**Fișier:** `db/migrate/YYYYMMDDHHMMSS_m2_cleanup_variants_data.rb`

```bash
rails generate migration M2CleanupVariantsData
```

Copiază codul din PLAN_VARIANTE9.md secțiunea "### M2: Cleanup & Preflight"

**⚠️ ATENȚIE:**
- M2 e Postgres-only (skip pe SQLite/MySQL)
- Poate fi HEAVY pe tabele mari (>100k rows)
- Rulează în maintenance window pentru prod
- Monitorizează `pg_stat_activity` și `pg_locks` în timpul rulării

**Verificare post-M2:**
- [ ] Niciun SKU duplicat per product
- [ ] Niciun external_sku duplicat global
- [ ] Nicio variantă cu multiple valori pe același option_type
- [ ] Toate variantele au SKU non-null
- [ ] Toate variantele au stock >= 0 și price >= 0
- [ ] options_digest calculat pentru variantele cu opțiuni

---

#### M3: Constraints & Indexes
**Fișier:** `db/migrate/YYYYMMDDHHMMSS_m3_add_variants_constraints.rb`

```bash
rails generate migration M3AddVariantsConstraints
```

Copiază codul din PLAN_VARIANTE9.md secțiunea "### M3: Constraints & Indexes"

**Verificare post-M3:**
- [ ] Index `idx_unique_sku_per_product` există
- [ ] Index `idx_unique_ovv` există
- [ ] Foreign keys pe `option_value_variants`, `variants`, `order_items`
- [ ] (Postgres only) Partial indexes:
  - [ ] `idx_unique_active_options_per_product`
  - [ ] `idx_unique_active_default_variant`
  - [ ] `idx_unique_external_sku`
- [ ] (Postgres only) CHECK constraints:
  - [ ] `chk_variants_price_positive`
  - [ ] `chk_variants_stock_positive`
  - [ ] `chk_variants_status_enum`

---

### Pas 1.3: Rulează migrările
```bash
rails db:migrate
```

### Pas 1.4: Audit post-migrare
```bash
rails variants:audit
```

---

## FAZA 2 — COD CORE (Concerns + Config + Modele + Servicii)

### Pas 2.1: Concerns

#### IdSanitizer
**Fișier:** `app/models/concerns/id_sanitizer.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### IdSanitizer"

**Invariant critic:**
- `STRICT_DECIMAL_REGEX` = `/\A[1-9]\d*\z/`
- Fail-fast pe hex/octal/binary/underscore
- Zero/negative aruncă `ArgumentError`

---

#### AdvisoryLockKey
**Fișier:** `app/models/concerns/advisory_lock_key.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### AdvisoryLockKey"

**Invariante critice:**
- `int32(u)` pentru conversie signed
- `transaction_open_on?(conn)` cu fallback la `open_transactions` (Fix 7)
- `assert_transaction_open_on_lock_connection!` fail-fast
- `supports_pg_advisory_locks?` pentru DB-portability

---

### Pas 2.2: Config

#### VariantSyncConfig
**Fișier:** `config/initializers/variant_sync.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### VariantSyncConfig"

**Invariante critice:**
- ENV `VARIANT_SYNC_DUAL_LOCK_ENABLED` (default: true)
- `increment_dual_lock_counter` pentru volum
- `increment_legacy_lock_counter` pentru deprecation tracking
- Boot-time log pentru status

---

### Pas 2.3: Modele

#### Variant
**Fișier:** `app/models/variant.rb`

Copiază/actualizează codul din PLAN_VARIANTE9.md secțiunea "### Variant"

**Invariante critice:**
- `enum :status, { active: 0, inactive: 1 }`
- `validates :sku, :price, :stock`
- `validate :no_active_digest_conflict`
- `before_validation :normalize_identifiers`
- `has_many :variant_external_ids, dependent: :destroy`
- `find_or_create_external_id!` cu `requires_new: true`

---

#### VariantExternalId
**Fișier:** `app/models/variant_external_id.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### VariantExternalId"

**Invariante critice:**
- `SOURCE_FORMAT` = `/\A[a-z][a-z0-9_]{0,49}\z/`
- `normalize_values` înainte de validation
- `normalize_lookup` class method pentru DRY
- `external_id` normalizat cu `.to_s.strip.presence` (Fix 6)

---

#### OptionValueVariant
**Fișier:** `app/models/option_value_variant.rb`

Copiază/verifică codul din PLAN_VARIANTE9.md secțiunea "### OptionValueVariant"

---

#### Product
**Fișier:** `app/models/product.rb`

Copiază/actualizează codul din PLAN_VARIANTE9.md secțiunea "### Product"

**Invariant critic:**
- `archive!` cu lock order P → V* (order id)
- `locked_variant_ids = variants.order(:id).lock.pluck(:id)`

---

### Pas 2.4: Servicii

#### Variants::OptionValueValidator
**Fișier:** `app/services/variants/option_value_validator.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Variants::OptionValueValidator"

---

#### Variants::CreateOrReactivateService
**Fișier:** `app/services/variants/create_or_reactivate_service.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Variants::CreateOrReactivateService"

**Invariante critice:**
- `include IdSanitizer`
- `include OptionValueValidator`
- `@product.transaction(requires_new: true)`
- `@product.lock!` înainte de orice operație

---

#### Variants::UpdateOptionsService
**Fișier:** `app/services/variants/update_options_service.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Variants::UpdateOptionsService"

**Invariante critice:**
- `include IdSanitizer`
- `include OptionValueValidator`
- `@product.transaction(requires_new: true)`
- `@product.lock!` apoi `@variant.lock!`

---

#### Products::UpdateOptionTypesService
**Fișier:** `app/services/products/update_option_types_service.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Products::UpdateOptionTypesService"

**Invariant critic:**
- `variants.order(:id).lock.to_a` pentru lock order

---

#### Checkout::FinalizeService
**Fișier:** `app/services/checkout/finalize_service.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Checkout::FinalizeService"

**Invariante critice:**
- Lock order O → I → V* (order id)
- `items.group_by(&:variant_id)` apoi `sorted_ids.each`

---

#### Orders::ConcurrencyPolicy
**Fișier:** `app/services/orders/concurrency_policy.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Orders::ConcurrencyPolicy"

---

#### Orders::RestockService
**Fișier:** `app/services/orders/restock_service.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Orders::RestockService"

**Invariant critic:**
- Lock order O → I → V* (order id)
- `Variant.where(id: variant_ids).order(:id).lock`

---

#### Variants::BulkLockingService
**Fișier:** `app/services/variants/bulk_locking_service.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Variants::BulkLockingService"

**Invariante critice:**
- `extend IdSanitizer::ClassMethods`
- `Variant.where(id: ids).order(:id).lock`
- DB-portable check pentru stock/price >= 0

---

### Pas 2.5: Rake Tasks

#### Audit
**Fișier:** `lib/tasks/variants.rake`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Audit"

---

### Pas 2.6: Rulează testele
```bash
bundle exec rspec
```

---

## FAZA 3 — EXTERNAL IDs MULTI-SOURCE (M4–M5)

### Pas 3.1: Migrări

#### M4: Create VariantExternalIds
**Fișier:** `db/migrate/YYYYMMDDHHMMSS_m4_create_variant_external_ids.rb`

```bash
rails generate migration M4CreateVariantExternalIds
```

Copiază codul din PLAN_VARIANTE9.md secțiunea "### M4: External IDs Mapping Table"

**Verificare post-M4:**
- [ ] Tabel `variant_external_ids` există
- [ ] Index `idx_unique_source_account_external_id` există (unique)
- [ ] Index `idx_vei_variant` există
- [ ] Index `idx_vei_source` există
- [ ] Index `idx_vei_source_account` există
- [ ] (Postgres only) CHECK constraints pe source/source_account/external_id

---

#### M5: Backfill External IDs (opțional)
**Fișier:** `db/migrate/YYYYMMDDHHMMSS_m5_backfill_variant_external_ids.rb`

```bash
rails generate migration M5BackfillVariantExternalIds
```

Copiază codul din PLAN_VARIANTE9.md secțiunea "### M5: Backfill External IDs"

**Notă:** M5 migrează `variants.external_sku` existent în `variant_external_ids` cu source='legacy'.

---

### Pas 3.2: Servicii pentru External IDs

#### Imports::VariantSyncService
**Fișier:** `app/services/imports/variant_sync_service.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Imports::VariantSyncService"

**Invariante critice:**
- `require 'zlib'` la început
- `include AdvisoryLockKey`
- `include IdSanitizer`
- `VariantExternalId.transaction` pentru advisory lock
- `with_variant_transaction_if_needed` pentru multi-DB safety (Fix 2)
- `transaction_open_on?(conn)` (Fix 7)
- Guard `result.variant&.persisted?` (Fix 1)
- `:race_condition` → `:linked` (Fix 1)
- `handle_unique_violation` returnează `:conflict` când mapping există (Fix 8)
- Idempotency hardening pentru `:conflict` cu variant nil (Fix 5)

---

#### Variants::AdminExternalIdService
**Fișier:** `app/services/variants/admin_external_id_service.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Variants::AdminExternalIdService"

**Invariante critice:**
- `require 'zlib'` la început
- `include AdvisoryLockKey`
- `VariantExternalId.transaction` pentru advisory lock
- Dual-lock consistent cu VariantSyncService

---

### Pas 3.3: Rulează migrările
```bash
rails db:migrate
```

### Pas 3.4: Audit final
```bash
rails variants:audit
```

---

## FAZA 4 — TESTE

### Pas 4.1: Support helpers

#### LockOrderHelper
**Fișier:** `spec/support/lock_order_helper.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Helper: Lock Order Verification"

---

### Pas 4.2: Unit tests

#### IdSanitizer
**Fișier:** `spec/models/concerns/id_sanitizer_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: IdSanitizer unit spec"

---

#### Lock Safety Patterns
**Fișier:** `spec/lint/lock_safety_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: Pattern-uri interzise în codebase"

---

#### VariantSyncConfig
**Fișier:** `spec/config/variant_sync_config_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: Dual-lock deprecation tracking"

---

### Pas 4.3: Regression tests (postgres_only)

#### Nested Transaction Safety
**Fișier:** `spec/services/variants/nested_transaction_safety_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: Nested Transaction Safety"

---

#### Product Mismatch
**Fișier:** `spec/services/imports/variant_sync_service_product_mismatch_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: Product mismatch în race condition"

---

#### Variant Lock Safety
**Fișier:** `spec/models/variant_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: Variant.update nu atinge product"

---

#### BulkLockingService
**Fișier:** `spec/services/variants/bulk_locking_service_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: BulkLockingService lock order"

---

#### RestockService
**Fișier:** `spec/services/orders/restock_service_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: RestockService lock order"

---

#### Product#archive!
**Fișier:** `spec/models/product_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: Product#archive! lock order"

---

#### Advisory Lock Guard
**Fișier:** `spec/services/imports/variant_sync_service_advisory_lock_guard_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: Advisory lock transaction guard"

---

#### Advisory Lock Serialization
**Fișier:** `spec/services/imports/variant_sync_service_serialization_spec.rb`

Copiază codul din PLAN_VARIANTE9.md secțiunea "### Test: Advisory lock serialization"

---

### Pas 4.4: Rulează toate testele
```bash
bundle exec rspec
```

---

## FAZA 5 — DEPLOY

### Pre-deploy checklist

- [ ] Toate testele trec local
- [ ] Backup DB făcut
- [ ] Maintenance window anunțat (pentru M2 dacă tabel mare)
- [ ] Monitoring setup pentru:
  - Deadlock-uri (`deadlock detected` în logs)
  - Erori de unicitate pe `variant_external_ids`
  - `product_mismatch` în logs

### Deploy sequence

1. **Staging:**
   - `rails db:migrate`
   - `rails variants:audit`
   - Testare manuală flow-uri critice
   - Monitorizare 24h

2. **Production:**
   - (M1) `rails db:migrate VERSION=XXXM1` - add columns
   - Verificare aplicație funcționează
   - (M2) În maintenance window: `rails db:migrate VERSION=XXXM2` - cleanup
   - Monitorizare query times
   - (M3) `rails db:migrate VERSION=XXXM3` - constraints
   - Deploy cod nou
   - `rails variants:audit`

3. **Când ai nevoie de multi-source feeds:**
   - (M4) `rails db:migrate VERSION=XXXM4`
   - (M5) `rails db:migrate VERSION=XXXM5` (opțional - backfill)
   - Deploy servicii VariantSyncService + AdminExternalIdService
   - Actualizează importerii să folosească VariantSyncService

### Post-deploy monitoring

- [ ] `variant_sync.dual_lock_call` metric funcționează
- [ ] `variant_sync.legacy_lock_call` metric funcționează
- [ ] Niciun deadlock în primele 24h
- [ ] Niciun `product_mismatch` (dacă apare = config feed greșit)
- [ ] Import jobs funcționează corect

---

## VERIFICĂRI FINALE ("identic cu V8.0.2")

Cele mai importante 15 verificări:

1. [ ] Index names identice (idx_unique_*, idx_vei_*, idx_ovv_*, chk_*)
2. [ ] Partial unique indexes doar pe Postgres (și `return unless postgres?`)
3. [ ] M2CleanupVariantsData e Postgres-only cu preflight-uri fail-fast
4. [ ] M1 are preflight check pentru `variants.status` type (Fix 9)
5. [ ] CreateOrReactivateService are `@product.transaction(requires_new: true) + @product.lock!`
6. [ ] UpdateOptionsService are `@product.transaction(requires_new: true) + lock product + lock variant`
7. [ ] OptionValueValidator e extras și inclus în ambele servicii
8. [ ] VariantSyncService#update_existing folosește `with_variant_transaction_if_needed`
9. [ ] VariantSyncService#create_or_link_new are guard `result.variant&.persisted?`
10. [ ] VariantSyncService#create_or_link_new: `:already_exists/:race_condition` → return `success: true, action: :linked`
11. [ ] VariantSyncService#handle_unique_violation returnează `:conflict` când mapping există (Fix 8)
12. [ ] Advisory lock guard: `assert_transaction_open_on_lock_connection!` apelat înainte de `pg_advisory_xact_lock`
13. [ ] `transaction_open_on?(conn)` cu fallback (Fix 7)
14. [ ] Lock order: orice lock pe variants bulk e cu `.order(:id).lock`
15. [ ] Metrici: `increment_legacy_lock_counter` în loc de StatsD direct (Fix 4)

---

## STRUCTURĂ FIȘIERE FINALĂ

```
app/
├── models/
│   ├── concerns/
│   │   ├── id_sanitizer.rb
│   │   └── advisory_lock_key.rb
│   ├── variant.rb
│   ├── variant_external_id.rb
│   ├── option_value_variant.rb
│   └── product.rb
├── services/
│   ├── variants/
│   │   ├── option_value_validator.rb
│   │   ├── create_or_reactivate_service.rb
│   │   ├── update_options_service.rb
│   │   ├── bulk_locking_service.rb
│   │   └── admin_external_id_service.rb
│   ├── products/
│   │   └── update_option_types_service.rb
│   ├── imports/
│   │   └── variant_sync_service.rb
│   ├── checkout/
│   │   └── finalize_service.rb
│   └── orders/
│       ├── concurrency_policy.rb
│       └── restock_service.rb
config/
└── initializers/
    └── variant_sync.rb
db/
└── migrate/
    ├── XXXX_m1_add_variants_columns.rb
    ├── XXXX_m2_cleanup_variants_data.rb
    ├── XXXX_m3_add_variants_constraints.rb
    ├── XXXX_m4_create_variant_external_ids.rb
    └── XXXX_m5_backfill_variant_external_ids.rb
lib/
└── tasks/
    └── variants.rake
spec/
├── support/
│   └── lock_order_helper.rb
├── models/
│   ├── concerns/
│   │   └── id_sanitizer_spec.rb
│   ├── variant_spec.rb
│   └── product_spec.rb
├── config/
│   └── variant_sync_config_spec.rb
├── lint/
│   └── lock_safety_spec.rb
└── services/
    ├── variants/
    │   ├── nested_transaction_safety_spec.rb
    │   └── bulk_locking_service_spec.rb
    ├── imports/
    │   ├── variant_sync_service_product_mismatch_spec.rb
    │   ├── variant_sync_service_advisory_lock_guard_spec.rb
    │   └── variant_sync_service_serialization_spec.rb
    └── orders/
        └── restock_service_spec.rb
```

---

## CHANGELOG V8.0.2

### Fixes aplicați:
- **Fix 1**: `create_or_link_new` - guard `.persisted?` + return `:linked` pentru `:race_condition`
- **Fix 2**: `update_existing` - `with_variant_transaction_if_needed` pentru multi-DB row-lock safety
- **Fix 3**: Extract `Variants::OptionValueValidator` - DRY pentru `valid_option_values_for_product?`
- **Fix 4**: Metric drift - folosește `VariantSyncConfig.increment_legacy_lock_counter` în loc de StatsD direct
- **Fix 5**: Idempotency hardening - `create_or_link_new` face lookup pe `:conflict` când variant e nil
- **Fix 6**: Normalizare `external_id` - `.to_s.strip.presence` (consistent cu `external_sku`)
- **Fix 7**: `transaction_open_on?` helper - fallback la `open_transactions` dacă `transaction_open?` nu există
- **Fix 8**: `handle_unique_violation` - returnează `:conflict` în loc de `:linked` când mapping există dar pentru alt variant
- **Fix 9**: M1 preflight - verifică tipul coloanei `variants.status` înainte de migrare

---

## NOTĂ FINALĂ

Acest plan este **implementation-ready**. Nu modifică funcționalitatea existentă, doar adaugă cod nou.

Pentru orice întrebări despre implementare, consultă secțiunile detaliate din PLAN_VARIANTE9.md.


Planul de implementare V9.0.2 este complet și salvat în PLAN_VARIANTE10.md.

Documentul conține:

5 faze organizate cronologic pentru implementare
Checklisturi cu verificări pentru fiecare pas
Invariante critice marcate pentru fiecare componentă
Structura de fișiere finală
15 verificări finale pentru a confirma implementarea corectă
Deploy sequence pentru staging și production
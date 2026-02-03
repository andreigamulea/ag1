# PLAN FAZA 2 - Concerns & Services Implementation

## Status: 📋 PLANNING

**Prerequisite:** ✅ FAZA 1 completă (162 teste pass, 0 failures)

---

## Obiectiv FAZA 2

Implementarea **Concerns** (module partajate) și **Services** (obiecte de serviciu pentru operații complexe de business logic) conform PLAN_VARIANTE9.md.

---

## 1. CONCERNS (4 module partajate)

### 1.1. IdSanitizer
**Locație:** `app/models/concerns/id_sanitizer.rb`

**Responsabilitate:**
- Sanitizare array-uri de ID-uri pentru operații pe variante/opțiuni
- Validare strict decimală (reject hex/octal/binary/underscore format)
- FAIL-FAST semantics: ArgumentError pe input invalid
- SINGLE-SOURCE pattern: instance method delegă la class method

**Funcționalități:**
- `sanitize_ids(input)` - instance method
- `ClassMethods.sanitize_ids(input)` - class method (SINGLE-SOURCE)
- Returnează Array<Integer> sortat, unic, doar valori > 0
- Reject: nil/empty string (drop), hex ("0x10"), octal ("0o17"), binary ("0b101"), underscore separator ("1_000"), leading zero ("01"), negativ, zero

**Teste necesare:**
- Validare format strict decimal (reject hex/octal/binary/underscore)
- Validare pozitiv (reject 0, -1)
- Drop nil/empty string
- Conversie "123" → 123
- Sort + unique
- ArgumentError pe input invalid

---

### 1.2. AdvisoryLockKey
**Locație:** `app/models/concerns/advisory_lock_key.rb`

**Responsabilitate:**
- Helper pentru generare chei advisory lock (Postgres pg_advisory_xact_lock)
- DB-PORTABLE: skip lock pe non-Postgres (SQLite, MySQL)
- MULTI-DB SAFETY: folosește `advisory_lock_connection` pentru conexiunea corectă
- FAIL-FAST GUARD: verifică tranzacție deschisă înainte de lock

**Funcționalități:**
- `supports_pg_advisory_locks?` - verifică dacă DB suportă advisory locks
- `advisory_lock_connection` - conexiunea pentru lock (default: VariantExternalId.connection)
- `transaction_open_on?(conn)` - verifică tranzacție deschisă (cu fallback pentru adaptere vechi)
- `assert_transaction_open_on_lock_connection!` - FAIL-FAST guard
- `int32(u)` - convertește CRC32 unsigned la signed int32 pentru Postgres

**Teste necesare:**
- `supports_pg_advisory_locks?` returnează true pe Postgres, false pe SQLite
- `transaction_open_on?` detectează tranzacție deschisă
- `assert_transaction_open_on_lock_connection!` raise error când nu e tranzacție
- `int32` conversie corectă pentru valori >= 2^31

---

### 1.3. VariantSyncConfig
**Locație:** `config/initializers/variant_sync.rb`

**Responsabilitate:**
- Feature flags pentru Imports::VariantSyncService
- Control dual-lock deprecation (legacy + new format advisory lock)
- Observability metrics pentru deprecation tracking

**Funcționalități:**
- `VariantSyncConfig.dual_lock_enabled?` - citește ENV['VARIANT_SYNC_DUAL_LOCK_ENABLED']
- `increment_dual_lock_counter` - metric pentru volumul dual-lock
- `increment_legacy_lock_counter` - metric pentru legacy lock (criteriu deprecation)
- Boot-time logging pentru status dual-lock

**Teste necesare:**
- `dual_lock_enabled?` parsează corect ENV (case-insensitive: "true", "TRUE", "false", "FALSE")
- Default = true când ENV absent
- Metric counters apelează StatsD când e definit
- Boot-time log emis la after_initialize

---

### 1.4. Variants::OptionValueValidator
**Locație:** `app/services/variants/option_value_validator.rb`

**Responsabilitate:**
- DRY validare option_value_ids pentru CreateOrReactivateService și UpdateOptionsService
- Verifică că toate IDs există, au option_types distincte, aparțin produsului

**Funcționalități:**
- `valid_option_values_for_product?(product, ids)` - returnează boolean
- Validări:
  1. Toate IDs există în DB
  2. Nu există 2 valori din același option_type
  3. Toate option_types sunt asociate produsului

**Teste necesare:**
- Toate IDs există → true
- ID inexistent → false
- 2 valori din același option_type → false
- option_type nu e asociat produsului → false
- Array gol → true

---

## 2. SERVICES (6 servicii principale)

### 2.1. Variants::CreateOrReactivateService
**Locație:** `app/services/variants/create_or_reactivate_service.rb`

**Responsabilitate:**
- Creează variantă nouă SAU reactivează variantă inactivă
- Reactivare soft (fără destroy) pentru a păstra istoric order_items
- Lock pe product pentru serializare cu UpdateOptionTypesService
- requires_new: true pentru savepoint (când apelat din tranzacție externă, ex: VariantSyncService)

**Parametri:**
- `product` - produsul pentru care creăm varianta
- `option_value_ids` - array de IDs (sanitizat via IdSanitizer)
- `attributes` - hash cu sku/price/stock/vat_rate/status

**Result struct:**
- `success` (boolean)
- `variant` (Variant record)
- `action` (symbol: :created, :reactivated, :updated, :invalid, :conflict, :linked)
- `error` (string sau nil)

**Logică:**
1. Sanitize option_value_ids
2. Lock product
3. Calculează digest (nil pentru default, "id1-id2-id3" pentru opțiuni)
4. Validează option_values aparțin produsului (via OptionValueValidator)
5. Dacă desired_status = inactive → creează mereu nouă variantă
6. Altfel găsește variantă existentă (active SAU inactive cu același digest)
7. Dacă există → reactivare/update, altfel → create new
8. Gestionează RecordNotUnique via handle_unique_violation (SKU/digest conflict)

**Teste necesare:**
- Creează variantă nouă (default + cu opțiuni)
- Reactivează variantă inactivă
- Update variantă activă existentă (ex: schimbare preț)
- Conflict SKU duplicate → action: :conflict
- Conflict digest duplicate → action: :conflict
- Validare option_values invalide → action: :invalid
- requires_new: true funcționează când apelat din tranzacție externă
- handle_unique_violation prinde RecordNotUnique și returnează conflict

---

### 2.2. Variants::UpdateOptionsService
**Locație:** `app/services/variants/update_options_service.rb`

**Responsabilitate:**
- Schimbă combinația de opțiuni pentru variantă existentă
- Verifică conflict digest ÎNAINTE de DB (early return)
- Lock pe product pentru serializare cu UpdateOptionTypesService
- requires_new: true pentru savepoint

**Parametri:**
- `variant` - varianta de modificat
- `option_value_ids` - noul array de IDs

**Result struct:**
- Similar cu CreateOrReactivateService

**Logică:**
1. Sanitize option_value_ids
2. Lock product
3. Validează option_values aparțin produsului
4. Calculează noul digest
5. Verifică conflict ÎNAINTE de DB (find existing active cu același digest)
6. Dacă conflict → return :conflict
7. Update variant.options_digest + replace option_value_variants
8. Gestionează RecordNotUnique (race condition)

**Teste necesare:**
- Update opțiuni cu succes
- Conflict digest existent → action: :conflict
- Validare option_values invalide → action: :invalid
- RecordNotUnique (race) → handle corect

---

### 2.3. Products::UpdateOptionTypesService
**Locație:** `app/services/products/update_option_types_service.rb`

**Responsabilitate:**
- Adaugă/șterge option_types la/din produs
- Dezactivează variante active care devin incomplete (când ștergi option_type)
- Recalculează options_digest pentru variante afectate
- Lock P → V (ORDER BY id)

**Parametri:**
- `product` - produsul de modificat
- `option_type_ids` - noul array de IDs

**Result struct:**
- Similar cu CreateOrReactivateService

**Logică:**
1. Lock product
2. Calculează delta (added/removed option_types)
3. Dacă removed → găsește variante afectate (active cu opțiuni din tipul șters)
4. Lock variante afectate (ORDER BY id)
5. Dezactivează variantele afectate
6. Pentru toate variantele rămase active → recalculează digest
7. Sync product_option_types

**Teste necesare:**
- Adaugă option_type la produs
- Șterge option_type → dezactivează variante afectate
- Recalculează digest pentru variante rămase
- Lock order P → V verificat

---

### 2.4. Imports::VariantSyncService
**Locație:** `app/services/imports/variant_sync_service.rb`

**Responsabilitate:**
- Sincronizare feed-uri externe (ERP, marketplace, furnizori)
- Găsește/creează variantă după external_id
- Link external_id la variantă (variant_external_ids table)
- Advisory lock pentru serializare la nivel external_id
- DUAL-LOCK pentru rolling deploy safety (legacy + new format)

**Parametri:**
- `source` - sursă (ex: "erp", "emag")
- `source_account` - cont (default: "default", ex: "emag_ro_1")

**API:**
- `call(product, external_id, option_value_ids, attributes)` - sincronizare variantă

**Result struct:**
- `success` (boolean)
- `variant` (Variant record)
- `action` (symbol: :created, :reactivated, :updated, :linked, :conflict, :invalid)
- `error` (string sau nil)

**Logică:**
1. Normalizează external_id (to_s.strip.presence)
2. Acquire advisory lock (dual-lock când feature flag activat)
3. Găsește mapping existent (VariantExternalId.find_mapping)
4. Dacă mapping există:
   - Verifică product mismatch
   - Verifică options mismatch
   - Update attributes (price/stock/sku) → action: :updated
5. Dacă mapping nu există:
   - Apelează CreateOrReactivateService
   - Creează mapping VariantExternalId
   - action: :created / :reactivated / :linked
6. Gestionează RecordNotUnique via handle_unique_violation

**Teste necesare:**
- Creează variantă + mapping nouă
- Găsește variantă existentă după external_id → update
- Product mismatch → error
- Options mismatch → error
- Advisory lock dual-lock când feature flag activ
- Advisory lock skip legacy când feature flag dezactivat
- RecordNotUnique → handle corect
- Normalizare external_id (whitespace/case)

---

### 2.5. Checkout::FinalizeService
**Locație:** `app/services/checkout/finalize_service.rb`

**Responsabilitate:**
- Finalizare comandă (snapshot variant → order_item, decrement stock)
- Lock O → I → V (ORDER BY id) pentru deadlock safety
- Snapshot imutabil: sku, options_text, vat_rate, line_total_gross, tax_amount
- Fail-fast când variant nil/inactive/stock insuficient

**Parametri:**
- `order` - comanda de finalizat

**Logică:**
1. Lock order
2. Lock order_items (ORDER BY id)
3. Pentru fiecare item:
   - Lock variant (ORDER BY id)
   - Verifică variant activ + stock suficient
   - Snapshot data (sku, options_text, vat_rate, line_total_gross, tax_amount)
   - Decrement stock (update_column pentru bypass callbacks)
4. Mark order as paid

**Teste necesare:**
- Finalizare comandă cu succes → snapshot + decrement stock
- Variant nil → error
- Variant inactive → error
- Stock insuficient → error
- Lock order O → I → V verificat
- Snapshot corect (sku, options_text, vat_rate, totals)

---

### 2.6. Orders::RestockService
**Locație:** `app/services/orders/restock_service.rb`

**Responsabilitate:**
- Reîncărcare stoc după cancel/refund comandă
- Lock O → I → V (ORDER BY id) pentru deadlock safety
- Doar pentru order_items cu variant_id nenull

**Parametri:**
- `order` - comanda de anulat/restituit

**Logică:**
1. Lock order
2. Lock order_items (ORDER BY id)
3. Colectează variant_ids (COMPACT pentru a exclude nil)
4. Lock variants (ORDER BY id)
5. Increment stock pentru fiecare variant
6. Mark order as cancelled/refunded

**Teste necesare:**
- Restock cu succes → increment stock
- Order_items cu variant_id = nil → skip
- Lock order O → I → V verificat

---

## 3. PLAN IMPLEMENTARE SECVENȚIAL

### Etapa 1: Concerns (simplele)
1. ✅ `IdSanitizer` + teste (6 teste)
2. ✅ `AdvisoryLockKey` + teste (4 teste - skip Postgres-specific pe SQLite)
3. ✅ `VariantSyncConfig` + teste (4 teste)
4. ✅ `Variants::OptionValueValidator` + teste (5 teste)

**Total Etapa 1:** ~19 teste

---

### Etapa 2: Services Core (fără external IDs)
1. ✅ `Variants::CreateOrReactivateService` + teste (12 teste)
2. ✅ `Variants::UpdateOptionsService` + teste (6 teste)
3. ✅ `Products::UpdateOptionTypesService` + teste (8 teste)

**Total Etapa 2:** ~26 teste

---

### Etapa 3: Services External IDs
1. ✅ `Imports::VariantSyncService` + teste (15 teste)

**Total Etapa 3:** ~15 teste

---

### Etapa 4: Services Checkout & Orders
1. ✅ `Checkout::FinalizeService` + teste (8 teste)
2. ✅ `Orders::RestockService` + teste (4 teste)

**Total Etapa 4:** ~12 teste

---

### Etapa 5: Integration & Lock Order Tests
1. ✅ Integration tests pentru flow-uri complete (8 teste)
2. ✅ Lock order runtime verification tests (6 teste)

**Total Etapa 5:** ~14 teste

---

## 4. ESTIMARE TESTE TOTALE FAZA 2

| Categorie | Teste |
|-----------|-------|
| Concerns | 19 |
| Services Core | 26 |
| Services External IDs | 15 |
| Services Checkout/Orders | 12 |
| Integration & Lock Order | 14 |
| **TOTAL FAZA 2** | **~86 teste** |

---

## 5. DEPENDENCIES & ORDER

**Ordinea CORECTĂ de implementare (respectă dependencies):**

```
IdSanitizer
    ↓
OptionValueValidator
    ↓
CreateOrReactivateService ← (necesită IdSanitizer, OptionValueValidator)
    ↓
UpdateOptionsService ← (necesită IdSanitizer, OptionValueValidator)
    ↓
UpdateOptionTypesService
    ↓
AdvisoryLockKey + VariantSyncConfig
    ↓
VariantSyncService ← (necesită CreateOrReactivateService, AdvisoryLockKey, VariantSyncConfig)
    ↓
FinalizeService
    ↓
RestockService
```

---

## 6. CHECKLIST IMPLEMENTARE

### Concerns:
- [ ] IdSanitizer + teste
- [ ] AdvisoryLockKey + teste
- [ ] VariantSyncConfig + teste
- [ ] Variants::OptionValueValidator + teste

### Services Core:
- [ ] Variants::CreateOrReactivateService + teste
- [ ] Variants::UpdateOptionsService + teste
- [ ] Products::UpdateOptionTypesService + teste

### Services External IDs:
- [ ] Imports::VariantSyncService + teste

### Services Checkout/Orders:
- [ ] Checkout::FinalizeService + teste
- [ ] Orders::RestockService + teste

### Integration:
- [ ] Integration tests (cross-service flows)
- [ ] Lock order runtime verification tests

### Documentation:
- [ ] Update TESTE_FAZA2.md cu rezultate

---

## 7. OBSERVAȚII IMPORTANTE

### FAIL-FAST Patterns:
- `IdSanitizer` → ArgumentError pe input invalid (nu silent drop)
- `AdvisoryLockKey` → RuntimeError când nu e tranzacție deschisă
- Services → Result struct cu success/error (nu exceptions pentru business logic failures)

### Lock Order (CRITICAL pentru deadlock safety):
- **P → V**: CreateOrReactivateService, UpdateOptionsService, UpdateOptionTypesService, archive!
- **O → I → V**: FinalizeService, RestockService
- **ORDER BY id**: ÎNTOTDEAUNA când lock-uim multiple rows

### Transaction Safety:
- **requires_new: true**: Când serviciul e apelat dintr-o tranzacție externă (creează SAVEPOINT)
- Advisory locks → NECESITĂ tranzacție deschisă pe conexiunea corectă

### Normalizare:
- `external_id` → `.to_s.strip.presence` (whitespace-only devine nil)
- `external_sku` → `.to_s.strip.presence`
- `sku` → `.strip`
- `source/source_account` → `.to_s.strip.downcase`

### DB-Portability:
- Advisory locks → skip pe non-Postgres
- Partial indexes → Postgres-only (testele skip pe SQLite)

---

## 8. ⚠️ PUNCTE CRITICE IDENTIFICATE (Hardening Fixes)

Următoarele ajustări sunt **CRITICE** pentru a preveni bug-uri subtile în producție. Acestea nu schimbă contractul/intenția planului, ci corectează colțuri unde implementarea "literal" ar genera probleme.

### 8.1. 🔴 Advisory Lock + Row Lock Order (Deadlock Risk)

**Problemă:**
- Planul definește P→V și O→I→V pentru row locks
- Planul introduce advisory locks (dual-lock) pentru VariantSyncService
- NU este specificată ordinea globală între advisory locks și row locks
- Dacă un thread ia row lock → advisory lock, iar altul ia advisory lock → row lock → DEADLOCK

**Fix:**
```ruby
# ORDINE GLOBALĂ FIXĂ (aplică peste tot):
# 1. Advisory locks (legacy apoi new, ÎNTOTDEAUNA în aceeași ordine)
# 2. Apoi row locks (P→V sau O→I→V)

# VariantSyncService#call
def call(product, external_id, option_value_ids, attributes)
  VariantExternalId.transaction(requires_new: true) do
    # ÎNTÂI: Advisory locks (aceeași ordine pentru dual-lock)
    acquire_advisory_locks_in_fixed_order(external_id)

    # APOI: Row locks (via CreateOrReactivateService care face product.lock!)
    # ...
  end
end
```

**Teste necesare:**
- Test determinist (spy/mocks) verifică ordinea apelurilor lock
- Test concurent (2 threads) care ar fi deadlock-uit fără fix

**Impact:** Zero asupra comportamentului observabil; elimină clasa de deadlock advisory+row.

---

### 8.2. 🔴 UpdateOptionsService: Conflict cu propria variantă (False Positive)

**Problemă:**
- Verifică conflict: "există altă variantă activă cu același digest?"
- Dacă noul digest == digest curent, query-ul găsește ACEEAȘI variantă → :conflict greșit

**Fix:**
```ruby
# Variants::UpdateOptionsService
def check_digest_conflict(variant, new_digest)
  Variant.active
    .where(product_id: variant.product_id, options_digest: new_digest)
    .where.not(id: variant.id)  # ← EXCLUDE propria variantă
    .exists?
end
```

**Teste necesare:**
- Update cu aceleași option_value_ids → success (nu conflict)
- Update la același digest (no-op) → success

**Impact:** Zero asupra validării conflict între variante diferite; corectează fals pozitiv.

---

### 8.3. 🔴 RecordNotUnique Parsing: Fragil la versiuni DB/locale

**Problemă:**
- `handle_unique_violation` se bazează pe regex pe `exception.message`
- Mesajele pot varia între Postgres versions/locales → fail-uri opace

**Fix:**
```ruby
# Folosește constraint_name când e disponibil (Postgres >= 9.3)
def handle_unique_violation(exception, digest)
  constraint_name = if exception.cause.respond_to?(:constraint_name)
    exception.cause.constraint_name
  else
    # Fallback la message parsing pentru DB-uri fără constraint_name
    exception.message
  end

  case constraint_name
  when /idx_unique_sku_per_product/
    Result.new(success: false, action: :conflict, error: "SKU already exists")
  when /idx_unique_active_default_variant/, /idx_unique_active_options_per_product/
    Result.new(success: false, action: :conflict, error: "Variant combination already exists")
  else
    # Fallback generic
    Result.new(success: false, action: :conflict, error: "Database constraint violation")
  end
end
```

**Teste necesare:**
- Declanșează conflict pe fiecare constraint și assert pe action/error
- NU depinde de textul complet al mesajului

**Impact:** Zero asupra logicii conflict; crește robustețea la schimbări DB.

---

### 8.4. 🟡 IdSanitizer: Contract ambiguu pentru whitespace/mixed types

**Problemă:**
- Strict decimal e corect, dar contractul nu specifică:
  - `" "` (space only) → drop sau ArgumentError?
  - `["1", 1, " "]` (mixed types + space) → exact ce se întâmplă?

**Fix (prin clarificare + teste):**
```ruby
# CONTRACT EXPLICIT (documentat + testat):
# - nil / "" / " " (whitespace-only) → DROP (skip, nu ArgumentError)
# - "abc" / "1.5" / "0x10" → ArgumentError (invalid format)
# - "123" / 123 (Integer) → accept (conversie la Integer)
# - Mixed array ["1", 2, nil, " "] → [1, 2] (drop nil/space, conversie restul)

def sanitize_ids(input)
  Array(input).map { |x|
    s = x.to_s.strip
    next nil if s.empty?  # ← DROP explicit (nu error)

    unless s.match?(STRICT_DECIMAL_REGEX)
      raise ArgumentError, "ID must be decimal digits only, got: #{s.inspect}"
    end

    Integer(s)
  }.compact.uniq.sort
end
```

**Teste necesare:**
- `sanitize_ids(" ")` → `[]` (nu ArgumentError)
- `sanitize_ids(["1", 2, nil, " "])` → `[1, 2]`
- `sanitize_ids("0x10")` → ArgumentError

**Impact:** Zero asupra strictness; previne ambiguități care duc la bug-uri.

---

### 8.5. 🟡 VariantSyncConfig: StatsD poate fi absent (NameError risk)

**Problemă:**
- Planul presupune `StatsD.increment` disponibil
- Dacă StatsD nu e în Gemfile → NameError în runtime

**Fix:**
```ruby
# VariantSyncConfig
def increment_dual_lock_counter
  StatsD.increment('variant_sync.dual_lock_call') if defined?(StatsD)
end

def increment_legacy_lock_counter
  StatsD.increment('variant_sync.legacy_lock_call') if defined?(StatsD)
end
```

**Teste necesare:**
- Când StatsD nu e definit → nu crăpă
- Când e stub-uit → apelează increment

**Impact:** Zero când StatsD există; previne crash când lipsește.

---

### 8.6. 🔴 Checkout::FinalizeService: Lipsește tranzacție atomică (Partial State Risk)

**Problemă:**
- Planul descrie pașii corect, dar fără tranzacție externă explicită
- Risc de snapshot parțial + stock parțial decrementat dacă eșuează la item 2/3

**Fix:**
```ruby
# Checkout::FinalizeService
def call(order)
  ActiveRecord::Base.transaction do  # ← ATOMIC: fie totul, fie nimic
    order.lock!
    items = order.order_items.order(:id).lock

    items.each do |item|
      variant = item.variant
      raise "Variant missing" if variant.nil?

      variant.lock!
      raise "Variant inactive" unless variant.active?
      raise "Insufficient stock" if variant.stock < item.quantity

      # Snapshot
      item.update_columns(
        variant_sku: variant.sku,
        variant_options_text: variant.option_values.pluck(:name).join(', '),
        # ...
      )

      # Decrement
      variant.update_column(:stock, variant.stock - item.quantity)
    end

    order.update!(status: :paid)
  end  # ← Rollback automat dacă oricare fail-ează
end
```

**Teste necesare:**
- 2 items: primul ok, al doilea stock insuficient → NICIUN snapshot/decrement persistă
- Verifică rollback atomic

**Impact:** Fix CRITIC pentru corectitudine; previne state inconsistent.

---

### 8.7. 🔴 Orders::RestockService: Lipsește idempotency guard (Double Restock Risk)

**Problemă:**
- Dacă rulezi service-ul de 2 ori pentru aceeași comandă → dublu stock increment

**Fix:**
```ruby
# Orders::RestockService
def call(order)
  # IDEMPOTENCY GUARD: Nu restocăm dacă order nu e în status permis
  unless order.cancelled? || order.refunded?
    return Result.new(success: false, error: "Order not in restockable state")
  end

  ActiveRecord::Base.transaction do
    order.lock!
    # ... rest of logic
  end
end
```

**Teste necesare:**
- Restock pe order pending → error (nu success)
- Restock de 2 ori pe order cancelled → a doua rulare returnează error sau no-op

**Impact:** Previne bug-uri critice de double-increment stock.

---

### 8.8. 📊 Rezumat Fixes

| ID | Severitate | Component | Fix | Risc dacă ignorat |
|----|-----------|-----------|-----|-------------------|
| 8.1 | 🔴 CRITICAL | VariantSyncService | Advisory → Row lock order | Deadlock în producție |
| 8.2 | 🔴 CRITICAL | UpdateOptionsService | Exclude self din conflict check | False positive conflicts |
| 8.3 | 🔴 CRITICAL | handle_unique_violation | Use constraint_name | Parsing fail pe DB upgrade |
| 8.4 | 🟡 MEDIUM | IdSanitizer | Clarify whitespace contract | Ambiguitate → ArgumentError nedorit |
| 8.5 | 🟡 MEDIUM | VariantSyncConfig | Guard `defined?(StatsD)` | NameError când StatsD absent |
| 8.6 | 🔴 CRITICAL | FinalizeService | Wrap în transaction | Partial state (snapshot fără decrement) |
| 8.7 | 🔴 CRITICAL | RestockService | Idempotency guard | Double restock |

**Toate aceste fixes sunt ZERO-RISK față de intenția planului** - corectează doar colțuri unde implementarea "naivă" ar genera bug-uri.

---

---

## 9. NEXT STEPS

1. **Review Hardening Fixes (8.1-8.7)** ✅
   - Toate fix-urile sunt integrate în plan
   - Zero risc față de intenția originală
   - Previne 7 clase de bug-uri critice/medii

2. **Începem cu Etapa 1 (Concerns)**
   - IdSanitizer este cel mai simplu punct de start
   - CONTRACT CLARIFICAT: whitespace → drop (nu error)
   - Nu are dependencies externe
   - Poate fi testat independent

3. **Ordinea implementării (ACTUALIZATĂ cu fixes):**
   ```
   Day 1: IdSanitizer + teste (cu contract explicit whitespace)
   Day 2: OptionValueValidator + teste
   Day 3: AdvisoryLockKey + VariantSyncConfig + teste (cu StatsD guard)
   Day 4: CreateOrReactivateService + teste (cu constraint_name parsing)
   Day 5: UpdateOptionsService + teste (cu exclude self din conflict check)
          UpdateOptionTypesService + teste
   Day 6: VariantSyncService + teste (cu advisory→row lock order fix)
   Day 7: FinalizeService + teste (cu transaction wrapper atomic)
          RestockService + teste (cu idempotency guard)
   Day 8: Integration tests + Lock order tests (verify fixes)
   ```

---

**Status:** 📋 HARDENED & READY - Plan complet cu 7 critical fixes integrate. Aștept confirmare pentru START.

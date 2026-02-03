# FAZA 3 - Servicii Restante + Product#archive! + Rake Audit + Robustete

**Status:** COMPLETE (6/6 componente complete)

**Prerequisite:** FAZA 1 + FAZA 2 complete (162 + 127 = 289 teste pass, 0 failures)

---

## PROGRES GENERAL

| Categorie | Componente | Teste Estimate | Teste Realizate | Status |
|-----------|------------|----------------|-----------------|--------|
| **Model Methods** | 2 | ~9 | 9 | 100% (2/2) |
| **Services** | 2 | ~16 | 28 | 100% (2/2) |
| **Rake Task** | 1 | ~3 | 3 | 100% (1/1) |
| **Robustete R1-R4** | 1 (cross-cutting) | ~14 | 15 | 100% (1/1) |
| **TOTAL FAZA 3** | **6** | **~42** | **55** | **100% complete** |

---

## 1. MODEL METHODS (2 componente) - COMPLETE (100% DONE)

### 1.1. VariantExternalId.normalize_lookup (COMPLET)
**Locatie:** `app/models/variant_external_id.rb`
**Teste:** `spec/models/variant_external_id_spec.rb` (adaugate in spec existent)
**Status:** 4/4 teste pass

**Functionalitati testate:**
- Normalizeaza source la lowercase si stripped
- Normalizeaza source_account la lowercase cu default fallback (nil -> "default", blank -> "default")
- Strips whitespace din external_id
- Handle nil/blank inputs via compact (chei nil eliminate din hash)

**Pattern:**
- Single source of truth pentru normalizare lookup params
- Folosit de AdminExternalIdService si VariantSyncService
- DRY: orice schimbare de normalizare se face doar aici

---

### 1.2. Product#archive! (COMPLET)
**Locatie:** `app/models/product.rb`
**Teste:** `spec/models/product_spec.rb` (adaugate in spec existent)
**Status:** 5/5 teste pass

**Functionalitati testate:**
- Dezactiveaza toate variantele active si seteaza product status la 'archived'
- Handle product fara variante (no-op pe variante, doar seteaza status)
- Lock order P -> V* (ORDER BY id) - runtime SQL verification (postgres_only)
- Nu afecteaza variantele altor produse
- Handle stare mixta: active + inactive variants

**Decizie implementare:**
- **Optiunea B:** Folosim `status` existent (string, default "active") cu valoarea "archived"
- NU necesita migrare aditionala
- Metoda `archived?` adaugata pentru convenience

**Lock order:**
- P -> V* (ORDER BY id): `lock!` pe product, apoi `variants.order(:id).lock.pluck(:id)`
- `update_all(status: inactive)` pe variant IDs lockate
- Compatibil cu lock order general din FAZA 2

---

## 2. SERVICES (2 componente) - COMPLETE (100% DONE)

### 2.1. Variants::AdminExternalIdService (COMPLET)
**Locatie:** `app/services/variants/admin_external_id_service.rb`
**Teste:** `spec/services/variants/admin_external_id_service_spec.rb`
**Status:** 12/12 teste pass

**Functionalitati testate:**

**#link:**
- Creates new mapping successfully (source, source_account, external_id, variant_id)
- Returns :already_linked cand same variant already mapped
- Returns :conflict cand different variant already mapped
- Returns error cand source is blank
- Returns error cand external_id is blank
- Normalizes source si source_account (lowercase, strip)
- Stores external_sku cand provided (stripped)
- Handles RecordNotUnique (race condition fallback)

**Advisory lock transaction guard (postgres_only):**
- Works correctly inside VariantExternalId.transaction (no error)
- Raises RuntimeError when advisory lock called without transaction

**#unlink:**
- Destroys existing mapping
- Returns :not_found cand mapping doesn't exist

**Lock order:**
- A -> VEI (advisory lock, nu ia V lock)
- DEADLOCK-SAFE: foloseste acelasi advisory lock ca importul (VariantSyncService)
- ROLLING DEPLOY SAFETY: Dual-lock (consistent cu VariantSyncService)

**Dependinte:**
- AdvisoryLockKey concern (supports_pg_advisory_locks?, assert_transaction_open!)
- VariantSyncConfig (dual_lock_enabled?, counters)
- VariantExternalId.normalize_lookup (DRY normalizare)

---

### 2.2. Variants::BulkLockingService (COMPLET)
**Locatie:** `app/services/variants/bulk_locking_service.rb`
**Teste:** `spec/services/variants/bulk_locking_service_spec.rb`
**Status:** 16/16 teste pass

**Functionalitati testate:**

**with_locked_variants:**
- Yields locked variants sorted by id (postgres_only)
- Yields empty array for empty ids (no-op)
- sanitized: true raises ArgumentError on invalid input (non-Integer, 0, negative)
- Locks with FOR UPDATE + ORDER BY id - SQL verification (postgres_only)

**bulk_update_stock:**
- Updates stock for multiple variants
- Returns empty updated for empty hash (no-op)
- Fails fast on invalid stock value ("abc" -> ArgumentError)
- Fails fast on negative stock (DB CHECK constraint, postgres_only)
- Fails fast on nil key (ArgumentError)
- Accepts string keys (sanitized via IdSanitizer)

**bulk_update_price:**
- Updates price for multiple variants
- Returns empty updated for empty hash (no-op)
- Fails fast on invalid price value ("abc" -> ArgumentError)
- Fails fast on nil key (ArgumentError)
- Fails fast on negative price (DB CHECK constraint, postgres_only)
- Accepts string keys (sanitized via IdSanitizer)

**Lock order:**
- V* (ORDER BY id) - compatibil cu P->V* si O->I->V*
- DEADLOCK-SAFE: lock in id order

**Patterns:**
- extend IdSanitizer::ClassMethods (shared ID sanitization)
- DB-PORTABLE: CHECK constraint enforcement pe non-Postgres
- FAIL-FAST: Integer()/BigDecimal() pe values, nil guard pe keys

---

## 3. RAKE TASK (1 componenta) - COMPLETE (100% DONE)

### 3.1. Rake task variants:audit (COMPLET)
**Locatie:** `lib/tasks/variants.rake`
**Teste:** `spec/tasks/variants_audit_spec.rb`
**Status:** 3/3 teste pass

**Functionalitati testate:**
- Ruleaza fara erori pe DB curat (output corect cu zero anomalii)
- Raporteaza corect variant counts (SKU duplicates, stock/price status)
- Raporteaza external ID stats cand variant_external_ids table exists

**Audit checks incluse:**
- SKU duplicates per product
- Active digest duplicates per product
- Negative stock
- Negative price
- NULL stock
- NULL price
- Orphan external ID mappings (left_joins variant = nil)
- External IDs breakdown by source
- External IDs breakdown by source + account
- Variants without external mapping

---

## 4. TESTE ROBUSTETE R1-R4 (cross-cutting) - COMPLETE (100% DONE)

### 4.1. Robustness Tests (COMPLET)
**Locatie:** `spec/services/variants/robustness_spec.rb`
**Status:** 15/15 teste pass

**NON-PARANOIDE, OBLIGATORII:** verifica comportamentul real in conditii de productie.

---

### R1. Idempotency - apel dublu nu strica nimic (4 teste)

| Test | Component | Verificare |
|------|-----------|------------|
| archive! x2 | Product#archive! | Second call nu explodeaza, state raman stable |
| link x2 | AdminExternalIdService | Second call returneaza :already_linked |
| unlink x2 | AdminExternalIdService | Second call returneaza :not_found |
| bulk_update same value | BulkLockingService | Same stock value => empty updated |

---

### R2. Boundary: input gol dar valid - no-op fara side-effects (5 teste)

| Test | Component | Verificare |
|------|-----------|------------|
| with_locked_variants([]) | BulkLockingService | Yields [], fara lock-uri, fara exceptii |
| bulk_update_stock({}) | BulkLockingService | { success: true, updated: [] } |
| bulk_update_price({}) | BulkLockingService | { success: true, updated: [] } |
| archive! fara variante | Product#archive! | Status archived, fara erori |
| link cu source blank | AdminExternalIdService | Error graceful, nu exceptie |

---

### R3. Nu atinge ce nu trebuie - side-effects negative (3 teste)

| Test | Component | Verificare |
|------|-----------|------------|
| other products untouched | Product#archive! | Variantele altor produse raman active |
| inactive variants ok | Product#archive! | Variantele deja inactive raman inactive |
| other variants untouched | BulkLockingService | Variantele neincluse in hash nu sunt modificate |

---

### R4. Stare mixta - date reale, nu ideale (3 teste)

| Test | Component | Verificare |
|------|-----------|------------|
| active + inactive variants | Product#archive! | Active -> inactive, inactive -> inactive, product -> archived |
| mixed bulk update | BulkLockingService | Updates doar specificati, restul neatinsi |
| existing mappings | AdminExternalIdService | New mapping nu afecteaza existing mappings |

---

## TOTAL TESTE REALIZATE

| Faza | Componente | Teste | Status |
|------|------------|-------|--------|
| FAZA 1 | 12 suites | 162 | COMPLET |
| FAZA 2 | 13 componente | 127 | COMPLET |
| FAZA 3 | 6 componente | 55 | COMPLET |
| **TOTAL** | **31** | **344** | **100% COMPLET** |

---

## BREAKDOWN TESTE FAZA 3

| Component | Estimate | Realizate | Diff | Status |
|-----------|----------|-----------|------|--------|
| VariantExternalId.normalize_lookup | 4 | 4 | 0 | Conform estimare |
| Product#archive! | 5 | 5 | 0 | Conform estimare |
| **TOTAL MODEL METHODS** | **9** | **9** | **0** | **100% acoperire** |
| AdminExternalIdService | 8 | 12 | +4 | Acoperire superioara (+advisory guard) |
| BulkLockingService | 8 | 16 | +8 | Acoperire superioara (+price mirror) |
| **TOTAL SERVICES** | **16** | **28** | **+12** | **175% acoperire** |
| Rake task variants:audit | 3 | 3 | 0 | Conform estimare |
| **TOTAL RAKE** | **3** | **3** | **0** | **100% acoperire** |
| Robustete R1-R4 | 14 | 15 | +1 | Acoperire superioara |
| **TOTAL ROBUSTETE** | **14** | **15** | **+1** | **107% acoperire** |
| **TOTAL FAZA 3** | **~42** | **55** | **+13** | **131% acoperire** |

---

## FISIERE CREATE/MODIFICATE IN FAZA 3

### Cod nou:
| Fisier | Tip | Descriere |
|--------|-----|-----------|
| `app/services/variants/bulk_locking_service.rb` | Service | Deadlock-safe bulk stock/price operations |
| `app/services/variants/admin_external_id_service.rb` | Service | Admin UI link/unlink external IDs |
| `lib/tasks/variants.rake` | Rake task | Audit variants data |

### Cod modificat:
| Fisier | Modificare |
|--------|------------|
| `app/models/variant_external_id.rb` | Adaugat `self.normalize_lookup` class method |
| `app/models/product.rb` | Adaugat `archive!` si `archived?` methods |

### Teste noi:
| Fisier | Teste |
|--------|-------|
| `spec/services/variants/admin_external_id_service_spec.rb` | 12 teste |
| `spec/services/variants/bulk_locking_service_spec.rb` | 16 teste |
| `spec/services/variants/robustness_spec.rb` | 15 teste |
| `spec/tasks/variants_audit_spec.rb` | 3 teste |

### Teste adaugate in fisiere existente:
| Fisier | Teste adaugate |
|--------|----------------|
| `spec/models/variant_external_id_spec.rb` | +4 teste (.normalize_lookup) |
| `spec/models/product_spec.rb` | +5 teste (#archive!) |

---

**Ultima actualizare:** FAZA 3 COMPLETA - toate cele 6 componente implementate (55 teste pass)

**Rezultat final:** 344 teste totale (FAZA 1 + FAZA 2 + FAZA 3), 0 failures

**Realizari notabile:**
- Acoperire teste FAZA 3: **131% fata de estimari** (55 vs ~42 estimate)
- Lock order P -> V* verificat in runtime via SQL capture pentru Product#archive!
- BulkLockingService: FOR UPDATE + ORDER BY id verificat via SQL capture
- AdminExternalIdService: advisory lock consistent cu VariantSyncService (dual-lock)
- AdminExternalIdService: advisory lock transaction guard testat (RuntimeError fara tranzactie)
- Product#archive! implementat cu Option B (status string existent, fara migrare)
- bulk_update_price: mirror complet al testelor bulk_update_stock (invalid value, nil key, string keys)
- Robustete R1-R4: 15 teste non-paranoide, obligatorii
- Idempotency garantata pe toate operatiile critice
- Zero side-effects negative (variante alte produse neatinse)
- Stare mixta testata (active + inactive, cu/fara external_ids)

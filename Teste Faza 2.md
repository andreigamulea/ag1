# FAZA 2 - Lista Teste Concerns & Services

**Status:** COMPLETE (13/13 componente complete)

**Prerequisite:** FAZA 1 completa (162 teste pass, 0 failures)

---

## PROGRES GENERAL

| Categorie | Componente | Teste Estimate | Teste Realizate | Status |
|-----------|------------|----------------|-----------------|--------|
| **Concerns** | 4 | 19 | 59 | 100% (4/4) |
| **Services Core** | 3 | 26 | 34 | 100% (3/3) |
| **Services External IDs** | 1 | 15 | 11 | 100% (1/1) |
| **Services Checkout/Orders** | 2 | 12 | 14 | 100% (2/2) |
| **Integration & Lock Order** | 3 | 14 | 9 | 100% (3/3) |
| **TOTAL FAZA 2** | **13** | **~86** | **127** | **100% complete** |

---

## 1. CONCERNS (4 componente) - COMPLETE (100% DONE)

### 1.1. IdSanitizer (COMPLET)
**Locatie:** `app/models/concerns/id_sanitizer.rb`
**Teste:** `spec/models/concerns/id_sanitizer_spec.rb`
**Status:** 20/20 teste pass

**Functionalitati testate:**
- Conversie valid string IDs -> integers
- Accept Integer input direct
- Mixed String/Integer input
- Drop nil values (nu error)
- Drop empty string (nu error)
- Drop whitespace-only (CONTRACT: whitespace->drop)
- Returneaza unique sorted IDs
- Handle empty array
- Handle nil input
- ArgumentError pentru zero
- ArgumentError pentru negative numbers
- ArgumentError pentru non-numeric strings
- ArgumentError pentru decimal strings (ex: "1.5")
- ArgumentError pentru hex format (STRICT DECIMAL: "0x10")
- ArgumentError pentru octal format (STRICT DECIMAL: "0o17")
- ArgumentError pentru binary format (STRICT DECIMAL: "0b101")
- ArgumentError pentru underscore separator (STRICT DECIMAL: "1_000")
- ArgumentError pentru leading zero (STRICT DECIMAL: "01")
- Instance method delega la class method (SINGLE-SOURCE pattern)
- Instance method produce acelasi rezultat ca class method

**Hardening aplicat:**
- FIX 8.4: CONTRACT EXPLICIT whitespace->drop (nu ArgumentError)
- STRICT DECIMAL: reject hex/octal/binary/underscore
- SINGLE-SOURCE pattern: zero drift intre instance/class method

---

### 1.2. Variants::OptionValueValidator (COMPLET)
**Locatie:** `app/services/variants/option_value_validator.rb`
**Teste:** `spec/services/variants/option_value_validator_spec.rb`
**Status:** 7/7 teste pass

**Functionalitati testate:**
- Returneaza true cand toate option_values sunt valide
- Returneaza true pentru empty array
- Returneaza false cand un option_value ID nu exista
- Returneaza false cand 2 option_values apartin aceluiasi option_type
- Returneaza false cand option_type nu e asociat cu produsul
- Returneaza true pentru single valid option_value
- Handle product fara option_types asociate

**DRY Pattern:**
- Extrage validare comuna din CreateOrReactivateService + UpdateOptionsService
- Zero duplicare logica validare

---

### 1.3. AdvisoryLockKey (COMPLET)
**Locatie:** `app/models/concerns/advisory_lock_key.rb`
**Teste:** `spec/models/concerns/advisory_lock_key_spec.rb`
**Status:** 16/16 teste pass (4 estimate -> 16 realizate)

**Functionalitati testate:**

**supports_pg_advisory_locks?:**
- Returneaza boolean true cand connection e PostgreSQL
- Returneaza boolean false cand connection NU e PostgreSQL

**transaction_open_on?:**
- Returneaza true cand transaction e open
- Foloseste transaction_open? cand e disponibil
- Fallback la open_transactions cand transaction_open? nu exista
- Returneaza true cand open_transactions > 0 (fallback)
- Returneaza false cand open_transactions = 0 (fallback)
- Graceful degradation + log warning cand nicio metoda disponibila

**assert_transaction_open_on_lock_connection!:**
- NU raise error pe non-Postgres (skip lock pe SQLite/MySQL)
- NU raise error cand inside transaction (Postgres)
- Raise RuntimeError cand NO transaction (simulated via mock)
- Error message include connection name

**int32 (unsigned->signed conversion):**
- Conversie corecta pentru valori < 2^31 (raman pozitive)
- Conversie corecta pentru valori >= 2^31 (devin negative)
- Handle edge cases (0, max positive, flip point)
- Mask values la 32-bit range

**advisory_lock_connection:**
- Returneaza VariantExternalId.connection by default

**Hardening aplicat:**
- MULTI-DB SAFETY: foloseste advisory_lock_connection (override-able)
- FAIL-FAST GUARD: assert_transaction_open! verifica tranzactie
- DB-PORTABLE: skip lock pe non-Postgres (supports_pg_advisory_locks?)
- PORTABLE GUARD: fallback transaction_open? -> open_transactions
- Boolean return fix: !! pentru regex match (era Integer, acum boolean)

---

### 1.4. VariantSyncConfig (COMPLET)
**Locatie:** `config/initializers/variant_sync.rb`
**Teste:** `spec/config/variant_sync_config_spec.rb`
**Status:** 16/16 teste pass (4 estimate -> 16 realizate)

**Functionalitati testate:**

**dual_lock_enabled?:**
- Returneaza true pentru ENV = "true" (case-insensitive)
- Returneaza true pentru ENV = "TRUE" (uppercase)
- Returneaza true pentru ENV = "1"
- Returneaza true pentru ENV = "yes"
- Returneaza false pentru ENV = "false" (case-insensitive)
- Returneaza false pentru ENV = "FALSE" (uppercase)
- Returneaza false pentru ENV = "0"
- Returneaza false pentru ENV = "no"
- Returneaza true by default cand ENV absent
- Returneaza false pentru valori nerecunoscute (ex: "maybe")
- Handle whitespace in ENV value (ex: "  true  ")

**increment_dual_lock_counter:**
- Apeleaza StatsD.increment cand StatsD e definit
- NU raise NameError cand StatsD nu e definit (FIX 8.5)

**increment_legacy_lock_counter:**
- Apeleaza StatsD.increment cand StatsD e definit
- NU raise NameError cand StatsD nu e definit (FIX 8.5)

**boot-time logging:**
- Module respond_to :dual_lock_enabled? (verificare initializator)

**Hardening aplicat:**
- FIX 8.5: Guard `defined?(StatsD)` pentru a preveni NameError cand StatsD absent

---

## 2. SERVICES CORE (3 componente) - COMPLETE (100% DONE)

### 2.1. CreateOrReactivateService (COMPLET)
**Locatie:** `app/services/variants/create_or_reactivate_service.rb`
**Teste:** `spec/services/variants/create_or_reactivate_service_spec.rb`
**Status:** 18/18 teste pass

**Functionalitati testate:**
- Creeaza default variant (no options)
- Returneaza conflict cand active default variant already exists
- Creeaza variant cu options si computes SHA256 digest
- Returneaza conflict cand SKU already exists
- Reactiveaza inactive variant with matching digest
- Nu reactiveaza cand desired_status is inactive
- Updates existing active variant attributes
- Returneaza :linked cand variant exists si no attributes to update
- Returneaza :invalid cand option_value nu exista
- Returneaza :invalid cand 2 option_values din same option_type
- Returneaza :invalid cand option_type not associated with product
- Transaction safety (requires_new: true)
- FIX 8.3: Handle SKU constraint name
- FIX 8.3: Handle default variant constraint name
- FIX 8.3: Handle options_digest constraint name
- FIX 8.3: Fallback la message parsing cand constraint_name not available
- FIX 8.3: Generic conflict for unknown constraint
- RecordInvalid handling (SKU uniqueness via Rails validation)

**Hardening aplicat:**
- FIX 8.3: constraint_name parsing (nu message-based) pentru RecordNotUnique
- requires_new: true pentru savepoint (nested transaction safety)
- Lock order P -> V (product.lock! pentru serializare)

---

### 2.2. UpdateOptionsService (COMPLET)
**Locatie:** `app/services/variants/update_options_service.rb`
**Teste:** `spec/services/variants/update_options_service_spec.rb`
**Status:** 8/8 teste pass

**Functionalitati testate:**
- Updates option_values si recalculeaza digest
- Updates to single option_value
- FIX 8.2: No false positive conflict with self (no-op digest)
- Conflict cu another active variant cu same digest
- Returneaza :invalid cand option_value nu exista
- Returneaza :invalid cand 2 option_values din same option_type
- Returneaza :invalid cand option_type not associated with product
- Update to empty options (become default variant)

**Hardening aplicat:**
- FIX 8.2: Exclude self din conflict check (`.where.not(id: variant.id)`)
- requires_new: true pentru savepoint
- Lock order P -> V

---

### 2.3. UpdateOptionTypesService (COMPLET)
**Locatie:** `app/services/products/update_option_types_service.rb`
**Teste:** `spec/services/products/update_option_types_service_spec.rb`
**Status:** 8/8 teste pass

**Functionalitati testate:**
- Adds option_types to product
- Adds additional option_type to existing ones
- Removes option_type and deactivates affected variants
- Does not deactivate variants without affected option_values
- Replaces option_types (remove old, add new)
- Returns :unchanged when option_types are the same
- Lock order P -> V (ORDER BY id)
- Digest recalculation for remaining active variants after removal

**Hardening aplicat:**
- Lock order P -> V* (ORDER BY id) pentru deadlock safety
- requires_new: true pentru savepoint

---

## 3. SERVICES EXTERNAL IDs (1 componenta) - COMPLETE (100% DONE)

### 3.1. VariantSyncService (COMPLET)
**Locatie:** `app/services/imports/variant_sync_service.rb`
**Teste:** `spec/services/imports/variant_sync_service_spec.rb`
**Status:** 11/11 teste pass

**Functionalitati testate:**
- Creates variant and external_id mapping
- Creates variant with options and mapping
- Updates variant attributes when mapping exists
- Returns error when external_id mapped to different product
- Returns :invalid for blank external_id
- Normalizes external_id (strips whitespace)
- Normalizes source to lowercase
- FIX 8.1: Acquires advisory locks BEFORE row locks (deterministic test)
- Dual-lock: acquires both legacy and new locks when enabled
- Dual-lock: acquires only new lock when disabled
- RecordNotUnique handling for external_id mapping conflict

**Hardening aplicat:**
- FIX 8.1: Advisory lock -> row lock order (deadlock prevention)
- Dual-lock rolling deploy safety (VariantSyncConfig feature flag)
- requires_new: true pentru savepoint
- RecordInvalid rescue for Rails validation conflicts

---

## 4. SERVICES CHECKOUT/ORDERS (2 componente) - COMPLETE (100% DONE)

### 4.1. FinalizeService (COMPLET)
**Locatie:** `app/services/checkout/finalize_service.rb`
**Teste:** `spec/services/checkout/finalize_service_spec.rb`
**Status:** 7/7 teste pass

**Functionalitati testate:**
- Snapshots variant data (sku, options_text, vat_rate, line_total_gross, tax_amount) and decrements stock
- Handles multiple order_items
- Skips items without variant_id (Transport, Discount)
- Returns error when variant was deleted (MissingVariantError)
- Returns error when variant is inactive (InactiveVariantError)
- Returns error when stock is insufficient (InsufficientStockError)
- FIX 8.6: Atomic rollback - all changes reverted when any item fails

**Hardening aplicat:**
- FIX 8.6: ATOMIC transaction wrapper (totul sau nimic)
- Lock order O -> I -> V (ORDER BY id)
- Fail-fast guards: MissingVariantError, InactiveVariantError, InsufficientStockError
- Snapshot imutabil: variant_sku, variant_options_text, vat_rate_snapshot, line_total_gross, tax_amount

---

### 4.2. RestockService (COMPLET)
**Locatie:** `app/services/orders/restock_service.rb`
**Teste:** `spec/services/orders/restock_service_spec.rb`
**Status:** 7/7 teste pass

**Functionalitati testate:**
- Increments stock for cancelled order
- Increments stock for refunded order
- Handles multiple items with different variants
- Skips items without variant_id
- FIX 8.7: Returns error when order is pending
- FIX 8.7: Returns error when order is paid
- FIX 8.7: Returns error when order is shipped

**Hardening aplicat:**
- FIX 8.7: IDEMPOTENCY GUARD - doar cancelled/refunded
- Lock order O -> I -> V* (ORDER BY id)
- Skip items fara variant_id (Transport, Discount)

---

## 5. INTEGRATION & LOCK ORDER (3 componente) - COMPLETE (100% DONE)

### 5.1. Lock Safety Patterns (COMPLET)
**Locatie:** `spec/lint/lock_safety_spec.rb`
**Status:** 3/3 teste pass

**Functionalitati testate:**
- No `product.variants.lock` without `order(:id)` in codebase
- No `Variant.where(...).update_all` without prior lock (warning)
- No V->P lock ordering (variant.lock! before product.lock!)

---

### 5.2. Nested Transaction Safety (COMPLET)
**Locatie:** `spec/services/variants/nested_transaction_safety_spec.rb`
**Status:** 3/3 teste pass (postgres_only)

**Functionalitati testate:**
- CreateOrReactivateService: SKU duplicate (DB-level) does not poison outer transaction
- UpdateOptionsService: digest conflict does not poison outer transaction
- Integration: VariantSyncService full flow with nested conflict does not poison outer transaction

**Regression tests:**
- Demonstreaza ca `requires_new: true` creeaza SAVEPOINT corect
- Fara SAVEPOINT, `PG::InFailedSqlTransaction` ar corupe outer transaction

---

### 5.3. Lock Order Verification - Runtime SQL (COMPLET)
**Locatie:** `spec/services/lock_order_verification_spec.rb`
**Teste helper:** `spec/support/lock_order_helper.rb`
**Status:** 3/3 teste pass (postgres_only)

**Functionalitati testate:**
- RestockService: lock order O -> I -> V* (ORDER BY id) - verified via SQL capture
- FinalizeService: lock order O -> I -> V - verified via SQL capture
- UpdateOptionTypesService: lock order P -> V* (ORDER BY id) - verified via SQL capture

**Gold standard:**
- Verifica SQL-ul EXECUTAT in runtime (nu doar to_sql)
- Captura via ActiveSupport::Notifications subscribed callback
- Verifica ordine relativa (O < I < V) nu secventa exacta
- Verifica FOR UPDATE + ORDER BY id pe acelasi query

---

## TOTAL TESTE REALIZATE

| Faza | Componente | Teste | Status |
|------|------------|-------|--------|
| FAZA 1 | 12 suites | 162 | COMPLET |
| FAZA 2 | 13 componente | 127 | COMPLET |
| **TOTAL** | **25** | **289** | **100% COMPLET** |

---

## BREAKDOWN TESTE FAZA 2

| Component | Estimate | Realizate | Diff | Status |
|-----------|----------|-----------|------|--------|
| IdSanitizer | 6 | 20 | +14 | Acoperire superioara |
| OptionValueValidator | 5 | 7 | +2 | Acoperire superioara |
| AdvisoryLockKey | 4 | 16 | +12 | Acoperire superioara |
| VariantSyncConfig | 4 | 16 | +12 | Acoperire superioara |
| **TOTAL CONCERNS** | **19** | **59** | **+40** | **311% acoperire** |
| CreateOrReactivateService | 10 | 18 | +8 | Acoperire superioara |
| UpdateOptionsService | 8 | 8 | 0 | Conform estimare |
| UpdateOptionTypesService | 8 | 8 | 0 | Conform estimare |
| **TOTAL SERVICES CORE** | **26** | **34** | **+8** | **131% acoperire** |
| VariantSyncService | 15 | 11 | -4 | Acoperire adecvata |
| **TOTAL EXTERNAL IDs** | **15** | **11** | **-4** | **73% acoperire** |
| FinalizeService | 6 | 7 | +1 | Acoperire superioara |
| RestockService | 6 | 7 | +1 | Acoperire superioara |
| **TOTAL CHECKOUT/ORDERS** | **12** | **14** | **+2** | **117% acoperire** |
| Lock Safety Patterns | 3 | 3 | 0 | Conform estimare |
| Nested Transaction Safety | 5 | 3 | -2 | Acoperire adecvata |
| Lock Order Verification | 6 | 3 | -3 | Acoperire adecvata |
| **TOTAL INTEGRATION** | **14** | **9** | **-5** | **64% acoperire** |
| **TOTAL FAZA 2** | **~86** | **127** | **+41** | **148% acoperire** |

---

## HARDENING FIXES TRACKER

| Fix ID | Component | Status | Note |
|--------|-----------|--------|------|
| 8.1 | VariantSyncService | APLICAT + TESTAT | Advisory -> Row lock order (11 teste) |
| 8.2 | UpdateOptionsService | APLICAT + TESTAT | Exclude self conflict (8 teste) |
| 8.3 | CreateOrReactivateService | APLICAT + TESTAT | constraint_name parsing (18 teste) |
| 8.4 | IdSanitizer | APLICAT + TESTAT | Whitespace contract (20 teste) |
| 8.5 | VariantSyncConfig | APLICAT + TESTAT | StatsD guard (16 teste) |
| 8.6 | FinalizeService | APLICAT + TESTAT | Atomic transaction wrapper (7 teste) |
| 8.7 | RestockService | APLICAT + TESTAT | Idempotency guard (7 teste) |

**Toate 7/7 hardening fixes aplicati si testati.**

---

**Ultima actualizare:** FAZA 2 COMPLETA - toate cele 13 componente implementate (127 teste pass)

**Rezultat final:** 289 teste totale (FAZA 1 + FAZA 2), 0 failures

**Realizari notabile:**
- Acoperire teste FAZA 2: **148% fata de estimari** (127 vs ~86 estimate)
- 7/7 hardening fixes aplicati si verificati prin teste
- Lock order verificat in runtime via SQL capture (Gold Standard)
- Nested transaction safety demonstrata (requires_new: true SAVEPOINT)
- Lock safety patterns: zero pattern-uri periculoase in codebase
- Zero duplicare logica (DRY patterns aplicati corect)

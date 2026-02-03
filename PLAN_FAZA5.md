# FAZA 5 — DEPLOY

**Status:** PLAN COMPLET - READY TO EXECUTE

---

## INFRASTRUCTURA

| Component | Detalii |
|-----------|---------|
| **Hosting** | Render.com (Web Service) |
| **Plan** | Starter |
| **Domeniu** | ayus.ro |
| **DB** | PostgreSQL pe Render.com Frankfurt (`ag1_production`) |
| **Build script** | `bin/render-build.sh` (ruleaza `db:migrate` automat) |
| **Entrypoint** | `bin/docker-entrypoint` (ruleaza `db:prepare` la start container) |
| **Ruby** | 3.3.9 (Docker multi-stage) |
| **Workers** | WEB_CONCURRENCY=1, RAILS_MAX_THREADS=2 |
| **CI/CD** | Nu exista pipeline - deploy manual via Render dashboard sau git push |
| **Staging** | Nu exista - doar production |

---

## CE SE DEPLOYEAZA

### Migratii (3 fisiere)

| # | Migratie | Timestamp | Ce face | Risc |
|---|---------|-----------|---------|------|
| 1 | M1: Create Variant System | 20260202220011 | Creeaza 5 tabele noi (option_types, option_values, product_option_types, variants, option_value_variants) + 6 coloane pe order_items | **SCAZUT** - doar CREATE TABLE + ADD COLUMN |
| 2 | M3: Add Variants Constraints | 20260202220012 | Adauga partial indexes + CHECK constraints (Postgres-only) | **SCAZUT** - tabele goale, constraints pe date noi |
| 3 | M4: Create Variant External IDs | 20260202220013 | Creeaza tabela variant_external_ids + indexes + CHECK constraints | **SCAZUT** - tabel nou, fara date existente |

**Nota:** M2 (Cleanup & Preflight) a fost OMISA — implementare greenfield, nu exista date legacy de curatat.

### Cod nou

| Categorie | Fisiere | Detalii |
|-----------|---------|---------|
| **Modele noi** | 6 | OptionType, OptionValue, OptionValueVariant, ProductOptionType, Variant, VariantExternalId |
| **Model modificat** | 1 | Product (adaugat has_many :variants, archive!) |
| **Concerns** | 2 | IdSanitizer, AdvisoryLockKey |
| **Servicii** | 9 | CreateOrReactivateService, UpdateOptionsService, OptionValueValidator, BulkLockingService, AdminExternalIdService, UpdateOptionTypesService, VariantSyncService, FinalizeService, RestockService |
| **Initializer** | 1 | variant_sync.rb (VariantSyncConfig) |
| **Rake task** | 1 | variants:audit |
| **Factories** | 7 | Pentru toate modelele noi |
| **Spec files** | 25+ | 344 teste, 0 failures |

---

## 1. PRE-DEPLOY CHECKLIST

### 1.1. Verificari locale

- [ ] **Teste:** `bundle exec rspec` → 344 examples, 0 failures
- [ ] **Migratii reversibile:** Toate 3 migratiile folosesc `change` (auto-reversible)
- [ ] **Guards idempotente:** Migratiile au `unless index_exists?`, `unless column_exists?`, `unless constraint_exists?` — safe to re-run
- [ ] **Schema.rb actualizat:** `db/schema.rb` reflecta toate migratiile
- [ ] **Gemfile:** Nicio dependenta noua adaugata (verificat `Gemfile.lock`)

### 1.2. Backup DB Production

- [ ] **Render Dashboard** → ag1_production → Manual Backup
- [ ] **Verifica** ca backup-ul apare in lista cu timestamp corect
- [ ] **Optional:** Download backup local ca safety net

### 1.3. ENV Vars pe Render

Adauga in Render Dashboard → ag1 → Environment:

| ENV Var | Valoare | Obligatoriu | Scop |
|---------|---------|-------------|------|
| `VARIANT_SYNC_DUAL_LOCK_ENABLED` | `true` | Recomandat | Activeaza dual-lock strategy (backward compatibility pentru rolling deploy) |

**Nota:** Daca nu setezi `VARIANT_SYNC_DUAL_LOCK_ENABLED`, default-ul este `true` (din `variant_sync.rb`).

### 1.4. Review migration safety

**M1 (Create Variant System):**
- `CREATE TABLE` — non-blocking, safe
- `ADD COLUMN` pe `order_items` — poate fi slow daca tabela e mare, dar are guard `unless column_exists?`
- `ADD REFERENCE` cu FK — adauga FK constraint care necesita `SHARE ROW EXCLUSIVE` lock pe order_items
- **Risc:** Daca `order_items` are multe randuri, `ADD REFERENCE :order_items, :variant` poate lock tabela temporar

**M3 (Constraints):**
- `ADD INDEX` pe tabele goale — instant
- `ADD CHECK CONSTRAINT` pe tabele goale — instant
- `return unless postgres?` guard — safe pe non-Postgres

**M4 (External IDs):**
- `CREATE TABLE` — non-blocking
- `ADD INDEX` + `ADD CHECK CONSTRAINT` pe tabel gol — instant

---

## 2. DEPLOY PROCEDURE

### Deploy unic (nu incremental)

Deoarece aceasta este o implementare **greenfield** (nicio data existenta de variante), toate 3 migratiile pot rula intr-un singur deploy. Nu este nevoie de deploy incremental sau maintenance window.

### Pasii deploy:

#### Pas 2.1: Git push

```bash
# Asigura-te ca esti pe branch-ul corect
git status
git log --oneline -5

# Push la remote (Render detecteaza automat si triggereaza build)
git push origin main
```

#### Pas 2.2: Monitorizare build pe Render

1. Deschide Render Dashboard → ag1 → Events
2. Urmareste logurile de build:
   - `Instalez gem-urile necesare...` — bundle install
   - `Precompilez assets...` — asset precompile
   - `Migrez baza de date...` — **AICI RULEAZA MIGRATIILE**
3. **IMPORTANT:** Verifica in loguri:
   - `== M1CreateVariantSystem: migrating ==` — M1 a inceput
   - `== M1CreateVariantSystem: migrated ==` — M1 completata
   - `== M3AddVariantsConstraints: migrating ==` — M3 a inceput
   - `== M3AddVariantsConstraints: migrated ==` — M3 completata
   - `== M4CreateVariantExternalIds: migrating ==` — M4 a inceput
   - `== M4CreateVariantExternalIds: migrated ==` — M4 completata
4. **ATENTIE:** `bin/render-build.sh` are `db:migrate || true` — daca o migratie esueaza, build-ul NU va pica! Verifica manual ca toate 3 migratiile au rulat.

#### Pas 2.3: Verificare container start

1. Dupa build, Render porneste containerul nou
2. `bin/docker-entrypoint` ruleaza `db:prepare` — aceasta este redundanta (migratiile deja au rulat), dar safe
3. Verifica in loguri:
   - `[VariantSyncConfig] Dual-lock strategy: ENABLED` — initializer-ul variant_sync.rb a rulat

---

## 3. POST-DEPLOY VERIFICARE

### 3.1. Health check

- [ ] **Site up:** https://ayus.ro raspunde cu 200
- [ ] **Functionalitate existenta:** Navigare produse, cos, checkout — totul functioneaza normal
- [ ] **Nu sunt erori 500** in primele minute

### 3.2. Verificare migratii (via Render Shell)

Deschide Render Dashboard → ag1 → Shell:

```bash
# Verifica ca toate migratiile au rulat
bundle exec rails db:migrate:status
```

Rezultat asteptat:
```
Status   Migration ID    Migration Name
--------------------------------------------------
  up     ...             ...  (migratii existente)
  up     20260202220011  M1 create variant system
  up     20260202220012  M3 add variants constraints
  up     20260202220013  M4 create variant external ids
```

**Daca una din migratii este `down`:**
```bash
bundle exec rails db:migrate
```

### 3.3. Variants Audit

```bash
bundle exec rails variants:audit
```

Rezultat asteptat (greenfield, nicio data):
```
=== VARIANTS AUDIT ===
No SKU duplicates
No active digest duplicates
No negative stock
No negative price
No NULL stock
No NULL price
No orphan external ID mappings
External IDs by source: {}
External IDs by source+account: {}
Variants without external mapping: 0
=== END AUDIT ===
```

### 3.4. Verificare schema DB (via Rails console)

```bash
bundle exec rails console
```

```ruby
# Verifica tabelele noi exista
%w[option_types option_values product_option_types variants option_value_variants variant_external_ids].each do |t|
  puts "#{t}: #{ActiveRecord::Base.connection.table_exists?(t)}"
end

# Verifica coloanele pe order_items
%w[variant_id variant_sku variant_options_text vat_rate_snapshot currency line_total_gross tax_amount].each do |col|
  puts "order_items.#{col}: #{ActiveRecord::Base.connection.column_exists?(:order_items, col)}"
end

# Verifica partial indexes (Postgres)
puts ActiveRecord::Base.connection.index_exists?(:variants, [:product_id, :options_digest], name: 'idx_unique_active_options_per_product')
puts ActiveRecord::Base.connection.index_exists?(:variants, [:product_id], name: 'idx_unique_active_default_variant')
puts ActiveRecord::Base.connection.index_exists?(:variants, :external_sku, name: 'idx_unique_external_sku')

# Verifica CHECK constraints
sql = "SELECT conname FROM pg_constraint WHERE conrelid = 'variants'::regclass AND contype = 'c'"
puts ActiveRecord::Base.connection.execute(sql).map { |r| r['conname'] }
# Asteptat: chk_variants_price_positive, chk_variants_stock_positive, chk_variants_status_enum

sql2 = "SELECT conname FROM pg_constraint WHERE conrelid = 'variant_external_ids'::regclass AND contype = 'c'"
puts ActiveRecord::Base.connection.execute(sql2).map { |r| r['conname'] }
# Asteptat: chk_vei_source_format, chk_vei_source_account_format, chk_vei_external_id_not_empty, chk_vei_external_id_normalized

puts "DONE - All checks passed"
```

### 3.5. Test rapid model layer

```ruby
# In Rails console:

# Creeaza un option type
ot = OptionType.create!(name: 'test_color', presentation: 'Culoare Test')
puts "OptionType: #{ot.persisted?}"

# Creeaza option values
ov = OptionValue.create!(option_type: ot, name: 'rosu', presentation: 'Rosu')
puts "OptionValue: #{ov.persisted?}"

# Creeaza variant pe un produs existent
product = Product.first
if product
  v = Variant.create!(product: product, sku: "TEST-DEPLOY-#{Time.now.to_i}", price: 10, stock: 5)
  puts "Variant: #{v.persisted?}, status: #{v.status}"

  # Cleanup
  v.destroy!
  puts "Variant destroyed"
end

ov.destroy!
ot.destroy!
puts "Cleanup complete"
```

---

## 4. MONITORING (primele 24h)

### 4.1. Loguri de urmarit

Render Dashboard → ag1 → Logs:

| Pattern | Semnificatie | Actiune |
|---------|-------------|---------|
| `deadlock detected` | Deadlock intre tranzactii | Investigheaza — verifica lock ordering in servicii |
| `ActiveRecord::Deadlocked` | Deadlock Rails-level | Investigheaza — posibil lock order violation |
| `product_mismatch` | External ID mapat pe alt produs | Verifica config feed import |
| `PG::UniqueViolation` | Constraint violation la insert | Normal daca e race condition handled; investigheaza daca persistent |
| `PG::CheckViolation` | CHECK constraint violation | Bug in cod — pret negativ, stoc negativ, etc. |
| `[VariantSyncConfig]` | Status dual-lock la boot | Informational |

### 4.2. Metrici (daca StatsD configurat)

| Metric | Scop |
|--------|------|
| `variant_sync.dual_lock_call` | Nr apeluri cu dual-lock activat |
| `variant_sync.legacy_lock_call` | Nr apeluri cu legacy lock format |

**Nota:** StatsD nu pare configurat in proiect (`if defined?(StatsD)` guard). Aceste metrici vor fi no-op pana la configurarea StatsD.

### 4.3. Performance

- [ ] **Response times:** Nu trebuie sa creasca semnificativ (nu s-au modificat query-uri existente)
- [ ] **Memory:** Monitorizare pe Render dashboard — noul cod nu ar trebui sa creasca consumul
- [ ] **DB connections:** Pool = 2 (RAILS_MAX_THREADS) — suficient pentru Starter plan

---

## 5. ROLLBACK PLAN

### 5.1. Rollback rapid (cod)

Daca noul cod cauzeaza probleme dar migratiile au rulat corect:

1. Render Dashboard → ag1 → Manual Deploy → selecteaza commit-ul anterior
2. Sau: `git revert HEAD && git push origin main`

**Nota:** Codul vechi nu cunoaste tabelele noi, dar asta e OK — tabelele goale nu afecteaza functionalitatile existente.

### 5.2. Rollback complet (cod + migratii)

Daca migratiile cauzeaza probleme (ex: lock pe order_items):

```bash
# Via Render Shell:
bundle exec rails db:rollback STEP=3
```

Aceasta va reversa (in ordine inversa):
1. M4 — drop table `variant_external_ids`
2. M3 — remove partial indexes + CHECK constraints
3. M1 — drop tables `option_value_variants`, `variants`, `product_option_types`, `option_values`, `option_types` + remove columns de pe `order_items`

**Toate 3 migratiile folosesc `change` — sunt auto-reversible.**

### 5.3. Rollback din backup

Cazul cel mai grav — daca rollback-ul nu functioneaza:

1. Render Dashboard → ag1_production → Restore from backup
2. Selecteaza backup-ul creat la Pas 1.2
3. Redeploy commit-ul anterior

---

## 6. VARIABILE DE MEDIU DOCUMENTATIE

### Noi (introduse de sistemul de variante)

| ENV Var | Default | Valori | Scop |
|---------|---------|--------|------|
| `VARIANT_SYNC_DUAL_LOCK_ENABLED` | `"true"` | `"true"/"1"/"yes"` sau `"false"/"0"/"no"` | Controleaza dual-lock strategy in VariantSyncService. `true` = acquire both legacy + new advisory locks (safe pentru rolling deploy). `false` = doar new advisory lock. |

### Existente (relevante)

| ENV Var | Valoare pe Render | Relevanta |
|---------|------------------|-----------|
| `DATABASE_URL` | Auto de la ag1_production | Conexiune PostgreSQL |
| `RAILS_MAX_THREADS` | 2 | Pool DB connections |
| `WEB_CONCURRENCY` | 1 | Nr Puma workers |

---

## 7. VERIFICARI FINALE (din PLAN_VARIANTE10.md)

Cele 15 verificari critice aplicate la implementarea reala:

| # | Verificare | Status | Note |
|---|-----------|--------|------|
| 1 | Index names identice (idx_unique_*, idx_vei_*, idx_ovv_*, chk_*) | OK | Verificat in migratii M1/M3/M4 |
| 2 | Partial unique indexes doar pe Postgres (si `return unless postgres?`) | OK | M3 are `return unless postgres?` |
| 3 | M2CleanupVariantsData e Postgres-only cu preflight-uri fail-fast | N/A | M2 omisa (greenfield) |
| 4 | M1 are preflight check pentru `variants.status` type (Fix 9) | N/A | Greenfield — nu exista coloana anterioara |
| 5 | CreateOrReactivateService are `@product.transaction(requires_new: true) + @product.lock!` | OK | Implementat in FAZA 2 |
| 6 | UpdateOptionsService are lock product + lock variant | OK | Implementat in FAZA 2 |
| 7 | OptionValueValidator e extras si inclus in ambele servicii | OK | Implementat in FAZA 2 |
| 8 | VariantSyncService#update_existing foloseste `with_variant_transaction_if_needed` | OK | Implementat in FAZA 2 |
| 9 | VariantSyncService#create_or_link_new are guard `result.variant&.persisted?` | OK | Implementat in FAZA 2 |
| 10 | VariantSyncService#create_or_link_new: already_exists/race_condition → return linked | OK | Implementat in FAZA 2 |
| 11 | VariantSyncService#handle_unique_violation returneaza :conflict cand mapping exista (Fix 8) | OK | Implementat in FAZA 2 |
| 12 | Advisory lock guard: `assert_transaction_open_on_lock_connection!` | OK | AdvisoryLockKey concern, FAZA 2 |
| 13 | `transaction_open_on?(conn)` cu fallback (Fix 7) | OK | AdvisoryLockKey concern, FAZA 2 |
| 14 | Lock order: orice lock pe variants bulk e cu `.order(:id).lock` | OK | BulkLockingService + archive!, FAZA 3 |
| 15 | Metrici: `increment_legacy_lock_counter` in loc de StatsD direct (Fix 4) | OK | VariantSyncConfig, FAZA 2 |

**Rezultat:** 13/15 OK, 2/15 N/A (M2 omisa).

---

## 8. REZUMAT EXECUTIE

```
[ ] 1. Backup DB pe Render
[ ] 2. (Optional) Set VARIANT_SYNC_DUAL_LOCK_ENABLED=true pe Render
[ ] 3. git push origin main
[ ] 4. Monitorizare build logs — confirma 3 migratii up
[ ] 5. Verifica [VariantSyncConfig] in logs
[ ] 6. Health check: https://ayus.ro
[ ] 7. Render Shell: rails db:migrate:status → toate up
[ ] 8. Render Shell: rails variants:audit → no issues
[ ] 9. (Optional) Test rapid in Rails console
[ ] 10. Monitorizare logs 24h — fara deadlocks/errors
```

---

## TOTAL PROGRES PROIECT

| Faza | Componente | Teste | Status |
|------|------------|-------|--------|
| FAZA 1 | 12 suites | 162 | COMPLET |
| FAZA 2 | 13 componente | 127 | COMPLET |
| FAZA 3 | 6 componente | 55 | COMPLET |
| FAZA 4 | Integrata in F2+F3 | - | COMPLET |
| **FAZA 5** | **Deploy** | **-** | **PLAN READY** |
| **TOTAL** | **31+** | **344** | **0 failures** |

---

**Ultima actualizare:** FAZA 5 PLAN COMPLET

**Rezultat local:** 344 teste, 0 failures. Codul este ready pentru deploy.

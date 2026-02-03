# FAZA 1 — SCHEMA CORE (M1–M3) + Modele + Factories + Teste Schema

**Status:** COMPLET (162 teste pass, 0 failures)

---

## CE S-A FACUT

FAZA 1 a implementat fundatia intregului sistem de variante: migrarile DB, modelele ActiveRecord, factories si testele complete de schema/constraints/FK/model validations.

---

## 1. MIGRATII DB (3 fisiere)

### 1.1. M1: Create Variant System
**Fisier:** `db/migrate/20260202220011_m1_create_variant_system.rb`

**Tabele create:**
| Tabla | Coloane cheie | Note |
|-------|---------------|------|
| `option_types` | name (unique), presentation, position | Ex: "Culoare", "Marime" |
| `option_values` | option_type_id (FK), name, presentation, position | Ex: "Rosu", "M", "XL" |
| `product_option_types` | product_id (FK), option_type_id (FK), position | Join table: ce option types are un produs |
| `variants` | product_id (FK restrict), sku (NOT NULL), price (default 0), stock (default 0), status (int default 0), options_digest, external_sku, vat_rate | Variantele produsului |
| `option_value_variants` | variant_id (FK cascade), option_value_id (FK restrict) | Join table: ce optiuni are o varianta |

**Coloane adaugate pe `order_items`:**
- `variant_id` (FK nullify) - referinta la varianta
- `variant_sku` - snapshot SKU la momentul cumpararii
- `variant_options_text` - snapshot optiuni (ex: "Culoare: Rosu, Marime: M")
- `vat_rate_snapshot` - snapshot TVA
- `currency` (default 'RON')
- `line_total_gross` - total brut linie
- `tax_amount` - suma TVA

**Indexuri create in M1:**
- `idx_unique_sku_per_product` (unique: product_id + sku)
- `idx_unique_ovv` (unique: variant_id + option_value_id)
- `idx_unique_product_option_type` (unique: product_id + option_type_id)
- `idx_ovv_variant`, `idx_ovv_option_value` (performance)
- `variants.status` index

---

### 1.2. M3: Add Variants Constraints
**Fisier:** `db/migrate/20260202220012_m3_add_variants_constraints.rb`

**Indexuri universale aditionale:**
- `idx_pot_product` (performance pe product_option_types)
- `idx_ov_type` (performance pe option_values)

**Postgres-only partial indexes:**
| Index | Conditie | Scop |
|-------|----------|------|
| `idx_unique_active_options_per_product` | `options_digest IS NOT NULL AND status = 0` | Max 1 varianta activa per combinatie optiuni |
| `idx_unique_active_default_variant` | `options_digest IS NULL AND status = 0` | Max 1 varianta default activa per produs |
| `idx_unique_external_sku` | `external_sku IS NOT NULL` | External SKU unic global |

**Postgres-only CHECK constraints:**
| Constraint | Regula | Scop |
|------------|--------|------|
| `chk_variants_price_positive` | `price IS NOT NULL AND price >= 0` | Previne pret negativ/null |
| `chk_variants_stock_positive` | `stock IS NOT NULL AND stock >= 0` | Previne stoc negativ/null |
| `chk_variants_status_enum` | `status IN (0, 1)` | Doar active(0) si inactive(1) |

---

### 1.3. M4: Create Variant External IDs
**Fisier:** `db/migrate/20260202220013_m4_create_variant_external_ids.rb`

**Tabla creata:**
| Tabla | Coloane | Note |
|-------|---------|------|
| `variant_external_ids` | variant_id (FK cascade), source (NOT NULL), source_account (NOT NULL, default 'default'), external_id (NOT NULL), external_sku | Mapping-uri externe |

**Indexuri:**
- `idx_unique_source_account_external_id` (unique: source + source_account + external_id)
- `idx_vei_variant` (lookup rapid dupa variant)
- `idx_vei_source` (cautare dupa source)
- `idx_vei_source_account` (cautare dupa source + account)

**Postgres-only CHECK constraints:**
| Constraint | Regula | Scop |
|------------|--------|------|
| `chk_vei_source_format` | `source ~ '^[a-z][a-z0-9_]{0,49}$'` | Doar lowercase alfanumeric |
| `chk_vei_source_account_format` | `source_account ~ '^[a-z][a-z0-9_]{0,49}$'` | Doar lowercase alfanumeric |
| `chk_vei_external_id_not_empty` | `btrim(external_id) <> ''` | Nu permite empty/whitespace |
| `chk_vei_external_id_normalized` | `external_id = btrim(external_id)` | Fara leading/trailing whitespace |

---

## 2. MODELE ActiveRecord (7 fisiere)

### 2.1. Modele noi create

| Model | Fisier | Asocieri cheie |
|-------|--------|---------------|
| `OptionType` | `app/models/option_type.rb` | has_many :option_values (dependent: destroy), has_many :product_option_types |
| `OptionValue` | `app/models/option_value.rb` | belongs_to :option_type, has_many :option_value_variants |
| `OptionValueVariant` | `app/models/option_value_variant.rb` | belongs_to :variant, belongs_to :option_value |
| `ProductOptionType` | `app/models/product_option_type.rb` | belongs_to :product, belongs_to :option_type |
| `Variant` | `app/models/variant.rb` | belongs_to :product, has_many :option_value_variants (dependent: destroy), has_many :external_ids (dependent: destroy) |
| `VariantExternalId` | `app/models/variant_external_id.rb` | belongs_to :variant |

### 2.2. Modele modificate

| Model | Fisier | Modificari |
|-------|--------|-----------|
| `Product` | `app/models/product.rb` | has_many :variants (dependent: restrict_with_exception), has_many :product_option_types (dependent: destroy), has_many :option_types through: :product_option_types |

### 2.3. Functionalitati cheie model Variant

- **enum** `:status, { active: 0, inactive: 1 }`
- **validates**: sku (presence, uniqueness scoped to product_id), price (>= 0), stock (>= 0)
- **before_save**: `compute_options_digest` - SHA256 digest din option_value_ids sortate
- **`#options_text`** - format "Culoare: Rosu, Marime: M"
- **`#price_breakdown`** - calcul VAT (brut, net, tva)

### 2.4. Functionalitati cheie model VariantExternalId

- **validates**: source (presence, format), external_id (presence, uniqueness scoped to source+account)
- **before_validation**: `normalize_values` (lowercase source/account, strip external_id)
- **`self.find_variant`** - lookup variant dupa source + external_id
- **`self.normalize_lookup`** - normalizare parametri lookup (DRY)
- **scopes**: `by_source`, `by_source_account`

---

## 3. FACTORIES (7 fisiere)

| Factory | Fisier | Note |
|---------|--------|------|
| `product` | `spec/factories/products.rb` | Cu sequence pe name/slug/sku |
| `option_type` | `spec/factories/option_types.rb` | Cu sequence pe name |
| `option_value` | `spec/factories/option_values.rb` | Cu association option_type |
| `variant` | `spec/factories/variants.rb` | Cu association product, sequence sku |
| `option_value_variant` | `spec/factories/option_value_variants.rb` | Join factory |
| `product_option_type` | `spec/factories/product_option_types.rb` | Join factory |
| `variant_external_id` | `spec/factories/variant_external_ids.rb` | Cu association variant, sequence external_id |

---

## 4. SUPPORT HELPERS (2 fisiere)

| Helper | Fisier | Scop |
|--------|--------|------|
| `DbMinInsertHelper` | `spec/support/db_min_insert_helper.rb` | `insert_min_row!` - insereaza rand minim in tabela (pentru FK constraint tests pe order_items) |
| `LockOrderHelper` | `spec/support/lock_order_helper.rb` | `capture_lock_queries`, `expect_lock_order!`, `select_for_update_regex` - SQL capture pentru lock order verification |

---

## 5. TESTE (12 suite-uri, 162 teste)

### 5.1. Model Specs - Validari + Asocieri

| Spec | Fisier | Teste FAZA 1 | Adaugate FAZA 3 | Total actual | Ce testeaza |
|------|--------|-------------|-----------------|-------------|-------------|
| OptionType | `spec/models/option_type_spec.rb` | 5 | - | 5 | Validari (name required, unique), asocieri (has_many option_values, dependent destroy) |
| OptionValue | `spec/models/option_value_spec.rb` | 6 | - | 6 | Validari (name required, unique per type, allows same in different types), display_name (2 teste) |
| OptionValueVariant | `spec/models/option_value_variant_spec.rb` | 3 | - | 3 | Unicitate option_value per variant, allows same on different variants |
| ProductOptionType | `spec/models/product_option_type_spec.rb` | 3 | - | 3 | Unicitate option_type per product, allows same on different products |
| Variant | `spec/models/variant_spec.rb` | 17 | - | 17 | Validari (sku, price, stock), enum status (2), options_text, price_breakdown (3), compute_options_digest (3), asocieri (destroy cascades OVV + VEI) |
| VariantExternalId | `spec/models/variant_external_id_spec.rb` | 16 | +4 | 20 | Validari (source, external_id, uniqueness, format), normalizare (3), find_variant (3), scopes (2), asocieri. *FAZA 3: +4 normalize_lookup* |
| Product | `spec/models/product_spec.rb` | 11 | +5 | 16 | Validari (name, slug, price, sku), price_breakdown (2), variant associations (has_many, option_types through, restrict deletion, destroy cascades POT). *FAZA 3: +5 archive!* |

**Total model specs FAZA 1:** 5 + 6 + 3 + 3 + 17 + 16 + 11 = **61 teste**
*(Fisierele actuale contin 61 + 9 = 70 teste dupa adaugarile din FAZA 3)*

---

### 5.2. Schema Specs - Verificare Structura DB

| Spec | Fisier | Teste | Ce testeaza |
|------|--------|-------|-------------|
| Variant Schema | `spec/models/variant_schema_spec.rb` | 43 | Column defaults/nullability (variants 5 teste, VEI 3 teste, order_items 7 teste), index existence (variants 2, OVV 3, POT 1, VEI 3, order_items 1, postgres partial 3 = 13 teste), foreign keys (8 FK + on_delete = 9 teste), CHECK constraints (6 constraints = 6 teste) |
| Variant Unique Indexes | `spec/models/variant_unique_indexes_spec.rb` | 12 | DB-level unicitate bypass Rails validations: idx_unique_sku_per_product (2), idx_unique_ovv (2), idx_unique_product_option_type (2), idx_unique_source_account_external_id (3), option_types.name (1), option_values per type (2) |
| Variant DB Constraints | `spec/models/variant_db_constraints_spec.rb` | 29 | Partial indexes: default variant (4), active options (4), external_sku (3). CHECK constraints: price (3), stock (3), status (3), VEI source format (3), VEI source_account format (3), VEI external_id (3) |
| Variant FK Constraints | `spec/models/variant_fk_constraints_spec.rb` | 12 | FK behaviors: variants->products restrict (2), OVV->variants cascade (1), OVV->option_values restrict (2), VEI->variants cascade (1), POT->products restrict (2), OV->option_types restrict (2), POT->option_types restrict (1), order_items->variants nullify (1) |
| Variant Isolation | `spec/models/variant_isolation_spec.rb` | 5 | V->P izolare: price/stock update nu touch product (2 teste), status change nu touch (1), add option_values nu touch (1), read variants nu modifica (1) |

**Total schema + isolation specs:** 43 + 12 + 29 + 12 + 5 = **101 teste** (96 schema + 5 isolation)

---

### 5.3. Ce verifica fiecare tip de test

**Model specs** - verifica **Rails layer**: validari ActiveRecord, callbacks, asocieri, metode de instanta/clasa. Folosesc `build(:factory)` si `create(:factory)`.

**Schema specs** - verifica **DB layer**: coloane exista cu tipul/default corect, indexuri exista, foreign keys au on_delete corect, CHECK constraints rejecteaza valori invalide. Folosesc `connection.columns`, `connection.index_exists?`, `connection.foreign_key_exists?`, `update_column` (bypass Rails).

**Isolation specs** - verifica **side-effects**: update pe Variant NU produce UPDATE pe products table. Folosesc `ActiveSupport::Notifications` SQL capture + `travel` time helpers.

---

### 5.4. Rezumat Teste FAZA 1

| Categorie | Suite-uri | Teste FAZA 1 |
|-----------|-----------|-------------|
| Model Validari + Asocieri | 7 | 61 |
| Schema (columns, indexes, FK, CHECK) | 4 | 96 |
| Izolare V->P | 1 | 5 |
| **TOTAL FAZA 1** | **12** | **162** |

**Verificare aritmetica:** 61 (model) + 96 (schema) + 5 (isolation) = **162**

**Nota:** Dupa adaugarile din FAZA 3 (+4 normalize_lookup, +5 archive!), cele 12 suite-uri contin acum 171 teste.
Testele FAZA 3 adaugate in fisiere FAZA 1 sunt contabilizate in FAZA 3 (55 teste), nu aici.

---

## 6. DESIGN DECISIONS

### M2 (Cleanup & Preflight) - OMISA
Migratia M2 din plan (cleanup date existente) nu a fost necesara deoarece aceasta este o implementare greenfield - nu exista date legacy de curatat.

### Consolidare migratii
Planul prevedea migratii separate M1, M2, M3, M4, M5. In practica:
- **M1** consolidata: creeaza toate tabelele + indexuri universale intr-o singura migratie
- **M2** omisa (greenfield, nu exista date de curatat)
- **M3** contine doar partial indexes + CHECK constraints (Postgres-only)
- **M4** creeaza variant_external_ids + constraints
- **M5** nu a fost necesara (functionalitatile integrate in M1/M3/M4)

### FK on_delete behaviors
| FK | Behavior | Motivatie |
|----|----------|-----------|
| variants -> products | RESTRICT | Nu sterge produsul daca are variante |
| option_value_variants -> variants | CASCADE | Sterge automat la delete variant |
| option_value_variants -> option_values | RESTRICT | Nu sterge option_value daca e folosita |
| variant_external_ids -> variants | CASCADE | Sterge automat la delete variant |
| order_items -> variants | NULLIFY | Pastreaza order_item dar nullifies referinta |

### Enum vs String pentru Variant.status
- `enum :status, { active: 0, inactive: 1 }` (integer backed)
- CHECK constraint DB-level: `status IN (0, 1)`
- Avantaj: eficient, type-safe, extensibil

---

## TOTAL PROGRES DUPA FAZA 1

| Faza | Componente | Teste | Status |
|------|------------|-------|--------|
| FAZA 1 | 12 suites | 162 | COMPLET |

---

**Ultima actualizare:** FAZA 1 COMPLETA

**Rezultat:** 162 teste, 0 failures. Fundatia sistemului de variante stabilita.

# FAZA 1 - Lista Completa Teste (162 total, 0 failures)

> **Sursa de adevar:** `bundle exec rspec --format documentation` pe cele 12 suite-uri FAZA 1.
> Numerele reflecta `it` blocks reale din spec files, NU estimari sau descrieri planificate.
> Testele adaugate ulterior in FAZA 3 (normalize_lookup +4, archive! +5) sunt notate separat.

---

## 1. spec/models/option_type_spec.rb (5 teste)
- is valid with valid attributes
- requires name
- requires unique name
- has many option_values
- destroys option_values when destroyed

## 2. spec/models/option_value_spec.rb (6 teste)
- is valid with valid attributes
- requires name
- requires unique name within option_type
- allows same name in different option_types
- `#display_name` returns presentation if set
- `#display_name` returns name if presentation is blank

## 3. spec/models/option_value_variant_spec.rb (3 teste)
- is valid with valid attributes
- requires unique option_value per variant
- allows same option_value on different variants

## 4. spec/models/product_option_type_spec.rb (3 teste)
- is valid with valid attributes
- requires unique option_type per product
- allows same option_type on different products

## 5. spec/models/variant_spec.rb (17 teste)

**validations (6):**
- is valid with valid attributes
- requires sku
- requires unique sku within product
- allows same sku in different products
- requires price >= 0
- requires stock >= 0

**enum status (2):**
- defaults to active
- can be set to inactive

**#options_text (1):**
- returns formatted options string

**#price_breakdown (3):**
- calculates VAT correctly for 19%
- returns zero VAT when vat_rate is 0
- returns zero VAT when vat_rate is nil

**#compute_options_digest (3):**
- generates digest based on option_value_ids
- returns nil when no option_values
- generates same digest for same option_values regardless of order

**associations (2):**
- destroys option_value_variants when destroyed
- destroys external_ids when destroyed

## 6. spec/models/variant_external_id_spec.rb (16 teste FAZA 1 + 4 adaugate in FAZA 3 = 20 actual)

**validations (7):**
- is valid with valid attributes
- requires source
- requires external_id
- requires source to be lowercase
- rejects invalid source format
- requires unique external_id per source and account
- allows same external_id on different source_accounts

**normalization (3):**
- normalizes source to lowercase
- normalizes source_account to lowercase
- strips whitespace from external_id

**.find_variant (3):**
- finds variant by external_id
- returns nil when not found
- respects source_account parameter

**scopes (2):**
- by_source returns records for source
- by_source_account returns records for source and account

**associations (1):**
- is destroyed when variant is destroyed

*Adaugate in FAZA 3 (+4 teste .normalize_lookup):*
- *normalizes source to lowercase and stripped*
- *normalizes source_account to lowercase with default fallback*
- *strips whitespace from external_id*
- *handles nil/blank inputs via compact*

## 7. spec/models/product_spec.rb (11 teste FAZA 1 + 5 adaugate in FAZA 3 = 16 actual)

**validations (5):**
- is valid with valid attributes
- requires name
- requires slug
- requires price
- requires sku

**#price_breakdown (2):**
- calculates VAT correctly for 19%
- returns zero VAT when vat is 0

**variant associations (4):**
- has many variants
- has many option_types through product_option_types
- restricts deletion when variants exist
- destroys product_option_types when destroyed

*Adaugate in FAZA 3 (+5 teste #archive!):*
- *deactivates all active variants and sets product status to archived*
- *handles product without variants*
- *lock order P -> V\* (ORDER BY id) runtime SQL verification (postgres_only)*
- *does not affect variants of other products*
- *handles mixed state: active + inactive variants*

---

## 8. spec/models/variant_db_constraints_spec.rb (29 teste)

### Partial Indexes (Postgres-only):

**idx_unique_active_default_variant (4 teste):**
- prevents two active default variants for same product
- allows active + inactive default variants for same product
- allows new active default when existing default is inactive
- allows active defaults on different products

**idx_unique_active_options_per_product (4 teste):**
- prevents two active variants with same options_digest for same product
- allows active + inactive variants with same options_digest
- allows two inactive variants with same options_digest
- allows same options_digest on different products (both active)

**idx_unique_external_sku (3 teste):**
- prevents duplicate external_sku values
- allows multiple variants with nil external_sku
- allows one with external_sku and one without

### CHECK Constraints (Postgres-only):

**chk_variants_price_positive (3 teste):**
- rejects negative price at DB level
- rejects NULL price at DB level
- allows zero price

**chk_variants_stock_positive (3 teste):**
- rejects negative stock at DB level
- rejects NULL stock at DB level
- allows zero stock

**chk_variants_status_enum (3 teste):**
- rejects invalid status values at DB level
- allows status 0 (active)
- allows status 1 (inactive)

**chk_vei_source_format (3 teste):**
- rejects invalid source format at DB level
- rejects source with uppercase at DB level
- allows valid source format (lowercase with underscores)

**chk_vei_source_account_format (3 teste):**
- rejects invalid source_account format at DB level
- rejects source_account with uppercase at DB level
- allows valid source_account format (lowercase with underscores)

**chk_vei_external_id_not_empty (3 teste):**
- rejects empty external_id at DB level
- rejects whitespace-only external_id at DB level
- allows valid external_id

---

## 9. spec/models/variant_fk_constraints_spec.rb (12 teste)

**variants -> products FK (restrict) (2 teste):**
- prevents product deletion when variants exist (using delete)
- allows product deletion when no variants exist

**option_value_variants -> variants FK (cascade) (1 test):**
- cascades delete to option_value_variants when variant is deleted

**option_value_variants -> option_values FK (restrict) (2 teste):**
- prevents option_value deletion when used by variants
- allows option_value deletion when not used

**variant_external_ids -> variants FK (cascade) (1 test):**
- cascades delete to variant_external_ids when variant is deleted

**product_option_types -> products FK (restrict) (2 teste):**
- prevents product deletion when product_option_types exist
- allows product deletion when no product_option_types exist

**option_values -> option_types FK (restrict) (2 teste):**
- prevents option_type deletion when option_values exist
- allows option_type deletion when no option_values exist

**product_option_types -> option_types FK (restrict) (1 test):**
- prevents option_type deletion when product_option_types exist

**order_items -> variants FK (nullify) (1 test):**
- nullifies variant_id when variant is deleted (DB-level cu helper `insert_min_row!`)

---

## 10. spec/models/variant_schema_spec.rb (43 teste)

### Column Defaults & Nullability:

**variants table (5 teste):**
- has status with default 0
- has price with default 0
- has stock with default 0
- has sku as NOT NULL
- has product_id as NOT NULL

**variant_external_ids table (3 teste):**
- has source_account with default "default"
- has source as NOT NULL
- has external_id as NOT NULL

**order_items table (7 teste):**
- has variant_id as nullable
- has currency with default "RON"
- has variant_sku column
- has variant_options_text column
- has vat_rate_snapshot column
- has line_total_gross column
- has tax_amount column

### Index Existence:

**variants table (2 teste):**
- has idx_unique_sku_per_product index
- has status index

**option_value_variants table (3 teste):**
- has idx_unique_ovv index
- has idx_ovv_variant index
- has idx_ovv_option_value index

**product_option_types table (1 test):**
- has idx_unique_product_option_type index

**variant_external_ids table (3 teste):**
- has idx_unique_source_account_external_id index
- has idx_vei_variant index
- has idx_vei_source index

**order_items table (1 test):**
- has index on variant_id

**Postgres partial indexes (3 teste - postgres_only):**
- has idx_unique_active_default_variant partial index
- has idx_unique_active_options_per_product partial index
- has idx_unique_external_sku partial index

### Foreign Keys (9 teste):
- variants references products
- option_value_variants references variants
- option_value_variants references option_values
- variant_external_ids references variants
- product_option_types references products
- product_option_types references option_types
- option_values references option_types
- order_items references variants
- order_items.variant_id FK has on_delete: nullify

### CHECK Constraints (6 teste - postgres_only):
- has chk_variants_price_positive constraint
- has chk_variants_stock_positive constraint
- has chk_variants_status_enum constraint
- has chk_vei_source_format constraint
- has chk_vei_source_account_format constraint
- has chk_vei_external_id_not_empty constraint

---

## 11. spec/models/variant_unique_indexes_spec.rb (12 teste)

**idx_unique_sku_per_product (2 teste):**
- prevents duplicate SKU within same product
- allows same SKU on different products

**idx_unique_ovv (2 teste):**
- prevents duplicate option_value per variant
- allows same option_value on different variants

**idx_unique_product_option_type (2 teste):**
- prevents duplicate option_type per product
- allows same option_type on different products

**idx_unique_source_account_external_id (3 teste):**
- prevents duplicate external_id per source+account
- allows same external_id on different source_accounts
- allows same external_id on different sources

**option_types.name unique index (1 test):**
- prevents duplicate option_type names

**option_values unique per option_type (2 teste):**
- prevents duplicate names within same option_type
- allows same name in different option_types

---

## 12. spec/models/variant_isolation_spec.rb (5 teste)

**Variant update isolation from Product (4 teste):**
- updating price/stock does NOT touch product.updated_at
- updating price/stock does NOT query products table for UPDATE
- changing variant status does NOT touch product
- adding option_values to variant does NOT touch product

**Product accessing variants (1 test):**
- reading product.variants does NOT modify product

---

## TOTAL FAZA 1: 162 teste, 0 failures

**Verificare aritmetica per fisier:**

| # | Spec file | Teste FAZA 1 |
|---|-----------|-------------|
| 1 | option_type_spec.rb | 5 |
| 2 | option_value_spec.rb | 6 |
| 3 | option_value_variant_spec.rb | 3 |
| 4 | product_option_type_spec.rb | 3 |
| 5 | variant_spec.rb | 17 |
| 6 | variant_external_id_spec.rb | 16 |
| 7 | product_spec.rb | 11 |
| 8 | variant_db_constraints_spec.rb | 29 |
| 9 | variant_fk_constraints_spec.rb | 12 |
| 10 | variant_schema_spec.rb | 43 |
| 11 | variant_unique_indexes_spec.rb | 12 |
| 12 | variant_isolation_spec.rb | 5 |
| | **TOTAL** | **162** |

**Breakdown pe categorii:**
- 61 teste model (validari + asocieri + business logic)
- 96 teste schema (columns, indexes, FK, CHECK constraints enforcement)
- 5 teste isolation (V->P)

**Nota:** Fisierele variant_external_id_spec.rb si product_spec.rb contin acum 20 respectiv 16 teste (dupa adaugarile din FAZA 3). Cele 9 teste adaugate in FAZA 3 sunt contabilizate in FAZA 3, nu aici.

**Status:** FAZA 1 100% COMPLETA

# Solidus — Schema Completă a Bazei de Date

Toate tabelele Solidus au prefixul `spree_`. Mai jos sunt organizate pe module funcționale, cu coloanele cheie și echivalentul din AG1.

---

## Legendă

- **PK** = Primary Key
- **FK** = Foreign Key
- **AG1** = echivalentul din proiectul ag1/ayus.ro
- ❌ = nu există echivalent în AG1
- ✅ = există echivalent direct
- 🔶 = echivalent parțial

---

## 1. PRODUSE

### `spree_products` ✅ → `products`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| name | string | name | |
| description | text | description | |
| slug | string | slug | URL-friendly |
| meta_title | string | meta_title | SEO |
| meta_description | string | meta_description | SEO |
| meta_keywords | string | keywords | |
| available_on | datetime | ❌ | AG1 nu are programare publicare |
| discontinue_on | datetime | ❌ | AG1 nu are discontinuare automată |
| promotionable | boolean | coupon_applicable | Echivalent |
| status | string | ❌ | AG1 folosește vizibilitate pe variante |
| created_at | datetime | created_at | |
| updated_at | datetime | updated_at | |

**Ce are AG1 în plus pe `products`:**
- `price`, `discount_price`, `cost_price` — prețuri direct pe produs (Solidus le pune pe variante)
- `stock` — stoc direct pe produs
- `sku` — SKU direct pe produs
- `vat_rate` — TVA direct pe produs
- `delivery_method` — tip livrare (shipping/digital/download/external_link)
- `requires_login`, `visible_to_guests` — vizibilitate
- `external_image_url` — CDN
- `custom_attributes` — JSONB flexibil

---

### `spree_variants` ✅ → `variants`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| product_id | FK | product_id | |
| sku | string | sku | |
| weight | decimal | ❌ | AG1 nu are greutate |
| height | decimal | ❌ | |
| width | decimal | ❌ | |
| depth | decimal | ❌ | |
| position | integer | ❌ | |
| is_master | boolean | ❌ | AG1 nu are concept de master variant |
| track_inventory | boolean | ❌ | AG1 urmărește mereu stocul |
| cost_price | decimal | cost_price | |
| cost_currency | string | ❌ | AG1 e doar RON |
| created_at | datetime | created_at | |
| updated_at | datetime | updated_at | |

**Ce are AG1 în plus pe `variants`:**
- `price`, `discount_price` — prețuri direct pe variantă
- `stock` — stoc direct pe variantă
- `active` — status explicit
- `options_digest` — SHA256 hash al combinației de opțiuni (unicitate)
- `lock_version` — optimistic locking

**Diferență cheie**: Solidus are **obligatoriu** un "master variant" per produs. AG1 permite produse fără variante.

---

### `spree_prices` ❌ (AG1 nu are tabel separat)

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| variant_id | FK | |
| amount | decimal | Prețul |
| currency | string | Multi-currency! |
| country_iso | string | Preț per țară |
| created_at | datetime | |
| updated_at | datetime | |

**În AG1**: prețurile sunt coloane directe pe `products` și `variants` (`price`, `discount_price`). Simplu dar fără multi-currency.

---

### `spree_option_types` ✅ → `option_types`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| name | string | name | ex: "color", "size" |
| presentation | string | presentation | ex: "Culoare", "Mărime" |
| position | integer | position | |
| created_at | datetime | created_at | |
| updated_at | datetime | updated_at | |

---

### `spree_option_values` ✅ → `option_values`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| option_type_id | FK | option_type_id | |
| name | string | name | ex: "red" |
| presentation | string | presentation | ex: "Roșu" |
| position | integer | position | |

---

### `spree_option_values_variants` ✅ → `option_value_variants`

Join table: leagă variante de valorile lor de opțiuni.

| Coloană Solidus | Echivalent AG1 |
|----------------|---------------|
| variant_id | variant_id |
| option_value_id | option_value_id |

---

### `spree_product_option_types` ✅ → `product_option_types`

| Coloană Solidus | Echivalent AG1 | Note |
|----------------|---------------|------|
| product_id | product_id | |
| option_type_id | option_type_id | |
| position | position | |
| — | primary | AG1 are flag `primary` (lipsește în Solidus) |

---

### `spree_variant_external_ids` ❌ (Solidus nu are)

**Doar AG1** — sincronizare multi-platformă:

| Coloană AG1 | Tip | Note |
|------------|-----|------|
| variant_id | FK | |
| source | string | ex: "shopify", "emag" |
| source_account | string | Cont pe platformă |
| external_id | string | ID-ul pe platforma externă |

---

## 2. TAXONOMIE & CATEGORII

### `spree_taxonomies` ❌ (AG1 nu are)

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| name | string | ex: "Categorii", "Brand-uri" |
| position | integer | |

**Arbore ierarhic**. O taxonomie = un arbore. AG1 are structură plată.

---

### `spree_taxons` 🔶 → `categories`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| taxonomy_id | FK | ❌ | AG1 nu are taxonomii |
| parent_id | FK | ❌ | AG1 nu are ierarhie |
| name | string | name | |
| permalink | string | slug | |
| description | text | description | |
| meta_title | string | meta_title | |
| meta_description | string | meta_description | |
| meta_keywords | string | ❌ | |
| lft | integer | ❌ | Nested set (arbore) |
| rgt | integer | ❌ | Nested set (arbore) |
| position | integer | ❌ | |
| depth | integer | ❌ | Nivel în arbore |

**Diferență cheie**: Solidus folosește **nested set** (arbore ierarhic nelimitat: Categorii > Electronice > Telefoane > Samsung). AG1 are categorii plate, fără sub-categorii.

---

### `spree_products_taxons` ✅ → `categories_products`

Join table produse ↔ categorii. Identic conceptual.

---

## 3. STOC & INVENTAR

### `spree_stock_locations` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| name | string | ex: "Depozit București", "Depozit Cluj" |
| address1 | string | Adresa depozitului |
| city | string | |
| state_id | FK | |
| country_id | FK | |
| active | boolean | |
| default | boolean | Depozitul principal |
| backorderable_default | boolean | Permite backorder |
| propagate_all_variants | boolean | |

**AG1 nu are multi-depozit**. Stocul e direct pe produs/variantă.

---

### `spree_stock_items` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| stock_location_id | FK | Care depozit |
| variant_id | FK | Care variantă |
| count_on_hand | integer | Stoc disponibil |
| backorderable | boolean | Permite comenzi peste stoc |

**AG1 echivalent**: câmpul `stock` direct pe `products` și `variants`.

---

### `spree_stock_movements` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| stock_item_id | FK | |
| quantity | integer | +/- |
| action | string | Motiv (received, sold, adjustment) |
| originator_type | string | Polymorphic — ce a cauzat mișcarea |
| originator_id | integer | |

**Audit trail complet al stocului**. AG1 doar decrementează direct — fără istoric.

---

## 4. COMENZI

### `spree_orders` ✅ → `orders`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| number | string | ❌ | AG1 nu are număr order vizibil |
| state | string | status | Solidus: cart/address/delivery/payment/confirm/complete |
| user_id | FK | user_id | |
| email | string | email | |
| item_total | decimal | ❌ | Calculat în AG1 |
| total | decimal | total | |
| adjustment_total | decimal | discount_amount | |
| payment_total | decimal | ❌ | |
| shipment_total | decimal | shipping_cost | |
| promo_total | decimal | ❌ | |
| item_count | integer | ❌ | |
| currency | string | currency | |
| completed_at | datetime | ❌ | |
| bill_address_id | FK | ❌ (inline) | AG1 are adresa direct pe order |
| ship_address_id | FK | ❌ (inline) | AG1 are adresa direct pe order |
| payment_state | string | ❌ | |
| shipment_state | string | ❌ | |
| token | string | ❌ | Guest checkout token |
| channel | string | ❌ | Multi-canal |
| canceled_at | datetime | ❌ | |
| canceler_id | FK | ❌ | |
| approver_id | FK | ❌ | |
| approved_at | datetime | ❌ | |

**Solidus** are state machine complex cu stări separate pentru payment și shipment. **AG1** are un singur `status` liniar.

**Ce are AG1 direct pe order (inline):**
- `first_name`, `last_name`, `phone`
- `address`, `city`, `county`, `postal_code`, `country`
- `shipping_first_name`, `shipping_last_name`, `shipping_address`, etc.
- `coupon_code`, `discount_amount`, `discount_type`
- `notes`

---

### `spree_line_items` ✅ → `order_items`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| order_id | FK | order_id | |
| variant_id | FK | variant_id | |
| quantity | integer | quantity | |
| price | decimal | price | |
| cost_price | decimal | ❌ | |
| currency | string | ❌ | |
| adjustment_total | decimal | ❌ | |
| promo_total | decimal | ❌ | |
| additional_tax_total | decimal | ❌ | |
| included_tax_total | decimal | vat_amount | |

**Ce are AG1 în plus pe `order_items`:**
- `product_name` — snapshot la momentul comenzii
- `vat_rate` — rata TVA snapshot
- `variant_options` — opțiunile variantei (snapshot)

---

### `spree_adjustments` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| adjustable_type | string | Polymorphic (Order, LineItem, Shipment) |
| adjustable_id | integer | |
| source_type | string | Ce a generat adjustment-ul (Promotion, TaxRate, etc.) |
| source_id | integer | |
| amount | decimal | Suma (+/-) |
| label | string | |
| eligible | boolean | |
| finalized | boolean | |

**Sistem generic de ajustări** — acoperă discounturi, taxe, shipping adjustments. AG1 nu are acest concept — totul e calculat direct.

---

## 5. ADRESE & GEOGRAFIE

### `spree_addresses` ❌ (AG1 are inline pe order)

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | Refolosibil! |
| firstname | string | |
| lastname | string | |
| address1 | string | |
| address2 | string | |
| city | string | |
| zipcode | string | |
| phone | string | |
| state_id | FK | |
| country_id | FK | |
| company | string | |

**Avantaj Solidus**: adresele sunt obiecte separate, refolosibile (adresa de acasă, de birou). AG1 le duplică pe fiecare order.

---

### `spree_countries` 🔶 → `taris`

| Coloană Solidus | Tip | Echivalent AG1 |
|----------------|-----|---------------|
| id | PK | id |
| iso_name | string | ❌ |
| iso | string(2) | ❌ |
| iso3 | string(3) | ❌ |
| name | string | name |
| numcode | integer | ❌ |

---

### `spree_states` 🔶 → `judets`

| Coloană Solidus | Tip | Echivalent AG1 |
|----------------|-----|---------------|
| id | PK | id |
| name | string | name |
| abbr | string | ❌ |
| country_id | FK | tara_id |

---

### `spree_cities` ❌ (Solidus nu are nativ!)

AG1 are `localitatis` — Solidus **nu** are tabel de localități. Avantaj AG1 pentru România.

---

## 6. ZONE & TAXE

### `spree_zones` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| name | string | ex: "EU", "România", "Non-EU" |
| description | string | |
| zone_members_count | integer | |
| default_tax | boolean | |

---

### `spree_zone_members` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| zone_id | FK | |
| zoneable_type | string | Country sau State |
| zoneable_id | integer | |

O zonă conține țări sau state. Permite reguli diferite per regiune.

---

### `spree_tax_categories` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| name | string | ex: "TVA Standard", "TVA Redus", "Scutit" |
| is_default | boolean | |
| tax_code | string | |

---

### `spree_tax_rates` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| zone_id | FK | Se aplică în ce zonă |
| tax_category_id | FK | Pentru ce categorie de taxe |
| amount | decimal | ex: 0.19 (19% TVA) |
| name | string | |
| included_in_price | boolean | TVA inclus sau adăugat |
| show_rate_in_label | boolean | |

**AG1 echivalent**: câmpul `vat_rate` direct pe `products`/`variants`. Simplu dar nu permite zone multiple sau rate diferite per regiune.

---

## 7. LIVRARE (SHIPPING)

### `spree_shipping_methods` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| name | string | ex: "Standard", "Express", "Curier" |
| code | string | |
| tracking_url | string | URL tracking cu placeholder |

---

### `spree_shipping_categories` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| name | string | ex: "Normal", "Fragil", "Frigorific" |

---

### `spree_shipping_rates` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| shipment_id | FK | |
| shipping_method_id | FK | |
| cost | decimal | Cost calculat |
| selected | boolean | |

---

### `spree_shipments` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| order_id | FK | |
| number | string | ex: "H12345" |
| state | string | pending/ready/shipped/canceled |
| tracking | string | Număr AWB |
| shipped_at | datetime | |
| cost | decimal | |
| stock_location_id | FK | Din care depozit |

**AG1**: livrarea e simplificată — `delivery_method` pe produs, `shipping_cost` pe order. Fără shipments separate, fără tracking AWB, fără rate calculator.

---

## 8. PLĂȚI

### `spree_payment_methods` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| type | string | STI: `Spree::PaymentMethod::CreditCard`, `::Check`, etc. |
| name | string | ex: "Stripe", "PayPal" |
| preferences | text | Configurare gateway (chei API, etc.) |
| active | boolean | |
| auto_capture | boolean | Captură automată vs manuală |

---

### `spree_payments` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| order_id | FK | |
| payment_method_id | FK | |
| source_type | string | Polymorphic (CreditCard, etc.) |
| source_id | integer | |
| amount | decimal | |
| state | string | checkout/pending/completed/failed/void |
| response_code | string | De la gateway |
| avs_response | string | Address Verification |
| number | string | |

---

### `spree_credit_cards` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| user_id | FK | |
| gateway_customer_profile_id | string | Token Stripe/PayPal |
| gateway_payment_profile_id | string | |
| cc_type | string | visa/mastercard/etc. |
| last_digits | string | Ultimele 4 cifre |
| month | integer | |
| year | integer | |
| name | string | Numele de pe card |
| default | boolean | Card implicit |

**AG1**: doar Stripe Checkout Sessions — fără carduri salvate, fără multiple payment methods.

---

### `spree_store_credits` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| user_id | FK | |
| amount | decimal | Credit disponibil |
| amount_used | decimal | |
| category_id | FK | |
| type_id | FK | |
| currency | string | |
| memo | text | |

**AG1**: nu are store credit.

---

### `spree_refunds` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| payment_id | FK | |
| amount | decimal | |
| transaction_id | string | |
| reason_id | FK | |

---

### `spree_reimbursements` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| order_id | FK | |
| total | decimal | |
| number | string | |
| reimbursement_status | string | |

**Solidus** are workflow complet de rambursare: Reimbursement → Refund → Payment reversal. **AG1** doar loghează webhook-ul `charge.refunded`.

---

## 9. PROMOȚII

### `spree_promotions` 🔶 → `coupons`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| name | string | code | |
| description | text | ❌ | |
| starts_at | datetime | starts_at | |
| expires_at | datetime | expires_at | |
| usage_limit | integer | usage_limit | |
| match_policy | string | ❌ | "all" sau "any" din reguli |
| code | string | code | |
| advertise | boolean | ❌ | |
| path | string | ❌ | URL-triggered promo |
| per_code_usage_limit | integer | ❌ | |

---

### `spree_promotion_rules` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| promotion_id | FK | |
| type | string | STI: `FirstOrder`, `ItemTotal`, `Product`, `User`, `UserGroup`, etc. |
| preferences | text | Configurare regulă |

**Tipuri de reguli Solidus** (fiecare e o clasă Ruby):
- `Spree::Promotion::Rules::FirstOrder` — doar prima comandă
- `Spree::Promotion::Rules::ItemTotal` — valoare minimă coș ≈ AG1 `minimum_cart_value`
- `Spree::Promotion::Rules::Product` — produse specifice ≈ AG1 `product_id`
- `Spree::Promotion::Rules::User` — utilizatori specifici
- `Spree::Promotion::Rules::UserGroup` — grupuri de utilizatori
- `Spree::Promotion::Rules::Taxon` — categorii specifice
- `Spree::Promotion::Rules::OptionValue` — variante cu anumite opțiuni

---

### `spree_promotion_actions` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| promotion_id | FK | |
| type | string | STI: `CreateAdjustment`, `CreateItemAdjustments`, `FreeShipping`, etc. |
| preferences | text | |

**Tipuri de acțiuni Solidus**:
- `CreateAdjustment` — discount pe order total ≈ AG1 `discount_type: "fixed"`
- `CreateItemAdjustments` — discount per item
- `FreeShipping` — livrare gratuită ≈ AG1 `free_shipping: true`

---

### `spree_promotion_codes` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| promotion_id | FK | |
| value | string | Codul efectiv |

O promoție Solidus poate avea **multiple coduri**. AG1 are 1 cod per cupon.

---

## 10. UTILIZATORI & AUTENTIFICARE

### `spree_users` ✅ → `users`

| Coloană Solidus | Tip | Echivalent AG1 | Note |
|----------------|-----|---------------|------|
| id | PK | id | |
| email | string | email | |
| encrypted_password | string | encrypted_password | Devise |
| sign_in_count | integer | sign_in_count | |
| last_sign_in_at | datetime | last_sign_in_at | |
| current_sign_in_ip | inet | current_sign_in_ip | |
| last_sign_in_ip | inet | last_sign_in_ip | |
| ship_address_id | FK | ❌ | Adresă livrare implicită |
| bill_address_id | FK | ❌ | Adresă facturare implicită |

**AG1 în plus**: `role` (0/1), `active`, `first_name`, `last_name`, `phone`.

---

### `spree_roles` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| name | string | ex: "admin", "user" |

---

### `spree_roles_users` ❌

Join table: un user poate avea **multiple roluri**. AG1 are doar `role` integer (0=user, 1=admin).

---

## 11. MAGAZIN (STORE)

### `spree_stores` ❌

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| name | string | Numele magazinului |
| url | string | Domeniul |
| mail_from_address | string | |
| default_currency | string | |
| code | string | Identificator unic |
| default | boolean | |
| seo_title | string | |
| meta_description | string | |
| meta_keywords | string | |
| supported_currencies | string | Lista monedelor suportate |
| supported_locales | string | |
| default_locale | string | |
| checkout_zone_id | FK | |

**Multi-store nativ**. AG1 e single-store (ayus.ro).

---

## 12. FACTURI

### Nu există nativ în Solidus ❌ → AG1 `invoices`

AG1 are nativ:

| Coloană AG1 | Tip | Note |
|------------|-----|------|
| id | PK | |
| order_id | FK | |
| invoice_number | integer | Auto-increment de la 10001 |
| series | string | ex: "AYG" |
| total_amount | decimal | |
| vat_amount | decimal | |
| payment_method | string | |
| due_date | date | |
| currency | string | Default RON |

**Avantaj clar AG1** — facturare conformă RO out-of-the-box.

---

## 13. IMAGINI & ATAȘAMENTE

### `spree_assets` / `spree_images` 🔶 → ActiveStorage

| Coloană Solidus | Tip | Note |
|----------------|-----|------|
| id | PK | |
| viewable_type | string | Polymorphic (Variant) |
| viewable_id | integer | |
| attachment_file_name | string | Paperclip legacy |
| position | integer | |
| alt | string | Alt text |
| type | string | STI: Image, File |

**AG1**: folosește ActiveStorage + `external_image_url` pentru BunnyCDN. Mai modern.

---

## 14. ALTE TABELE SOLIDUS

### `spree_log_entries` ❌
Loguri de payment gateway (request/response). AG1 nu are.

### `spree_return_authorizations` ❌
Autorizări de retur. AG1 nu are workflow de retururi.

### `spree_return_items` ❌
Items individuale în retur.

### `spree_customer_returns` ❌
Retururi primite de la clienți.

### `spree_inventory_units` ❌
Unități individuale de inventar per line_item per shipment.

### `spree_state_changes` ❌
Audit trail al schimbărilor de stare pe orders/payments/shipments.

### `spree_store_credit_events` ❌
Istoric al mișcărilor de store credit.

### `spree_wallet_payment_sources` ❌
Surse de plată salvate per user (wallet).

### `spree_cartons` ❌
Colete fizice (un shipment poate avea mai multe colete).

### `spree_preferences` ❌
Configurări key-value ale engine-ului.

---

## SUMAR: Număr de tabele per modul

| Modul | Solidus | AG1 | Diferență |
|-------|---------|-----|-----------|
| **Produse & Variante** | 7 | 6 | AG1 are `variant_external_ids` |
| **Categorii** | 3 | 2 | Solidus are taxonomii ierarhice |
| **Stoc & Inventar** | 4 | 0 (câmpuri) | Solidus: multi-depozit + audit |
| **Comenzi** | 3 | 2 | Solidus: adjustments generice |
| **Adrese & Geo** | 3 | 3 | AG1 are localități, Solidus nu |
| **Zone & Taxe** | 4 | 0 (câmpuri) | Solidus: zone geografice + rate |
| **Livrare** | 4 | 0 (câmpuri) | Solidus: shipments, rates, tracking |
| **Plăți** | 6 | 0 (Stripe direct) | Solidus: multi-gateway, store credit |
| **Promoții** | 4 | 1 | Solidus: engine complex |
| **Utilizatori** | 3 | 1 | Solidus: roluri multiple |
| **Magazin** | 1 | 0 | Solidus: multi-store |
| **Facturi** | 0 | 1 | AG1: facturare nativă |
| **Altele** | ~10 | 3 | Retururi, audit, wallet, etc. |
| **TOTAL** | **~52** | **~19** | Solidus are ~2.7x mai multe tabele |

---

## DIAGRAMĂ RELAȚII CHEIE SOLIDUS

```
spree_stores
    │
    ├── spree_orders ──────────────────────┐
    │       ├── spree_line_items           │
    │       │       └── spree_variants     │
    │       │               ├── spree_prices (multi-currency)
    │       │               ├── spree_option_values_variants
    │       │               │       └── spree_option_values
    │       │               │               └── spree_option_types
    │       │               ├── spree_stock_items
    │       │               │       └── spree_stock_locations
    │       │               └── spree_images
    │       │
    │       ├── spree_payments             │
    │       │       ├── spree_payment_methods
    │       │       └── spree_refunds      │
    │       │                              │
    │       ├── spree_shipments            │
    │       │       ├── spree_shipping_rates│
    │       │       │       └── spree_shipping_methods
    │       │       └── spree_stock_locations
    │       │                              │
    │       ├── spree_adjustments          │
    │       │       └── (promotions, tax_rates)
    │       │                              │
    │       └── spree_addresses ───────────┘
    │               ├── spree_countries
    │               └── spree_states
    │
    └── spree_products
            ├── spree_variants (is_master=true → master)
            ├── spree_product_option_types
            │       └── spree_option_types
            └── spree_products_taxons
                    └── spree_taxons
                            └── spree_taxonomies
```

---

## CONCLUZIE SCHEMA

**Solidus** = ~52 tabele, relații complexe, totul normalizat, multi-everything.
**AG1** = ~19 tabele, denormalizat pragmatic, direct și ușor de înțeles.

Cu fișierele MVC scoase din engine, poți naviga și modifica orice model Solidus la fel de ușor ca în AG1. Diferența e doar de **volum** (mai multe tabele de învățat), nu de **accesibilitate**.

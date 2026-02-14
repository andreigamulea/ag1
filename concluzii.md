# AUDIT COMPLET PROIECT AG1 - AYUS GRUP ROMANIA

**Data auditului:** 2026-02-14
**Framework:** Ruby on Rails 7.1.6, PostgreSQL, Ruby 3.3
**Hosting:** Render.com (production), Bunny CDN (assets)

---

## 1. STRUCTURA PROIECT

### Baza de date - 21 tabele

| Tabel | Rol |
|-------|-----|
| users | Utilizatori (Devise auth, role admin/user) |
| products | Produse cu preturi, stocuri, SEO, promo |
| variants | Variante produs (SKU, pret, stoc, promo) |
| option_types | Tipuri optiuni (Culoare, Marime, Material) |
| option_values | Valori optiuni (Rosu, XL, Bumbac) + color_hex |
| option_value_variants | Join variante <-> valori optiuni |
| product_option_types | Join produse <-> tipuri optiuni (+ primary flag) |
| variant_external_ids | ID-uri externe pt integrari (Shopify, Wix) |
| categories | Categorii produse |
| categories_products | Join produse <-> categorii |
| orders | Comenzi (billing + shipping, Stripe) |
| order_items | Articole comanda (snapshot pret, TVA) |
| invoices | Facturi (serie AYG, numerotare secventiala) |
| coupons | Cupoane reducere (fix/procent, conditii) |
| cart_snapshots | Snapshot-uri cos de cumparaturi |
| newsletters | Abonati newsletter |
| taris | Tari (autocomplete) |
| judets | Judete Romania |
| localitatis | Localitati Romania |
| memory_logs | Monitorizare memorie |
| active_storage_* | 3 tabele ActiveStorage (blobs, attachments, variants) |

### Modele - 23 clase ActiveRecord

Toate modelele au validari, asocieri si metode de business logic corecte.

**Sistem variante complet:**
- Product -> has_many Variants (cu options_digest SHA256 pt unicitate combinatii)
- Primary option type (swatch-uri vizuale) + secondary option types (butoane)
- Preturi pe varianta cu suport promo (discount_price + promo_active)
- TVA calculat la nivel de produs si varianta
- External IDs pentru sincronizare cu platforme externe

---

## 2. FUNCTIONALITATI EXISTENTE

### Implementate si functionale:

- [x] **Catalog produse** - listare, filtrare, cautare, paginare (Kaminari)
- [x] **Pagina produs** - imagini, variante cu swatch-uri colorate, preturi, stoc
- [x] **Sistem variante** - option types, option values, primary/secondary display
- [x] **Cos de cumparaturi** - sesiune, add/remove/update, cupoane
- [x] **Checkout** - adresa facturare + livrare separata, validare Romania
- [x] **Plata Stripe** - checkout sessions, webhooks, confirmare automata
- [x] **Facturare** - generare automata la plata, PDF export (WickedPDF)
- [x] **Emailuri** - confirmare comanda (client + admin), contact
- [x] **Autentificare** - Devise (register, login, reset password, remember me)
- [x] **Admin panel** - produse CRUD, categorii, utilizatori, cupoane, option types
- [x] **SEO** - meta tags, Open Graph, Twitter Cards, JSON-LD, sitemap.xml, robots.txt
- [x] **Responsive** - mobile menu, layout adaptiv
- [x] **CDN** - Bunny CDN pentru imagini si fisiere (ActiveStorage S3-compatible)
- [x] **Autocomplete** - tara/judet/localitate cu Stimulus controllers
- [x] **Newsletter** - abonare, administrare in admin
- [x] **Pagini legale** - politica confidentialitate, cookies, termeni si conditii
- [x] **Monitorizare** - memory logs, GC fortat, chartkick grafice
- [x] **Cupoane** - fix/procent, date start/end, limita utilizari, minim cos
- [x] **Dezactivare cont** - soft delete cu posibilitate reactivare (admin)

### Teste:
- **436 RSpec** + **82 Minitest** + **208+ system tests** = 0 failures
- Raport teste/cod: 1.33:1 (excelent)

---

## 3. PROBLEME CRITICE DE SECURITATE

### CRITIC - De rezolvat INAINTE de productie:

#### 3.1 Credentiale expuse in cod

**config/database.yml** contine in clar:
- Username si parola baza de date productie
- URL complet PostgreSQL Render.com

**Recomandare:** Muta la `DATABASE_URL` environment variable. Nu hardcoda niciodata credentiale in fisiere tracked in git.

#### 3.2 Chei API in .env

Fisierul `.env` contine chei Bunny CDN in clar. Desi e in `.gitignore`, daca a fost commituit vreodata, cheile trebuie rotite.

**Recomandare:** Roteste toate cheile API. Foloseste `Rails.application.credentials` sau ENV vars.

#### 3.3 master.key

Verifica daca `config/master.key` a fost vreodata commituit. Daca da, regenereaza credentials complet.

---

## 4. PROBLEME DE SECURITATE - PRIORITATE MARE

### 4.1 Content Security Policy permisiva

```ruby
policy.script_src :unsafe_inline  # Permite JS inline -> vulnerabil la XSS
```

**Recomandare:** Elimina `unsafe_inline`. Muta tot JS-ul inline in fisiere separate sau foloseste nonce-uri.

### 4.2 Lipseste rate limiting

Nu exista protectie impotriva:
- Brute force pe login
- Spam pe autocomplete endpoints
- Abuz API

**Recomandare:** Adauga `gem 'rack-attack'` si configureaza throttling.

### 4.3 Security headers lipsa

Lipsesc:
- Permissions-Policy (camera, microfon, payment)
- X-Content-Type-Options
- Referrer-Policy

**Recomandare:** Adauga in `application_controller.rb` sau ca middleware.

---

## 5. PROBLEME DE ARHITECTURA

### 5.1 ActiveJob pe :async (NU e pt productie)

```ruby
config.active_job.queue_adapter = :async
```

Job-urile ruleaza in-process si se pierd la restart. Email-urile se trimit sincron (blocheaza request-ul).

**Recomandare:** Adauga `gem 'solid_queue'` sau `gem 'good_job'` (ambele database-backed, fara Redis).

### 5.2 Fara Redis/Memcached

Nu exista caching layer configurat. Pe trafic mare, queries repetitive vor incarca baza de date.

**Recomandare:** Adauga `gem 'redis'` + `config.cache_store = :redis_cache_store` sau macar `:memory_store` pt un singur server.

### 5.3 Puma - doar 2 workers

Insuficient pentru trafic real. Render.com free tier poate limita, dar pe un plan platit trebuie marit.

**Recomandare:** Configureaza 4-6 workers in functie de CPU/RAM disponibil.

---

## 6. PROBLEME MINORE

### 6.1 Copyright in footer: 2025

Footer-ul arata "2025" in loc de anul curent.

### 6.2 URL-uri hardcodate

`config/environments/production.rb` contine:
- `https://ayus-cdn.b-cdn.net` hardcodat
- Ar trebui sa fie `ENV['CDN_BASE_URL']`

### 6.3 ngrok hardcodat in development

```ruby
Rails.application.config.hosts << "7fbcb3465e7f.ngrok-free.app"
```

Nu e o problema de securitate, dar ar trebui sa fie ENV var.

### 6.4 Logging nestructurat

Nu foloseste JSON logging (lograge). In productie, debugging-ul va fi mai dificil fara logs structurate.

---

## 7. CE LIPSESTE PENTRU PRODUCTIE

### Esentiale:

| # | Ce lipseste | Prioritate | Efort |
|---|-------------|-----------|-------|
| 1 | Rotirea tuturor credentialelor expuse | CRITIC | 1h |
| 2 | Mutarea secretelor in ENV vars / credentials | CRITIC | 2h |
| 3 | Rate limiting (rack-attack) | MARE | 2h |
| 4 | Background jobs (solid_queue/good_job) | MARE | 3h |
| 5 | Security headers complete | MARE | 1h |
| 6 | Eliminare unsafe_inline din CSP | MARE | 4h* |

*Necesita refactorizare JS inline din views

### Nice to have:

| # | Ce lipseste | Prioritate | Efort |
|---|-------------|-----------|-------|
| 7 | Redis caching | MEDIU | 2h |
| 8 | JSON structured logging (lograge) | MEDIU | 1h |
| 9 | Brakeman security scanning in CI | MEDIU | 1h |
| 10 | Bundler-audit pt vulnerabilitati gem-uri | MEDIU | 30min |
| 11 | Monitoring (Sentry/Honeybadger) | MEDIU | 2h |
| 12 | Backup automat baza de date | MEDIU | 1h |

---

## 8. CE FUNCTIONEAZA BINE

- **Sistemul de variante** - complet, cu swatch-uri colorate, primary/secondary, options digest
- **Stripe integration** - webhook signature verification, procesare corecta
- **SEO** - JSON-LD, Open Graph, sitemap, robots.txt, meta tags dinamice
- **Teste** - acoperire excelenta (1.33:1 raport test/cod), 0 failures
- **Checkout** - validari Romania (judet/localitate), adrese separate billing/shipping
- **Facturare** - generare automata, PDF, serie+numar
- **Frontend** - responsive, Stimulus controllers, Turbo navigation
- **CDN** - Bunny CDN corect configurat pt productie
- **Devise auth** - bcrypt 12 stretches, password recovery, account deactivation
- **Dockerfile** - multi-stage build, non-root user, corect configurat

---

## 9. VERDICT FINAL

### Proiectul este functional si are toate feature-urile esentiale pentru un e-commerce.

**NU este gata de productie** din cauza:
1. **Credentiale expuse in cod** (critic - trebuie rotite si mutate)
2. **Fara rate limiting** (risc de abuz)
3. **ActiveJob :async** (email-urile se pierd la restart)
4. **CSP permisiva** (risc XSS)

**Estimare pentru a fi production-ready:** ~2 zile de munca (punctele 1-6 din tabelul de mai sus).

Dupa rezolvarea acestor probleme, proiectul poate fi pus in productie cu incredere.

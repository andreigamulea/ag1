deci ce nu s-a implementat?
Fata de PLAN_VARIANTE9.md/10.md, nu s-au implementat:

Component	De ce
M2 (Cleanup data)	Greenfield — nu ai date vechi de curatat
M5 (Backfill external_sku → variant_external_ids)	Nu ai date de migrat inca
Orders::ConcurrencyPolicy	Logica e in FinalizeService/RestockService direct
variant_sync_service_serialization_spec.rb	Test multi-thread fragil, PostgreSQL garanteaza serializarea
Primele doua (M2, M5) devin relevante cand vei importa date din surse externe (eMAG, ERP). Pana atunci nu au ce face — tabelele sunt goale.

Restul codului din plan e 100% implementat si deployed.

si cand o sa am un feed extern ce trebuie sa mai fac?
Cand ai un feed extern (eMAG, ERP, supplier), trebuie:

1. Migratie M5 (Backfill)
Daca ai deja produse cu external_sku pe variants, M5 le copiaza in variant_external_ids:


# Muta variants.external_sku → variant_external_ids cu source='legacy'
Variant.where.not(external_sku: nil).find_each do |v|
  VariantExternalId.create!(
    variant: v,
    source: 'legacy',
    source_account: 'default',
    external_id: v.external_sku
  )
end
2. Configurare feed import
Folosesti Imports::VariantSyncService care deja exista. Apelul arata asa:


service = Imports::VariantSyncService.new(
  source: 'emag',              # numele sursei
  source_account: 'emag_ro_1'  # contul specific
)

# Pentru fiecare produs din feed:
result = service.call(
  product: product,
  external_id: '12345',        # ID-ul din eMAG
  sku: 'EMAG-PROD-001',
  price: 99.90,
  stock: 15,
  option_values: { 'Culoare' => 'Rosu', 'Marime' => 'M' }
)
Serviciul se ocupa automat de:

Creare varianta noua sau reactivare existenta
Mapping external_id → variant in variant_external_ids
Advisory locks (anti-race condition)
Detectie product mismatch
3. Orders::ConcurrencyPolicy (optional)
Daca ai volum mare de comenzi simultane pe aceeasi varianta, implementezi policy-ul de concurenta. La volumul actual (Starter plan, 1 worker) nu e necesar.

Pe scurt
Cand	Ce faci
Ai feed eMAG/ERP	Scrii un job/rake task care apeleaza VariantSyncService.call per produs
Ai external_sku legacy	Creezi migratie M5 (backfill)
Ai volum mare concurrent	Implementezi ConcurrencyPolicy
Codul de baza (servicii, modele, constraints) e deja in productie si ready.

si fara feed nu putem face acum?
Poti folosi sistemul de variante chiar acum, fara feed extern. Ai doua optiuni:

1. Rails console (manual)

# Gaseste produsul
product = Product.find_by(name: 'Tricou')

# Defineste option types
culoare = OptionType.create!(name: 'culoare', presentation: 'Culoare')
marime = OptionType.create!(name: 'marime', presentation: 'Marime')

# Leaga option types de produs
ProductOptionType.create!(product: product, option_type: culoare)
ProductOptionType.create!(product: product, option_type: marime)

# Creeaza option values
rosu = OptionValue.create!(option_type: culoare, name: 'rosu', presentation: 'Rosu')
albastru = OptionValue.create!(option_type: culoare, name: 'albastru', presentation: 'Albastru')
m = OptionValue.create!(option_type: marime, name: 'm', presentation: 'M')
l = OptionValue.create!(option_type: marime, name: 'l', presentation: 'L')

# Creeaza variante cu serviciul
result = Variants::CreateOrReactivateService.new(product).call(
  sku: 'TRICOU-ROSU-M',
  price: 89.90,
  stock: 10,
  option_value_ids: [rosu.id, m.id]
)

result2 = Variants::CreateOrReactivateService.new(product).call(
  sku: 'TRICOU-ALBASTRU-L',
  price: 89.90,
  stock: 5,
  option_value_ids: [albastru.id, l.id]
)
2. Admin UI (nu exista inca)
Nu ai interfata admin pentru variante. Ar trebui sa construiesti:

Pagina admin unde adaugi/editezi variante per produs
Form cu dropdown-uri pentru culoare, marime, etc.
Tabel cu variantele existente, stoc, pret
Asta ar fi urmatorul pas logic daca vrei sa gestionezi variante fara feed.

Ce vrei sa faci?
Poti incepe cu Rails console pe Render Shell ca sa testezi pe un produs real, sau putem construi un admin UI.
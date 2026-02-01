# VARIANTS / INVARIANTE / LOCK ORDERING (Document de onboarding)

Acest document explică regulile conceptuale care fac sistemul de „variante” sigur într-un mediu cu concurență ridicată (admin + checkout + feed-uri externe), astfel încât un contributor nou să evite deadlock-uri, încălcări de invariante și bug-uri greu de reprodus.

Este intenționat orientat pe **de ce** (raționamente, contracte, riscuri), nu pe **cum** (implementare). Nu conține cod și nu propune refactorizări sau alternative.

---

## Cum să folosești acest document

- Citește o dată cap-coadă ca onboarding, apoi folosește-l ca referință când atingi Product/Variant, Order/Checkout sau feed-uri.
- Când te blochezi într-o decizie, începe de la: **ce invariantă trebuie protejată** și **ce lock-uri concurează**.
- Dacă un writer atinge mai mult de un domeniu, tratează-l ca risc ridicat și cere review de la cineva care cunoaște sistemul.

---

## Cuprins

- [0) Glosar și convenții](#0-glosar-și-convenții)
- [1) Context general](#1-context-general)
- [2) Invariante fundamentale (source of truth)](#2-invariante-fundamentale-source-of-truth)
- [3) Domenii și granițe](#3-domenii-și-granițe)
- [4) Lock Ordering – regula de aur](#4-lock-ordering--regula-de-aur)
- [5) Regula globală cross-domain: „V (Varianta) se lock-uiește ultima”](#5-regula-globală-cross-domain-v-varianta-se-lock-uiește-ultima)
- [6) Proof assumptions (de ce funcționează)](#6-proof-assumptions-de-ce-funcționează)
- [7) Greșeli comune pentru nou-veniți](#7-greșeli-comune-pentru-nou-veniți)
- [8) Cum să contribui în siguranță](#8-cum-să-contribui-în-siguranță)

---

## 0) Glosar și convenții

### Termeni cheie

- **Product**: entitatea de catalog care grupează variantele și regulile lor de prezentare.
- **Variant**: unitatea concretă vândută (combinație de opțiuni + stare + preț + stoc).
- **Combinație (de opțiuni)**: setul de atribute care diferențiază o variantă (ex: mărime/culoare). În sistem, această combinație are o reprezentare canonică (uneori numită „digest”).
- **Digest (al opțiunilor)**: identificator canonic al combinației de opțiuni, folosit pentru a detecta conflicte (două variante cu aceeași combinație).
- **Status**: starea unei variante din perspectiva catalogului (de regulă: activă vs inactivă).
- **Default**: varianta preselectată/implicită la nivel de produs (unde există această noțiune).
- **Completă (complete)**: variantă care are toate datele minime necesare pentru a fi vândută fără ambiguități (ex: preț prezent, stoc prezent, combinație validă, identificatori necesari). Termenul e intenționat conceptual: nu e „un câmp”, e un contract.
- **Cumpărabilă (buyable)**: variantă care, în acest moment, poate fi achiziționată în mod normal (de obicei: activă + completă + stoc disponibil > 0).
- **Checkout-permisă**: variantă acceptată de checkout pentru o cantitate cerută (de obicei: activă + stoc disponibil ≥ cantitatea cerută). E o definiție operațională: poate fi mai strictă sau mai relaxată decât „cumpărabil”.
- **Snapshot de comandă**: copia stabilă a informațiilor relevante (preț, monedă, identificatori, atribute) la momentul plasării comenzii, astfel încât istoricul să nu se rescrie.
- **Writer**: operație care modifică starea (catalog, comandă sau mapping-uri) și trebuie analizată pentru lock-uri și invariante.
- **Reader**: operație care citește și presupune că invarianta este adevărată (de exemplu, checkout-ul „se bazează pe” invarianta de stoc/preț).
- **Feed extern**: sursă de date din afara sistemului (ERP/marketplace/etc.) care poate crea/lega/actualiza variante.
- **External ID**: identificator venit dintr-o sursă externă, folosit pentru a potrivi o variantă internă cu o entitate externă.
- **Sursă / cont (source / source_account)**: dimensiuni care separă spațiile de identificatori externi (același external ID poate exista în surse diferite sau în conturi diferite).

### Convenții pentru secțiunea de lock-uri

În secțiunile despre lock ordering folosim abrevieri conceptuale:

- **A** = advisory lock (lock logic) pe o cheie externă (de ex. un external ID), folosit pentru coordonare între writer-e.
- **P** = lock pe Product (ancora domeniului de catalog).
- **V** = lock pe una sau mai multe variante.
- **O** = lock pe Order/Cart (ancora domeniului de checkout).
- **I** = lock pe liniile comenzii (order items).

Notă: abrevierile sunt doar o unealtă de comunicare; ideea importantă este **ordinea stabilă** în care sunt blocate resursele.

---

## 1) Context general

### 1.1 Ce problemă rezolvă sistemul de variante

„Varianta” este unitatea concretă care ajunge să fie vândută și livrată: combinația de opțiuni (mărime/culoare), starea de activare, disponibilitatea și prețul efectiv aplicabil. La nivel de produs, pot exista multiple variante, dar sistemul trebuie să ofere mereu:

- o reprezentare coerentă pentru client (ce se vede și ce se poate cumpăra);
- o reprezentare stabilă pentru comenzi (ce s-a cumpărat rămâne adevărat);
- o cale sigură de actualizare din mai multe surse (admin, feed-uri, automatizări).

### 1.2 Actori și fluxuri concurente

În practică, aceleași resurse (produse/variante) sunt atinse de fluxuri diferite, în paralel:

- **Admin**: creează/dezactivează/reactivează variante, schimbă preț/stoc, schimbă combinații de opțiuni, schimbă default.
- **Checkout**: validează și finalizează cumpărări (decide prețul, verifică eligibilitate, consumă stoc, scrie comanda).
- **Feed-uri externe**: sincronizează (uneori foarte des) preț/stoc și pot lega variante la identificatori externi; pot exista multiple surse și multiple conturi.

Aceste fluxuri rulează simultan sub load, în procese diferite, și concurează pe aceleași rânduri din baza de date.

### 1.3 De ce e dificil (și de ce „merge local” nu e relevant)

Dificultatea nu vine din „un update de preț” luat izolat, ci din suprapunerea operațiilor:

- aceeași variantă poate fi citită/rezervată în checkout în timp ce este modificată în admin;
- feed-uri multiple pot încerca să „corecteze” aceeași realitate, în momente diferite (și în ordine diferită);
- un produs poate avea operații paralele pe variante diferite, dar cu efecte comune (unicitate, default, agregări).

Într-un sistem concurent, „corect” înseamnă:

- să nu existe stări intermediare invalid-observabile (alt flux le poate vedea);
- să nu existe blocaje circulare (deadlock-uri) între writer-e;
- să existe o disciplină clară a priorităților (checkout e critical-path; feed-urile sunt best-effort).

### 1.4 Ce înseamnă „variantă” în acest sistem

Conceptual, o variantă are trei dimensiuni:

1) **Identitate**: aparține unui produs și are o combinație de opțiuni care o diferențiază.
2) **Comportament de business**: poate fi activă/inactivă, poate fi default, poate fi cumpărabilă sau nu.
3) **Interacțiune operațională**: poate fi ținta feed-urilor, poate fi folosită de checkout, și poate apărea în comenzi ca referință istorică.

Cele trei dimensiuni creează invariante. Dacă un contributor nou „schimbă ceva mic” într-o dimensiune fără să o vadă pe celelalte două, apare risc real de bug-uri de concurență.

### 1.5 Riscurile principale pe care le prevenim

Dacă păstrezi în minte „lista de dezastre”, devine mai ușor să recunoști când o schimbare aparent banală e de fapt high-risk:

- **Overselling**: checkout-ul finalizează mai multe comenzi decât permite stocul real.
- **Preț greșit**: clientul vede un preț, dar comanda finalizează cu altul, sau istoricul comenzilor se schimbă după un update de catalog.
- **Ambiguitate în catalog**: două variante active cu aceeași combinație sau două default-uri active pe același produs.
- **Matching extern nondeterminist**: același external ID ajunge să „însemne” două variante diferite în aceeași sursă/cont.
- **Deadlock-uri și timeouts**: writer-ele se blochează circular, iar baza de date întrerupe tranzacții exact când traficul e mare.

---

## 2) Invariante fundamentale (source of truth)

O invariantă este o regulă care trebuie să fie adevărată mereu (sau, mai pragmatic: la orice punct în care un reader critic poate observa starea). Invariantele există pentru că multe bug-uri „rare” sunt de fapt încălcări temporare ale acestor reguli sub concurență.

În această secțiune, „dacă se încalcă” nu înseamnă doar „ajunge la o valoare greșită”, ci include și situația în care sistemul trece printr-o stare invalidă suficient de mult încât un alt flux să o observe.

### 2.0 Cum să gândești invariantele într-un sistem concurent

- **Invariantele sunt contractul reader-elor.** Checkout-ul, de exemplu, ia decizii bazate pe faptul că „stocul nu poate fi depășit” și că „prețul folosit este coerent”.
- **Invariantele sunt mai importante decât ordinea intenționată a update-urilor.** Două update-uri perfect valide, dacă sunt intercalate greșit, pot produce un moment invalid.
- **O invariantă bună are un „de ce” clar.** Dacă nu poți explica ce catastrofă previne, de obicei nu e invariantă, ci preferință.

### 2.1 Invariante de combinatorică (opțiuni) și identitate

**Invariantă: pentru o combinație de opțiuni dată, există cel mult o variantă activă.**

- Protejează univocitatea: „varianta mărimea M / culoarea Negru” nu trebuie să fie ambiguă.
- Dacă se încalcă: clientul poate vedea duplicate, adminul poate modifica una crezând că e „cea corectă”, iar checkout-ul poate selecta nedeterminist una sau alta (în funcție de caching, ordinea rezultatelor sau timing).

**Invariantă: pot exista mai multe variante inactive/draft cu aceeași combinație, dar activarea trebuie să mențină univocitatea.**

- Protejează flexibilitatea operațională (poți pregăti o variantă nouă fără să „rupi” imediat catalogul).
- Dacă se încalcă: fie blochezi inutil operații legitime (nu mai poți pregăti draft-uri), fie permiți două active simultan (ambiguitate).

**Invariantă: combinația unei variante poate fi schimbată, dar nu într-un mod care produce conflict cu o variantă activă existentă.**

- Protejează faptul că „identitatea” unei variante nu este digest-ul; digest-ul este o proprietate care se poate schimba.
- Dacă se încalcă: ajungi la conflicte de univocitate sau la „teleportări” conceptuale (o variantă pare să devină alta, iar alte fluxuri o interpretează greșit).

**Invariantă: reprezentarea combinației (digest-ul) este canonică și calculată consistent.**

- Protejează detecția conflictelor. Dacă aceeași combinație poate fi reprezentată în două feluri, atunci două variante pot părea diferite când de fapt nu sunt.
- Dacă se încalcă: unicitatea „pare” respectată, dar în realitate ai duplicate semantice; bug-urile apar când interfețe diferite calculează diferit combinația.

### 2.2 Invariante de selecție (default) și stare (active/inactive)

**Invariantă: există cel mult o variantă default activă per produs.**

- Protejează experiența clientului (preselecție stabilă) și fluxurile interne care presupun un default unic.
- Dacă se încalcă: UI-ul poate oscila între două default-uri, caching-ul devine inconsistent, iar checkout-ul poate porni de la premise diferite între două cereri consecutive.

**Invariantă: „activ” nu este doar un flag; este un contract cu reader-ele.**

- Protejează așteptarea că o variantă activă este o candidată reală pentru a fi listată/aleasă.
- Dacă se încalcă: apar variante active dar „imposibil de vândut” din motive care nu sunt evidente (date lipsă, preț/stoc invalide), iar bug-urile se manifestă ca erori intermitente în UI/checkout.

### 2.3 Invariante de eligibilitate („cumpărabil” vs „checkout-permis”)

**Invariantă: „cumpărabil” are o definiție consistentă în tot sistemul.**

În mod tipic, o variantă este cumpărabilă dacă:

- este activă;
- este completă (are datele minime necesare);
- are stoc disponibil strict pozitiv.

- Protejează consistența între „ce afișăm” și „ce putem vinde”.
- Dacă se încalcă: poți afișa „în stoc” când nu este, sau poți ascunde variante care sunt de fapt vândabile.

**Invariantă: checkout-ul acceptă o variantă doar dacă poate garanta cantitatea cerută.**

Practic, checkout-ul trebuie să fie capabil să spună „da” sau „nu” pentru o cantitate, fără să se bazeze pe noroc. În mod tipic, condiția relevantă este stoc disponibil ≥ cantitatea cerută.

- Protejează împotriva overselling-ului și a eșecurilor târzii (după ce clientul a confirmat).
- Dacă se încalcă: comenzi care par valide la început, dar eșuează la finalizare; sau, mai rău, comenzi finalizate care nu pot fi onorate.

### 2.4 Invariante de stoc (disponibilitate și atomicitate)

**Invariantă: stocul nu poate fi depășit (checkout atomic).**

- Protejează promisiunea către client și previne overselling-ul.
- Dacă se încalcă: apar comenzi plasate care nu pot fi livrate, anulări, refund-uri, degradarea reputației și costuri operaționale.

**Invariantă: stocul și semantica lui sunt consistente (valoare prezentă, non-negativă).**

- Protejează calcule și decizii: „stoc lipsă” sau „stoc negativ” produce interpretări diferite în diverse componente.
- Dacă se încalcă: UI/checkout/feeds pot „repara” diferit aceleași date; apar bug-uri în lanț (de la afișare până la finalizare).

### 2.5 Invariante de preț (integritate business)

**Invariantă: prețul este întotdeauna prezent și non-negativ.**

- Protejează faptul că sistemul nu trebuie să ghicească ce înseamnă „preț lipsă” sau „preț negativ”.
- Dacă se încalcă: discount-uri/totaluri pot deveni absurde; apar erori de validare târzii; rapoarte devin incorecte.

**Invariantă: prețul prezentat și prețul folosit la plasarea comenzii sunt aliniate printr-o regulă stabilă.**

- Protejează încrederea și predictibilitatea (clientul nu vede un preț și plătește altul fără o cauză explicită).
- Dacă se încalcă: apar plăți la preț greșit, dispute, chargeback, sau costuri suport.

**Invariantă: comanda păstrează un snapshot al prețului (și al monedei) decis la momentul cumpărării.**

- Protejează contabilitatea și faptul că istoricul comenzilor nu se rescrie retroactiv.
- Dacă se încalcă: un update ulterior de preț ar schimba implicit trecutul; reconcilierea financiară devine fragilă.

### 2.6 Invariante de referință și istoricul comenzilor

**Invariantă: o variantă folosită într-o comandă rămâne interpretabilă în timp.**

Asta nu înseamnă neapărat că varianta nu se poate schimba în catalog, ci că:

- comanda păstrează snapshot-ul necesar;
- sistemul poate explica „ce s-a cumpărat” chiar dacă între timp catalogul s-a schimbat.

- Protejează suportul post-vânzare, retururile, și integritatea rapoartelor.
- Dacă se încalcă: „ce a cumpărat clientul” devine ambiguu; retururile nu pot fi procesate corect; audit-ul devine fragil.

### 2.7 Invariante pentru feed-uri externe (mapping + determinism)

**Invariantă: un external ID este unic în cadrul (sursă, cont).**

- Protejează faptul că „acest ID extern” se mapează determinist la o singură variantă internă în acel spațiu.
- Dacă se încalcă: același item din feed poate actualiza când una, când alta dintre două variante; rezultatul devine nondeterminist și greu de investigat.

**Invariantă: același external ID nu își schimbă produsul țintă.**

- Protejează împotriva feed-urilor/configurărilor care „reutilizează” ID-uri pentru entități diferite.
- Dacă se încalcă: actualizări legitime devin migrații implicite între produse; rezultatul este corupție de catalog (o variantă pare să „sară” la alt produs).

**Invariantă: update-urile din feed nu schimbă combinația de opțiuni; ele actualizează doar atribute operaționale (tipic: preț/stoc).**

- Protejează separația de responsabilitate: feed-ul descrie disponibilitate și preț, nu redefinește identitatea combinației.
- Dacă se încalcă: se rupe invarianta de unicitate pe combinații; apar situații în care feed-ul rescrie semnificația unei variante folosite de oameni în admin.

**Invariantă: feed-urile sunt tratate ca „at least once” și „out-of-order”, deci efectul trebuie să fie idempotent.**

- Protejează sistemul intern de reîncercări, duplicări și întârzieri.
- Dacă se încalcă: același eveniment aplicat de două ori produce dublări, drift, sau stări imposibile; bug-urile apar doar sub load sau incidente de integrare.

### 2.8 Permis vs interzis (în termeni de efect)

Permis (conceptual):

- să existe draft-uri/inactive multiple pentru aceeași combinație, atâta timp cât există cel mult una activă;
- să schimbi combinația unei variante, atâta timp cât nu creezi conflict cu o variantă activă;
- să rulezi operații paralele pe produse diferite sau pe domenii fără resurse comune;
- să actualizezi preț/stoc din feed în mod determinist și idempotent.

Interzis (conceptual):

- să existe simultan două variante active cu aceeași combinație;
- să existe simultan două default-uri active pe același produs;
- să permiți ca checkout-ul să observe o variantă „cumpărabilă” fără garanțiile asociate (preț/stoc coerente);
- să permiți ca un external ID să fie „re-atribuit” la alt produs;
- să creezi cicluri de lock-uri prin ordine inconsistentă între domenii.

### 2.9 Scenarii reprezentative (cum se manifestă concurența)

Scopul acestor scenarii este să te ajute să „simți” de ce invariantele sunt formulate așa și de ce lock ordering contează.

**Scenariul A: două operații administrative pe același produs**

Un developer își imaginează că „schimb o combinație” și „reactivez o variantă” sunt independente. În realitate, ambele pot converge către aceeași invariantă: unicitatea variantei active pentru o combinație. Dacă rulează simultan fără disciplină, e posibil ca pentru o perioadă scurtă să existe două active sau ca una să „calce” peste intenția celeilalte. Invarianta există tocmai ca să facă rezultatul determinist: la final există cel mult una activă pentru combinația respectivă.

**Scenariul B: checkout finalizează în timp ce feed-ul actualizează stocul**

Checkout-ul ia decizia „pot confirma cantitatea X?” în timp ce feed-ul primește o ajustare de stoc (de exemplu o corecție sau un import întârziat). Dacă stocul nu e protejat atomic, cele două operații pot interfera astfel încât checkout-ul să „vadă” o disponibilitate care nu mai e adevărată la final. De aici invarianta: stocul nu poate fi depășit, iar checkout-ul trebuie să aibă o decizie coerentă pentru cantitatea cerută.

**Scenariul C: două fluxuri încearcă să lege același external ID**

Poate fi două feed-uri, două instanțe ale aceluiași job, sau un admin care încearcă să corecteze un mapping. Dacă nu există o regulă de unicitate per (sursă, cont), rezultatul poate fi ambiguu: același external ID „arată” spre două variante diferite, iar un update ulterior va modifica când una, când alta. De aici apar două contracte: external ID unic în spațiul lui și advisory lock ca mecanism de coordonare pentru a preveni dubluri sub concurență.

**Scenariul D: operații care ating mai multe variante simultan**

Uneori o operație nu atinge o singură variantă, ci un set (de exemplu toate variantele unui produs sau mai multe variante dintr-o comandă). Două astfel de operații pot deadlock-ui chiar dacă ating același set, dacă ordinea de lock diferă. De aici regula „ordine deterministă” (de obicei după id): ea transformă conflictul dintr-un ciclu (deadlock) într-o simplă așteptare (una trece, cealaltă așteaptă).

**Scenariul E: prețul se schimbă după ce comanda a fost plasată**

Catalogul este o stare curentă și se schimbă. Comanda este istoric. Dacă o comandă ar „depinde” de prețul curent al variantei, atunci un update ulterior ar rescrie trecutul. De aici invarianta de snapshot: prețul (și moneda) folosite la cumpărare rămân atașate comenzii.

---

## 3) Domenii și granițe

Sistemul rămâne raționabil doar dacă păstrăm separația conceptuală dintre domenii. „Domeniu” înseamnă: set de entități și reguli care trebuie să fie coerente împreună.

### 3.1 Domeniul Product / Variant (catalog)

Responsabilități tipice:

- starea curentă a produsului și a variantelor (active/inactive, default, combinații);
- regulile de unicitate și interpretare a combinațiilor;
- datele curente folosite pentru listare (inclusiv eligibilitate).

Caracteristică: aici sunt multe operații administrative și de sincronizare, dar impactul lor se propagă către checkout prin faptul că checkout-ul citește catalogul.

### 3.2 Domeniul Order / Checkout

Responsabilități tipice:

- intenția de cumpărare (cart/order) și liniile ei;
- validări, consum/reservare de stoc, finalizare;
- snapshot-uri (preț, monedă, identitate/descriere variantă) pentru istoric.

Caracteristică: checkout-ul este **critical-path** (latență și consistență). El nu trebuie să „depindă” de stări intermediare de catalog.

### 3.3 Domeniul External Feeds (integrare)

Responsabilități tipice:

- potrivirea între lumea externă și entitățile interne (mapping external ID către o variantă);
- aplicarea deterministă a update-urilor (idempotent, robust la reordonare/duplicare);
- delimitarea clară a ce are voie să modifice un feed (de regulă: preț/stoc, nu identitate).

Caracteristică: feed-urile sunt best-effort și pot fi „zgomotoase”; sistemul intern trebuie să fie defensiv.

### 3.4 Ce se întâmplă dacă amesteci granițele

Simptomele clasice când granițele se rup:

- checkout-ul începe să depindă de stări volatile ale catalogului (și devine instabil);
- feed-urile încep să blocheze resurse din critical-path (și cresc latența sau rate-ul de erori);
- comenzile își pierd caracterul istoric (și trecutul se rescrie când se schimbă catalogul).

---

## 4) Lock Ordering – regula de aur

### 4.1 De ce lock-urile sunt inevitabile aici

Într-un sistem cu concurență ridicată, invariantele de mai sus nu pot fi garantate doar prin „ordinea în cod” sau prin „testare locală”. Ele au nevoie de o disciplină de acces exclusiv (lock) la resurse comune atunci când se scrie.

### 4.2 Tipuri de lock-uri (conceptual)

- **Row-level locks**: blocări pe rânduri (de exemplu pe un Product, o Variantă, un Order). Sunt mecanismul standard pentru a preveni scrieri concurente care ar încălca invarianta.
- **Advisory locks (A)**: blocări logice pe o cheie (de exemplu un external ID) pentru coordonarea writer-elor care altfel nu ar concura pe același rând, dar ar produce efecte conflictuale (dubluri, mapping-uri ambigue).

### 4.3 Ce este lock ordering

Lock ordering este o regulă de disciplină: când o operație are nevoie să blocheze mai multe resurse, o face mereu în aceeași ordine canonică. Scopul nu este „performanță”, ci **evitarea deadlock-urilor** și menținerea predictibilității sub concurență.

### 4.4 Ce este un deadlock (explicat simplu)

Un deadlock apare când două (sau mai multe) operații se blochează reciproc într-un ciclu:

- Operația A ține un lock pe resursa 1 și așteaptă resursa 2.
- Operația B ține un lock pe resursa 2 și așteaptă resursa 1.

În variante reale pot exista și cicluri de 3+ resurse (A așteaptă B, B așteaptă C, C așteaptă A).

Consecința practică: baza de date va întrerupe una dintre tranzacții. Pentru aplicație, asta înseamnă erori intermitente, retry-uri, latență crescută și comportament nondeterminist exact când ai trafic mare.

### 4.5 Ordinea canonică pentru domeniul produsului (catalog)

Regula conceptuală pentru writer-ele care operează în catalog:

1) Dacă operația depinde de un external ID (sau altă cheie externă care poate produce dubluri), ia mai întâi un **advisory lock (A)** pe cheia respectivă.
2) Ia lock pe **Product (P)** (ancora care stabilește „despre ce produs vorbim”).
3) Ia lock pe **variante (V)** implicate, întotdeauna într-o **ordine deterministă** (ex: crescător după id) dacă sunt mai multe.
4) Abia apoi atingi **resurse derivate** (de exemplu mapping-uri, agregări, alte entități dependente), astfel încât să nu creezi cicluri inversând ordinea.

Intuiție: product-ul este contextul. Dacă începi de la o variantă și abia apoi „urci” la product, concurezi cu fluxuri care pornesc de la product și coboră către variante; asta e sursă clasică de deadlock.

### 4.6 Ordinea canonică pentru domeniul comenzii (checkout)

Regula conceptuală pentru writer-ele care operează în checkout:

1) Ia lock pe **Order/Cart (O)** (ancora intenției de cumpărare).
2) Ia lock pe **liniile comenzii (I)**.
3) Ia lock pe **variantele (V)** implicate, din nou într-o **ordine deterministă** dacă sunt mai multe.

Intuiție: checkout-ul își stabilizează mai întâi intenția și structura comenzii, apoi consumă resurse externe comenzii (stoc/variante).

### 4.7 De ce e critică ordinea deterministă când blochezi mai multe variante

Chiar dacă două operații blochează același set de variante, ele pot deadlock-ui dacă le blochează în ordine diferită.

Exemplu narativ:

- Operația A blochează mai întâi varianta X, apoi varianta Y.
- Operația B blochează mai întâi varianta Y, apoi varianta X.

Dacă pornesc simultan, fiecare prinde primul lock și o așteaptă pe cealaltă. Rezultatul este un deadlock clasic.

De aceea, când ai mai multe variante, trebuie să existe o ordine canonică simplă (de obicei „după id”).

### 4.8 Scenarii tipice de deadlock (și cum să le recunoști)

Deadlock-ul nu este „o excepție ciudată”, ci rezultatul mecanic al unei ordini inconsistente de lock-uri. Câteva tipare care apar des:

**Tiparul 1: pornești de la Variantă, apoi urci la Product**

- Fluxul A: blochează varianta (pentru că „doar o modific”), apoi are nevoie să blocheze product-ul (pentru unicitate/default sau alte reguli la nivel de produs).
- Fluxul B: blochează product-ul (pentru o schimbare de catalog), apoi are nevoie să blocheze exact aceeași variantă.

Fiecare ține un lock și îl așteaptă pe celălalt: ciclu.

**Tiparul 2: două variante, două ordine**

Două operații ating aceleași două variante, dar în ordine diferită. Fiecare prinde prima variantă și o așteaptă pe cealaltă. Aici nu contează „intenția”, ci doar ordinea: fără o ordine deterministă, deadlock-ul este o chestiune de timp sub load.

**Tiparul 3: advisory lock luat târziu**

Un flux ia lock pe product/variant și abia apoi încearcă să ia advisory lock pe o cheie externă (de exemplu un external ID). În paralel, alt flux ia mai întâi advisory lock (A), apoi încearcă să ia product/variant. Rezultatul poate fi un ciclu între A și lock-urile de catalog.

Acesta este motivul pentru care ordinea canonică din catalog spune: dacă ai nevoie de A, îl iei primul.

---

## 5) Regula globală cross-domain: „V (Varianta) se lock-uiește ultima”

### 5.1 Ce spune regula (în termeni de intenție)

Când un writer traversează domenii (de exemplu, atinge și resurse din Order/Checkout și resurse din Product/Variant), **varianta** este tratată ca resursă „de capăt”: se blochează **ultimul**, după ce au fost stabilizate lock-urile de ancoră ale domeniilor implicate.

Această regulă există pentru că varianta este punctul comun cel mai frecvent între operații care pornesc din direcții diferite:

- admin/feeds pornesc dinspre catalog;
- checkout pornește dinspre comandă.

### 5.2 Ce este interzis (pentru că introduce cicluri)

- Să blochezi o variantă și apoi să blochezi product-ul (V înainte de P).
- Să blochezi o variantă și apoi să blochezi comanda/liniile ei (V înainte de O/I).
- Să blochezi multiple variante fără o ordine deterministă (ordine „aleatoare” din execuție).

Aceste tipare creează exact condițiile în care două fluxuri pot forma un ciclu: unul ține V și așteaptă P/O, iar altul ține P/O și așteaptă V.

### 5.3 Exemple narative (fără cod)

**Exemplu OK (catalog-only):**

Un flow de catalog pornește de la product, decide ce schimbă (default, activare, reguli de unicitate) și abia apoi blochează variantele relevante pentru a aplica schimbarea. Nu atinge comenzi. Ordinea este consistentă cu alte flow-uri de catalog, deci nu creează cicluri.

**Exemplu OK (order-only):**

Un flow de checkout pornește de la comandă, blochează liniile, validează cantități și apoi blochează variantele implicate (în ordine deterministă) pentru a consuma stoc. Nu ia lock pe product, deci nu intră în cicluri cu flow-urile de catalog.

**Exemplu periculos (cross-domain accidental):**

O operație pornește „doar să modifice” o variantă, ia lock pe ea, apoi își dă seama că trebuie să verifice și ceva legat de comenzi (sau să atingă product pentru unicitate/default). În același timp, un checkout pornește de la comandă și ajunge să aștepte aceeași variantă. Dacă fiecare ține deja un lock din domeniul lui, ciclul este probabil sub load.

---

## 6) Proof assumptions (de ce funcționează)

Acest design se bazează pe presupuneri de mediu și pe contracte între domenii. Nu sunt „opționale”: dacă se schimbă, logica de siguranță (invariante + lock ordering) poate deveni incompletă.

### 6.1 Presupunerea 1: isolation level este READ COMMITTED

Designul presupune isolation level **READ COMMITTED** (implicit în Postgres și, tipic, în aplicații Rails).

De ce contează:

- În READ COMMITTED, fiecare statement vede o fotografie (snapshot) a datelor la momentul statement-ului.
- Când trebuie blocate mai multe rânduri (de exemplu mai multe variante) într-o ordine deterministă, presupunem că acea ordine este respectată consecvent la achiziția lock-urilor.

Intuiție: dacă două tranzacții încearcă să blocheze același set de variante în aceeași ordine canonică, nu se poate forma un ciclu. Una va aștepta după cealaltă, dar nu vor ajunge să se aștepte reciproc.

Ce s-ar rupe dacă se schimbă:

- în REPEATABLE READ / SERIALIZABLE apar semantici suplimentare (recheck-uri, conflicte de serializare) care pot invalida presupunerile despre „cum” se obține aceeași ordine de lock-uri;
- chiar dacă multe lucruri ar continua să funcționeze, „proof”-ul devine incomplet: nu mai poți susține că ordinea de lock-uri e suficientă pentru absența deadlock-urilor în toate interleaving-urile relevante.

### 6.2 Presupunerea 2: toți writer-ii respectă aceeași disciplină de lock-uri

Lock ordering funcționează doar dacă este urmat de toate operațiile care concurează pe aceleași resurse. O singură excepție introdusă accidental poate reintroduce cicluri.

Ce s-ar rupe dacă se schimbă:

- deadlock-urile reapar (intermitent, de obicei doar sub load);
- retry-urile/timeouts cresc (și cresc concurența efectivă), ceea ce amplifică problema.

### 6.3 Presupunerea 3: domeniile rămân separate în scop și responsabilitate

Presupunem că:

- catalogul (Product/Variant) nu încearcă să finalizeze atomic decizii de checkout;
- checkout-ul nu tratează feed-urile ca adevăr perfect și instant;
- comenzile rămân record-uri istorice, nu o proiecție volatilă a catalogului.

Ce s-ar rupe dacă se schimbă:

- cross-domain devine „spaghete”: operații aparent simple ajung să blocheze resurse din multiple domenii;
- devine greu să raționezi despre invarianta și despre ordinea lock-urilor.

### 6.4 Presupunerea 4: feed-urile sunt imperfecte (și tratate ca atare)

Presupunem că:

- feed-urile pot retrimite aceeași informație (duplicări);
- feed-urile pot livra update-uri în altă ordine decât au fost generate (reordonare);
- feed-urile pot conține date inconsistente (ex: același external ID cu opțiuni diferite).

De aceea, contractul intern este: mapping determinist, idempotență și restricții clare asupra câmpurilor pe care un feed le poate modifica.

---

## 7) Greșeli comune pentru nou-veniți

### „Doar un update mic”

În sisteme concurente, „mic” nu descrie impactul. Un update mic poate:

- rupe unicitatea pe combinații (direct sau indirect);
- schimba cumpărabilitatea observată de checkout;
- intra în conflict cu un feed care rulează în paralel;
- schimba default-ul sau regulile de selecție fără să pară.

Întrebarea corectă nu este „cât e de mic?”, ci „ce invariante atinge și ce lock-uri concurează?”.

### „Am testat local și merge”

Majoritatea problemelor de concurență:

- apar rar (numai sub load);
- depind de timing (interleaving-uri diferite);
- dispar la debugging/logging suplimentar (pentru că timing-ul se schimbă).

Local poți valida logica funcțională, dar nu poți deduce că ai păstrat invarianta sub concurență.

### „Dacă se întâmplă, dăm retry”

Retry-ul poate fi o plasă de siguranță, dar nu justifică introducerea unei ordini de lock-uri inconsistente. Retry-ul crește încărcarea, ceea ce crește probabilitatea de a reproduce exact problema.

### „Feed-urile sunt doar sincronizare; nu pot strica checkout-ul”

Chiar dacă feed-urile nu ating direct comanda, ele ating resurse pe care checkout-ul le citește (preț, activare, eligibilitate, disponibilitate). Un feed este un writer concurent, nu un job „inofensiv”.

### „External ID-ul e doar un string; îl mutăm unde trebuie”

Tratează external ID-urile ca identitate externă, nu ca etichetă cosmetică:

- dacă permiți ca același external ID să se mapeze la două variante în aceeași sursă/cont, pierzi determinism;
- dacă permiți ca același external ID să „schimbe produsul”, introduci corupție de catalog greu de reparat.

---

## 8) Cum să contribui în siguranță

### 8.1 Clasifică schimbarea înainte să scrii

Înainte să te apuci, decide în ce categorie intră writer-ul:

- **Catalog-only (Product/Variant)**: afectează active/inactive, default, combinații, reguli de unicitate.
- **Order-only (Order/Checkout)**: afectează validare, stoc, snapshot comenzi.
- **Feed-only (External Feeds)**: afectează mapping-uri și update-uri operaționale (preț/stoc) în mod idempotent.
- **Cross-domain**: atinge două sau trei dintre domeniile de mai sus.

Cross-domain este categoria cu risc cel mai mare: verifică explicit regula „V se lock-uiește ultima”.

### 8.2 Checklist mental (înainte de orice writer)

- Ce invarianta poate afecta această schimbare (unicitate, default, preț, stoc, snapshot, external IDs)?
- Ce alte fluxuri pot rula în paralel (admin, checkout, feed-uri) și pe ce resurse concurează?
- Ce resursă este „ancora” (P sau O)? Există și o cheie externă care necesită A?
- Blochezi mai multe variante? Dacă da, ai o ordine deterministă pentru toate?
- Poate operația să facă vizibilă o stare intermediară invalidă?
- Operația traversează domenii? Dacă da, varianta este blocată ultima?

### 8.3 Întrebări-cheie pentru review

- Care invariantă este „cea mai importantă” pe care o protejează acest writer?
- Care este cel mai rău lucru care se poate întâmpla sub concurență (oversell, preț greșit, duplicate active, deadlock)?
- Există vreun loc unde se poate ajunge la V înainte de P sau V înainte de O/I?
- Există vreun loc unde external IDs devin ambigue (aceeași sursă/cont pentru două variante)?
- Dacă feed-ul livrează de două ori același update, rezultatul rămâne același?

### 8.4 Când trebuie cerut review de la cineva care cunoaște sistemul

- când operația atinge cross-domain (Order/Checkout + Product/Variant);
- când operația schimbă reguli de selecție (default/activ/eligibilitate);
- când operația afectează prețul sau stocul observabil;
- când operația atinge mapping-uri de external IDs sau comportamentul feed-urilor;
- când operația blochează multiple variante (risc crescut de deadlock dacă ordinea nu e clară).

---

## Rezumat (de reținut)

- Invariantele sunt contracte: încălcarea lor, chiar temporară, produce bug-uri rare dar catastrofale.
- Domeniile sunt separate pentru a păstra raționamentul simplu și corect.
- Lock ordering previne deadlock-uri doar dacă este consecvent și determinist (inclusiv ordinea când blochezi multiple variante).
- În operații cross-domain, varianta este resursa de capăt: se lock-uiește ultima.

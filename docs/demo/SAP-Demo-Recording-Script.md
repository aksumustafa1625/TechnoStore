# TechnoStore SAP Integration — Demo Recording Script

**Recording duration**: ~10-12 dakika (7 phase × 60-90 saniye)
**Strategy**: HONEST demo — sandbox real calls + Apex code + Postman reproducibility. No Fiori manipulation. Trial Fiori sadece "production reference UI" olarak opsiyonel.

## Ekran düzeni (her phase için aynı)

```
┌─────────────────────────────────┬─────────────────────────────────┐
│  SOL: SALESFORCE / APEX LOG     │  SAĞ: POSTMAN                   │
│  (action + result)              │  (reproducible API call)        │
│                                 │                                 │
│  - SF record / Developer        │  - Same SAP endpoint            │
│    Console / Debug Log          │  - Same headers                 │
│  - Audit fields update          │  - Same response                │
└─────────────────────────────────┴─────────────────────────────────┘
```

VS Code Developer Console'u açık tut. Postman'ı ikinci monitör veya yan pencerede.

---

## Pre-recording checklist (5 dakika)

- [ ] Salesforce orga login
- [ ] VS Code → SFDX projesi açık
- [ ] Postman → `TechnoStore SAP Demo` collection import edilmiş, environment seçilmiş, `SAP_API_KEY` set edilmiş
- [ ] Anypoint Studio çalışıyor (Mule deployed, ngrok aktif) — Phase 7 için
- [ ] Ekran kayıt yazılımı (OBS / Loom / Camtasia) hazır
- [ ] Mikrofon test edildi

---

## Intro (30 saniye)

> *"TechnoStore — Salesforce Industries Quote-to-Cash demo'mun **SAP entegrasyon** kısmına odaklanıyoruz. 7 SAP API entegrasyonu var: ATP, Sales Order, Tax, Payment, Material Master, Customer Master, Event Mesh. Hepsi gerçek SAP altyapısına (sandbox.api.sap.com) bağlı. Tüm çağrılar reproducible — Postman'dan da aynısını çalıştırabilirim."*

**Show**: README slide veya Mermaid C4 diagram (`docs/architecture/`)

---

## Phase 1 — ATP Check (90 sn)

**Soldaki ekran (Salesforce)**:
- Open Order #00000170 detail page
- Click "Request Inventory Check" button (or run anonymous Apex `scripts/run_phase1_atp.apex`)
- Debug log açıl: `=== PHASE 1 RESULT ===` görünür: `Material 221 → 0.000 units`
- Order audit fields: `SAP_Available_Quantity__c = 0.00`, `SAP_Inventory_Checked_At__c = ...`

**Sağdaki ekran (Postman)**:
- Phase 1 folder → "GET Material Stock for Material 221" → **Send**
- Aynı endpoint, aynı 200 OK, aynı `MatlWrhsStkQtyInMatlBaseUnit: 0.000`

**Narration**:
> *"Salesforce'taki Order için bir ATP check başlatıyorum. Apex servisim SAP MM API'ye gerçek bir GET atıyor — şu Postman penceresinde aynı çağrıyı manuel yapıyorum, aynı response. SAP material 221 için 0 unit available diyor. Bu rakam Salesforce Order'ın audit field'larına yazıldı. Production'da bu sıfır miktar Out-of-Stock flow'unu tetiklerdi (ADR-022)."*

---

## Phase 2 — Sales Order Push (90 sn — HONEST)

**Soldaki ekran (Salesforce)**:
- Open Order #00000170 → run `scripts/run_phase2_sap_push.apex`
- Debug log: "pushOrders enqueued (@future async)"
- Wait 15 sec → run `scripts/verify_phase2.apex`
- Audit: `Status_In_SAP__c = Push Failed`, `SAP_Sales_Order_Number__c = null`

**Sağdaki ekran (Postman)**:
- Phase 2 folder → "Step 1: HEAD CSRF Token" → Send → console: "Captured CSRF token..."
- "Step 2: POST Sales Order" → Send → response 200 (sandbox doesn't persist)

**Narration**:
> *"Sales Order push. CSRF token alıyorum, sonra Sales Order'ı POST ediyorum. Sandbox 200 dönüyor ama bu read-mostly bir test endpoint — record persist etmiyor. Bu davranışı Salesforce tarafında **transparent** olarak gösteriyoruz: `Status_In_SAP__c = Push Failed`. Bu honest engineering — sandbox limitation'ı saklamıyoruz. Production migration ADR-023'te dokümante: gerçek S/4HANA tenant'ında aynı API contract gerçek SO numarası döner ve audit field doğru dolar."*

---

## Phase 3 — Tax Determination (60 sn)

**Soldaki ekran (Salesforce)**:
- Open Invoice DOC-000000002 → run `scripts/test_sap_tax_calc.apex`
- Debug log: SAP tax API → 403 license-gated → fallback DE 19%
- Audit: `Tax_Engine_Used__c = SAP_FALLBACK_TABLE`, `SAP_Tax_Rate__c = 19.00`

**Sağdaki ekran (Postman)**:
- Phase 3 folder → "POST Tax Calculation" → Send → 403 expected

**Narration**:
> *"Tax determination. SAP tax modülü sandbox'ta license-gated — 403 döner. Kodum bunu yakalıyor ve transparent olarak country fallback table'a düşüyor: DE için %19 VAT. Hangi engine kullanıldı? `Tax_Engine_Used__c` field'ında: `SAP_FALLBACK_TABLE`. Production'da licensed tax modülü olunca aynı kod yolu `SAP_API` döner. ADR-024."*

---

## Phase 4 — Payment Reconciliation (CAMT.053) (60 sn)

**Soldaki ekran (Salesforce only — local parsing)**:
- Run `scripts/test_sap_payment_reconciliation.apex`
- Debug log: CAMT.053 XML parsed, 2 transactions, 2 invoices matched
- Audit: Invoice.Payment_Method__c = Bank_Transfer, SAP_Payment_Reference__c, SAP_Payment_Posted_At__c

**Sağdaki ekran (Postman)**:
- Phase 4 folder → README slide (no API call — local processing)

**Narration**:
> *"CAMT.053 — ISO 20022 bank statement reconciliation. SAP API çağrısı değil; bank'tan gelen XML'i local olarak parse ediyorum. 3 kademeli matching: EndToEndId → Remittance Reference → Amount Tolerance ±0.50 EUR. 2 transaction, 2 invoice matched. Production'da bu XML SAP'den veya bank'tan gelir; parsing kodu aynı. ADR-025."*

---

## Phase 5 — Material Master Sync (60 sn)

**Soldaki ekran (Salesforce)**:
- Run `scripts/test_sap_material_master_sync.apex`
- Debug log: 10 SAP materials fetched, upserted to Product2
- SOQL query: `SELECT Name, SAP_Material_Number__c FROM Product2 WHERE SAP_Material_Number__c != null` → shows imported records

**Sağdaki ekran (Postman)**:
- Phase 5 folder → "GET Top 10 SAP Products" → Send → 200 OK + 10 products

**Narration**:
> *"Material master sync. Apex GET'i sandbox'a, 10 material döner — gerçek SAP product code'ları. Salesforce'a Product2 olarak upsert edildi, `SAP_Material_Number__c` external ID alanı join key. Production'da bu nightly Mule batch olarak çalışır. ADR-026."*

---

## Phase 6 — Customer Master Sync (BP) (60 sn) ⭐ DACH HIGHLIGHT

**Soldaki ekran (Salesforce)**:
- Run `scripts/test_sap_customer_master_sync.apex`
- Debug log: 10 BPs fetched, German enterprises (Bechtle AG, Inlandskunde DE)
- SOQL query: Account list with SAP_BP_Number__c → German company names

**Sağdaki ekran (Postman)**:
- Phase 6 folder → "GET Top 10 SAP Business Partners" → Send → 200 OK
- Console: "Sample German BPs: Bechtle AG, Inlandskunde DE..."

**Narration**:
> *"Customer master sync — BP'leri Salesforce Account'lara upsert. Burada DACH-spesifik bir an: SAP sample data **Bechtle AG**'yi içeriyor — Almanya'nın #1 IT distributor'ı. Sandbox bile gerçekçi enterprise data. Account.SAP_BP_Number__c external ID. ADR-027."*

---

## Phase 7 — Event Mesh Inbound (90 sn)

**Soldaki ekran (Salesforce)**:
- Open Account [SAP] Cust15 — show current SAP_Customer_Group__c
- Open Apex Replay Debug Log viewer

**Sağdaki ekran (Postman)**:
- Phase 7 folder → "POST CloudEvent — Business Partner Changed" → Send → 200 OK
- (Ngrok endpoint via SF Site)

**Salesforce'a dön**:
- Refresh Account → SAP_Customer_Group__c = BP02 (was BP01)
- Show Webhook_Event__c log record (idempotency)
- Show Integration_Error__c records (if any)

**Narration**:
> *"Inbound — yön ters. SAP Event Mesh production'da gerçek zamanlı CloudEvent yayınlar. Postman'dan aynı CloudEvents 1.0 contract'ını simüle ediyorum. Salesforce REST webhook (`/sap/event`) HMAC validate ediyor, dispatcher event type'a göre route ediyor, ilgili sObject'in audit field'ı güncelleniyor. Trial'da SAP Event Mesh olmadığı için Postman replicating contract — production'da Event Mesh aynı POST'u yapacak. ADR-028."*

---

## Outro (45 saniye)

**Show**: ADR-028 + ADR-029 file open

> *"7 SAP entegrasyon fazı, tümü gerçek SAP API altyapısına bağlı, tümü reproducible Postman koleksiyonu ile. Sandbox kısıtlamaları (POST persistence, tax license) transparent olarak audit field'larda görünür. Production migration path ADR-022 ile ADR-029 arasında tam dokümante — Salesforce kodu zero-change, sadece `SAP_Config__c.API_Base_URL__c` ve OAuth Communication Arrangement değişir. Honest engineering, full traceability. Soru için hazırım."*

---

## Recruiter soru-cevap mühimmatı

| Soru | Cevap mühimmatı |
|------|---|
| "Trial S/4HANA Cloud kullandınız mı?" | "Evet, S/4HANA Cloud Public Edition trial'da gezindim — Manage Sales Orders, Maintain Business Partner gibi app'leri biliyorum. Demo'da kod entegrasyonu için trial Communication Arrangements'ın izin vermediği gerçeğini transparent paylaştım, sandbox üzerinden full API contract gösterdim." |
| "Production'a geçiş ne kadar?" | "ADR-029'da dokümante — 4-6 hafta. Major work: OAuth client credentials setup (her API scenario için Communication Arrangement), Named Credential refactor, endpoint URL switch. Apex contract sıfır değişir." |
| "Sandbox neden POST persist etmiyor?" | "SAP API Hub Sandbox public test infrastructure — multi-tenant, read-mostly. Production tenant authenticated + persistent. Bu davranışı `Status_In_SAP__c=Push Failed` ile transparent olarak audit'liyoruz, gizlemiyoruz." |
| "Tax engine fallback neden?" | "Sandbox'ta tax modülü license-gated. Production'da licensed tax engine aktif. Kod transparent fallback — `Tax_Engine_Used__c` field engine path'ini her record için audit'liyor. Bu pattern Phase 1 ATP'de de var: SAP-first / SF-fallback hybrid (ADR-022 + ADR-024 aynı pattern)." |
| "Event Mesh production setup?" | "SAP BTP Event Mesh + SAP Integration Suite gerekli. SAP CloudEvents 1.0 publisher kurarız, our `/sap/event` endpoint'i subscribes. HMAC validation rotates. Idempotency `Webhook_Event__c.External_Id__c` ile garantili (ADR-003 + ADR-028 pattern)." |
| "Mule rolü?" | "Şu an demo Apex-direct. Production'da Mule outbound proxy: retry, DLQ, idempotency, batching (ADR-001 Mule-vs-Apex matrix). Inbound Event Mesh için optional — Mule iFlow veya direct webhook ikisi de viable." |

---

## Recording sonrası — yapılacaklar

1. Video'yu Loom/YouTube unlisted upload
2. ADR-029 finalize
3. README'ye SAP demo bölümü ekle (link to video)
4. Notion portfolio'ya entry ekle: "SAP Integration Showcase — 7 Phases Honest Demo"
5. LinkedIn post: "Released a deep-dive demo of 7 SAP API integrations from a Salesforce Industries Q2C platform. Real sandbox calls, full audit transparency, production migration path documented."

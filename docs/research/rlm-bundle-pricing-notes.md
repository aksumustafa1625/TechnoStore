# RLM Pricing / Bundle Research Notes

Son guncelleme: 2026-06-29

Bu dosya, TechnoStore RLM bundle/configurator/pricing problemini org uzerinde yeni degisiklik yapmadan arastirmak icin olusturuldu.

Amac:

1. Resmi Salesforce dokumanlari, public web aramasi ve org runtime metadata bulgularini ayirmak.
2. `runSalesforceHeadlessPricing`, `runSalesforcePricing`, context sync, pricing procedure ve bundle quote line validation konularini netlestirmek.
3. Sonraki denemeleri kucuk, geri alinabilir ve kanita dayali hale getirmek.

Bu dosya org uzerinde herhangi bir DML/update/delete/callout degisikligi yapildigini gostermez. Arastirma sirasinda calistirilan org komutlari read-only REST/Apex describe ve SOQL sorgularidir.

## Kisa Sonuc

Su an en guclu sonuc:

- Bundle parent/child veri modeli buyuk olcude dogru kurulmus durumda.
- Asil kopukluk RLM/Salesforce Pricing runtime tarafinda: quote pricing transaction tamamlanmiyor.
- `Quote.CalculationStatus = SaveFailedOrIncomplete` ve `Quote.ValidationResult = TransactionIncomplete` semptom degil, native Create Order blokajinin ana nedeni.
- Parent `QuoteLineItem.UnitPrice` Apex ile degisse bile RLM read-only pricing alanlari (`NetUnitPrice`, `NetTotalPrice`, `TotalPrice`, quote totals) engine tarafindan tekrar yazilmadigi icin stale kaliyor.
- `ContextDefinitionSync` kayitlari icinde sadece `BrowseProductsCtxDefinition` icin basarili sync gorundu. `RLM_SalesTransactionContext` veya `RevSalesTransactionContext` icin sync kaydi gorunmedi.
- `runSalesforceHeadlessPricing` action'i orgda mevcut ve input sozlesmesi net: `contextDefinitionId`, `contextMappingId`, `pricingProcedureId`, `pricingData` zorunlu. Ancak public web'de bu action icin ayrintili ornek/payload dokumani bulunamadi.

## Arastirma Kapsami

### Web aramalari

Public web'de su terimler arandi:

- `SF-Pricing-00004`
- `We couldn't find the pricing procedure`
- `NO_CONTEXT_RUNTIME_FOUND`
- `runSalesforceHeadlessPricing`
- `runSalesforcePricing`
- `Salesforce Headless Pricing contextMappingId pricingData`
- `ContextDefinitionSync Salesforce`
- `QuoteLinePriceAdjustment Salesforce`
- `Revenue Lifecycle Management pricing procedure`
- `Industries CPQ pricing procedure`
- Salesforce StackExchange, GitHub, Trailblazer Community odakli aramalar

Bulgu:

- Exact hata/action isimleri icin public index'te anlamli bir cozum yazisi bulunamadi.
- Bu, problemin cozulmedigi anlamina gelmez; Salesforce RLM/Industries dokumanlarinin onemli kismi login arkasinda veya public arama indeksinde zayif gorunuyor olabilir.
- Public web'de net ornek bulunamadigi icin en guvenilir kaynak orgun kendi REST action describe endpoint'i ve object describe/SOQL bulgulari oldu.

## Resmi / Runtime Kaynaklar

### REST standard action describe: runSalesforceHeadlessPricing

Kaynak:

- Org runtime describe output: `scripts/describe_runSalesforceHeadlessPricing.out.json`
- Endpoint: `/services/data/v67.0/actions/standard/runSalesforceHeadlessPricing`

Action description:

> Invokes the pricing connect API by providing context definition ID, context mapping ID, JSON data string, pricing procedure ID, and price waterfall details.

Zorunlu inputlar:

- `contextDefinitionId`
  - Description: context definition record used to build pricing data.
- `contextMappingId`
  - Description: context mapping record Id that identifies which Salesforce object and mappings to use to build pricing data.
- `pricingProcedureId`
  - Description: id of the pricing procedure record used to execute the pricing process.
- `pricingData`
  - Description: JSON data used to build pricing data.

Opsiyonel inputlar:

- `isSkipWaterfall`
- `useSessionScopedContext`
- `persistContext`
- `taggedData`
- `discoveryProcedure`
- `skipDiscovery`
- `effectiveDate`
- `displayContext`
- `isHighVolumeLineItems`

Outputlar:

- `pricingProcessStatus`
- `pricingProcessErrors`
- `pricingResult`
- `contextDetails`
- `executionId`

Yorum:

- Bu action quote record Id almaz; kendi context payload'ini `pricingData` stringinden kurar.
- `displayContext=true` cok degerli olabilir; basarili ya da kismi basarili cagrida engine'in olusturdugu context yapisini dondurmesi beklenir.
- `pricingProcedureId` icin description "pricing procedure record" diyor. Bu ifadeden `CalculationProcedure.Id` (`0k0...`) mi yoksa version Id (`0k1...`) mi beklendigi tek basina kesin degil.
- Daha once hem `0k0...` hem `0k1...` ile denendi ve procedure bulunamadi. Bu nedenle hata sadece Id tipi degil, context/payload/default binding/sync ile de ilgili olabilir.

### REST standard action describe: runSalesforcePricing

Kaynak:

- Org runtime describe output: `scripts/describe_runSalesforcePricing.out.json`
- Endpoint: `/services/data/v67.0/actions/standard/runSalesforcePricing`

Action description:

> Invokes the pricing connect API by providing context ID, procedure name, and price waterfall details.

Zorunlu inputlar:

- `contextInstanceId`
- `pricingProcedureName`

Opsiyonel inputlar:

- `isSkipWaterfall`
- `discoveryProcedure`
- `skipDiscovery`
- `effectiveDate`
- `isDeveloperName`

Yorum:

- Bu action headless degil; aktif runtime context instance bekliyor.
- Quote Id verildiginde `NO_CONTEXT_RUNTIME_FOUND` alinmasi mantikli: quote record Id, context instance Id degil.
- Configure UI icindeki aktif session/runtime context yakalanmadan bu action'i kullanmak zor.

### REST standard action describe: createOrderFromQuote

Kaynak:

- Endpoint: `/services/data/v67.0/actions/standard/createOrderFromQuote`

Input:

- `quoteRecordId`

Yorum:

- Create Order action'i pricing'i kendisi tamir eden bir action gibi davranmiyor.
- Quote calculation status invalid ise UI'da gorulen hata beklenen davranis:
  - "calculation status of the quote is invalid"

## Org Kanitlari

### ContextDefinition kayitlari

Read-only diagnostic:

- `scripts/diagnose_rlm_pricing_context_focused_readonly.apex`
- Output:
  - `scripts/diagnose_rlm_pricing_context_focused_readonly.out.txt`

Hedef contextler:

| Context | Id | Active Version | LastModified |
|---|---|---|---|
| BrowseProductsCtxDefinition | `11Oaj000000whZFEAY` | `11paj00000PLbpNAAT` v11 | 2026-06-17 |
| Custom_ContractsContext | `11Oaj000000xL21EAE` | `11paj00000PUcCjAAL` v35 | 2026-04-22 |
| RevSalesTransactionContext | `11Oaj000000whZIEAY` | `11paj00000PLbpQAAT` v5 | 2026-04-10 |
| RLM_SalesTransactionContext | `11Oaj000000whZGEAY` | `11paj00000PLbpOAAT` v10 | 2026-04-10 |

### ContextDefinitionSync kayitlari

Read-only REST query:

- `scripts/query_context_definition_sync.out.json`

Sonuc:

```text
totalSize = 1
ContextDefinitionName = BrowseProductsCtxDefinition
Status = success
StartDateTime = 2026-06-17T11:24:05.000+0000
EndDateTime = 2026-06-17T11:24:07.000+0000
```

Kritik bulgu:

- `RLM_SalesTransactionContext` icin sync kaydi yok.
- `RevSalesTransactionContext` icin sync kaydi yok.
- Bu durum, "Browse Catalog/Product Discovery sync calisiyor ama quote pricing context runtime eksik olabilir" hipotezini guclendiriyor.

Dikkat:

- ContextDefinitionVersion kayitlari active gorunuyor. Ancak active version olmak ile runtime sync edilmis olmak ayni sey olmayabilir.
- BrowseProducts context'in 2026-06-17'de sync edilmis olmasi, catalog browsing tarafinin calismasini aciklayabilir.
- Quote pricing tarafinin syncsiz kalmasi, headless/runtime pricing sorununu aciklayabilir.

### CalculationProcedure / CalculationProcedureVersion

Read-only diagnostic sonucu:

| Kayit | Id | Durum |
|---|---|---|
| CalculationProcedure | `0k0aj000000I52wAAC` | `Revenue Management Default Pricing Procedure V1` |
| CalculationProcedureVersion | `0k1aj000000HkksAAC` | Version 1, `IsEnabled=true`, `Rank=1`, `StartDateTime=2025-02-02 20:56:40` |

Yorum:

- Pricing procedure kaydi yok degil; orgda var ve version enabled.
- Bu nedenle `SF-Pricing-00004` / "pricing procedure not found" hatasi buyuk ihtimalle daha dolayli:
  - Action yanlis context/payload ile procedure'i cozemiyor.
  - Procedure default binding/sync runtime cache'te yok.
  - `pricingProcedureId` olarak beklenen kayit tipi bizim verdigimizden farkli.
  - Context mapping ve payload kok objesi uyumsuz.

### Demo Quote 4/5 state

Read-only diagnostic:

| Quote | Id | CalculationStatus | ValidationResult | Total |
|---|---|---|---|---|
| Demo Quote 4 | `0Q0aj000002hDwyCAE` | `SaveFailedOrIncomplete` | `TransactionIncomplete` | 1898 |
| Demo Quote 5 | `0Q0aj000002hDwzCAE` | `SaveFailedOrIncomplete` | `TransactionIncomplete` | 1648 |

Kritik line bulgulari:

- Quote 4 parent:
  - `UnitPrice=1949`
  - `NetUnitPrice=1449`
  - `NetTotalPrice=1449`
  - `TotalPrice=1449`
- Quote 5 parent:
  - `UnitPrice=2099`
  - `NetUnitPrice=1599`
  - `NetTotalPrice=1599`
  - `TotalPrice=1599`

Yorum:

- Apex parent `UnitPrice` update ediyor.
- RLM pricing waterfall quote line read-only net/total alanlarini tekrar hesaplamiyor.
- Bu, "custom Apex price adjustment native pricing engine'in yerine gecmiyor" sonucunu guclendiriyor.

### QuoteLinePriceAdjustment durumu

Ilk diagnostic'te:

```text
QuoteLinePriceAdjustment ROW_COUNT=0
```

Yorum:

- Attribute upcharge su anda `QuoteLinePriceAdjustment` olarak modellenmiyor.
- Context mapping tarafinda `QuoteLinePriceAdjustment -> SalesTransactionItemPriceAdjustment__std` mapping oldugu daha once gorulmustu.
- Bu nedenle tek parent line uzerinde QLPA denemesi teknik olarak makul bir deney olabilir, ancak kalici cozum oldugu kanitlanmadan handler'a eklenmemeli.

## Yerel ADR Bulgulari

### ADR-002

Dosya:

- `docs/adr/ADR-002-custom-metadata-over-attribute-based-adjustment.md`

Oz:

- Native `AttributeBasedAdjustment` / Pricing Procedure yolu bu Developer Edition orgda bozuk goruldu.
- Builder UI procedure'i "0 steps" gibi render etti.
- Runtime engine step'leri skip ediyor gibi gozlemlendi.
- Bu nedenle custom metadata + Apex workaround kabul edildi.

Bugunku yorum:

- ADR-002 bugunku semptomlari destekliyor: native pricing engine bu orgda zaten supheliydi.
- Ancak ADR-002 daha cok attribute pricing procedure step'leriyle ilgiliydi; bugunku sorun quote transaction calculation status seviyesinde daha genis.

### ADR-016

Dosya:

- `docs/adr/ADR-016-pricing-apex-workaround.md`

Oz:

- Apex workaround gecici kabul edilmis.
- Canonical yolun native Pricing Procedure / AttributeBasedAdjustment oldugu belirtilmis.
- Future state: Builder fix gelirse trigger pricing path devre disi birakilip native procedure'e donulecek.

Bugunku yorum:

- ADR-016'nin "Apex UnitPrice workaround" yaklasimi konfigurator demo fiyati icin yeterli olabilir.
- Fakat native Create Order icin yeterli degil; cunku RLM read-only net/total/calculation status alanlari engine tarafindan yazilmali.
- Bu nedenle bugunku hedef sadece `UnitPrice` guncellemek degil, pricing transaction'i basariyla tamamlatmak.

## Public Web Arama Sonucu

Gayriresmi kaynaklarda exact cozum bulunamadi:

- Salesforce StackExchange exact `runSalesforceHeadlessPricing` / `SF-Pricing-00004` aramalarinda belirgin sonuc yok.
- GitHub exact hata/action aramalarinda belirgin sonuc yok.
- Trailblazer Community public index exact hata/action aramalarinda belirgin sonuc yok.

Bu bulgu iki sekilde yorumlanmali:

1. Problem nadir ve org/release/feature-flag spesifik olabilir.
2. Cozum dokumanlari Salesforce login arkasinda veya customer support / partner community icinde olabilir.

Bu nedenle bizim en guvenilir kaynaklar:

- Org action describe endpoint'leri
- Org object describe/SOQL bulgulari
- UI'daki Salesforce Pricing Setup ekranlari
- RevenueTransactionErrorLog
- Kucuk ve geri alinabilir testler

## Cevaplanmis Sorular

### runSalesforcePricing quote Id ile calisir mi?

Hayir gibi gorunuyor.

Kanita dayali gerekce:

- Action input'u `contextInstanceId` istiyor.
- Description: "Id of the context data used to build the Pricing Procedure."
- Quote Id ile daha once `NO_CONTEXT_RUNTIME_FOUND` alindi.

Sonuc:

- Bu action, UI runtime context instance olmadan quote reprice etmek icin uygun degil.

### runSalesforceHeadlessPricing quote Id ile minimal payload kabul eder mi?

Kesin degil.

Kanita dayali bildigimiz:

- Action `pricingData` string istiyor.
- Description sadece "JSON data used to build pricing data" diyor.
- `contextMappingId` hangi Salesforce object mappings kullanilacagini belirliyor.

Hipotezler:

- Minimal `{ "Quote": { "Id": "..." } }` yetersiz olabilir.
- `SalesTransaction` kok objesi gerekebilir.
- Full quote graph gerekebilir: quote + lines + attributes + relationships + adjustments.
- `taggedData`, `persistContext`, `displayContext` gibi opsiyonlar sonucu etkileyebilir.

### pricingProcedureId icin 0k0 mi 0k1 mi?

Kesin degil.

Kanita dayali bildigimiz:

- Action description "pricing procedure record" diyor.
- Orgda:
  - Procedure `0k0aj000000I52wAAC`
  - Version `0k1aj000000HkksAAC`
- Daha once iki varyantla da hata alindi.

Yorum:

- Id tipi onemli ama tek problem olmayabilir.
- Context sync/default binding olmadiginda dogru Id de "not found" gibi hata verebilir.

### QuoteLinePriceAdjustment daha native mi?

Muhtemelen evet, ama kanitlanmadi.

Destekleyen bulgular:

- Context mapping'de QLPA'nin SalesTransactionItemPriceAdjustment context node'una map edildigi gorulmustu.
- RLM net/total read-only alanlarini engine yazar; UnitPrice override tek basina waterfall sonucu uretmiyor.

Karsit/uyari:

- Manuel QLPA insert etmek engine'in bunu otomatik hesapladigi anlamina gelmez.
- UI Reprice/Headless Pricing calismadan QLPA da totals'a yansimayabilir.

Sonuc:

- QLPA tek parent line uzerinde iyi bir deney adayi.
- Kalici handler degisikligi icin erken.

### ValidationResult null yapmak cozum mu?

Tek basina hayir.

Yorum:

- Warning icon'u gorsel olarak azalabilir.
- Ancak quote `CalculationStatus=SaveFailedOrIncomplete` kaldikca native Create Order fail eder.
- Bu nedenle validation cleanup root cause degil, en fazla son temizlik adimi.

## En Guclu Hipotezler

### Hipotez 1: SalesTransaction context sync eksik

Guc: Yuksek.

Kanita dayali gerekce:

- `ContextDefinitionSync` tablosunda sadece `BrowseProductsCtxDefinition` success var.
- `RLM_SalesTransactionContext` / `RevSalesTransactionContext` sync kaydi yok.
- Browse catalog tarafinin calisip quote pricing tarafinin eksik kalmasi bu ayrimi destekliyor.

Risk:

- Context sync UI/API ile nasil tetiklenir tam bilinmiyor.
- Direkt `ContextDefinitionSync` insert etmek gecmiste platform tarafindan islenmemisti.

### Hipotez 2: Headless pricing payload/kok obje yanlis

Guc: Yuksek.

Kanita dayali gerekce:

- Action `contextMappingId` istiyor; bu mapping payload kok objesiyle uyumlu olmali.
- Daha once minimal quote payload ile procedure not found alindi.

Risk:

- Public payload ornegi bulunamadi.
- Yanlis payload yine ayni belirsiz hata mesajini uretebilir.

### Hipotez 3: UnitPrice override native waterfall'i bypass ediyor

Guc: Cok yuksek.

Kanita dayali gerekce:

- Parent `UnitPrice` 2099/1949.
- Parent `NetUnitPrice` 1599/1449 stale.
- Quote totals stale.

Sonuc:

- Apex UnitPrice update demo gorseli icin yararli ama native pricing completion icin yetersiz.

### Hipotez 4: Eski Quote 4/5 artik guvenilir test zemini degil

Guc: Orta-yuksek.

Kanita dayali gerekce:

- Bu quote'lar birden cok repair/reprice/attribute script gordu.
- `SaveFailedOrIncomplete` state'i yeni temiz transaction'da tekrar test edilmeli.

Risk:

- Trigger aktif oldugu surece "tamamen native" yeni quote testi de Apex etkisi alir.

## Sonraki Risksiz Arastirma Adimlari

Degisiklik yapmadan:

1. UI'da Salesforce Pricing Setup ekraninda secili pricing procedure, sync tarihi, default binding alanlari manuel incelensin.
2. `ContextMapping` field list daha detayli okunup `IsDefault`, `Name`, `Type`, `MappingType` gibi alanlar netlestirilsin.
3. `ContextNodeMapping` detaylari filtered olarak RLM/Rev context mapping Id'leri icin raporlansin.
4. `runSalesforceHeadlessPricing` icin sadece `displayContext=true`, `skipDiscovery=true`, `isSkipWaterfall=true` gibi en az yan etkili parametrelerle payload deneme planlanabilir; ancak bu action pricing execution yaptigi icin kullanici onayi gerekir.

## Sonraki Kucuk Deney Adaylari

Bu adimlar degisiklik yapabilir; her biri icin ayri onay alinmali.

### Deney A: Context sync UI yolu

Hedef:

- `RLM_SalesTransactionContext` veya `RevSalesTransactionContext` icin resmi UI Sync/Activate butonunu bulmak.

Risk:

- Dusuk-orta. Sync runtime cache degistirir ama data kayitlarini bozmaz.

Beklenen kanit:

- `ContextDefinitionSync` icinde SalesTransaction context icin yeni success kaydi.

### Deney B: Headless pricing displayContext denemesi

Hedef:

- Dogru context/mapping/payload kombinasyonunu bulmak.

Risk:

- Orta. Pricing action quote/line alanlarini guncelleyebilir.

Once denenmesi gereken korumalar:

- Yeni test quote.
- Mümkunse sadece `displayContext=true`, `isSkipWaterfall=true`, `skipDiscovery=true`.
- Output `contextDetails` incelensin.

### Deney C: Tek parent line QuoteLinePriceAdjustment

Hedef:

- Attribute upcharge'in QLPA olarak modellenmesi RLM pricing tarafindan okunuyor mu?

Risk:

- Orta. QLPA insert data degisikligidir.

Kural:

- Sadece yeni test quote veya kolay silinebilir Demo Quote kopyasi.
- Handler'a kalici ekleme yok.
- Deney sonrasi QLPA silinebilir olmali.

### Deney D: ValidationResult cleanup

Hedef:

- Sadece stale UI warning'i temizlemek.

Risk:

- Orta. Semptomu gizleyebilir.

Kural:

- Pricing status valid olmadan yapilmamali.

## Tavsiye Edilen Yol

Benim su anki teknik tavsiyem:

1. Once UI'da Salesforce Pricing Setup / Context Definition sync durumunu kontrol et.
2. SalesTransaction context icin sync butonu varsa sync calistir.
3. Sync kaydi olustuktan sonra yeni temiz quote ile bundle ekle.
4. Eski Quote 4/5 yerine temiz quote uzerinden Reprice/Create Order dene.
5. Hala fail ederse headless pricing payload arastirmasina gec.
6. QLPA deneyini ancak pricing runtime'in calistigindan emin olduktan sonra yap.

Neden?

- Eger context sync eksikse, QLPA veya ValidationResult denemeleri root cause'u cozmeyecek.
- Eger pricing runtime calisir hale gelirse, UnitPrice vs QLPA farkini cok daha temiz gorebiliriz.

## Kaynaklar

Resmi / yarı resmi:

- Salesforce REST API Invocable Actions documentation: https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_actions_invocable.htm
- Salesforce Developer Object Reference - Quote: https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_quote.htm
- Salesforce Developer Object Reference - QuoteLineItem: https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_quotelineitem.htm
- Salesforce Help home/search: https://help.salesforce.com/

Org runtime evidence:

- `scripts/describe_runSalesforceHeadlessPricing.out.json`
- `scripts/describe_runSalesforcePricing.out.json`
- `scripts/query_context_definition_sync.out.json`
- `scripts/diagnose_rlm_pricing_context_focused_readonly.out.txt`

Yerel karar kayitlari:

- `docs/adr/ADR-002-custom-metadata-over-attribute-based-adjustment.md`
- `docs/adr/ADR-016-pricing-apex-workaround.md`
- `docs/troubleshooting/rlm-bundle-troubleshooting-notes.md`

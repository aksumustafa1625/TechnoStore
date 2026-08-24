# TechnoStore RLM Bundle Troubleshooting Notes

Son guncelleme: 2026-06-28

Bu dosya, Salesforce RLM / Industries CPQ bundle konfigurasyon probleminde simdiye kadar yapilanlari, kesin bulgulari, denenip calismayan yollari ve disaridan yardim istenirken sorulabilecek net sorulari toplamak icin olusturuldu.

Amac: Native Salesforce RLM davranisina en yakin sekilde bundle parent + child quote line yapisini calistirmak.

Istenen is akisi:

1. Sales rep quote uzerinden Browse Catalog acar.
2. Bundle urunu ekler.
3. Configure ekraninda RAM, Storage, Processor, Screen Size gibi attribute secimleri yapar.
4. Child component urunleri quote line lara gelir.
5. Attribute upcharge lari fiyata yansir.
6. Sari validation warning kaybolur.
7. Quote calculation status valid hale gelir.
8. Native Create Order butonu order olusturur.

Org hassasiyeti:

- Bu Developer Edition org uzerinde cok sayida demo entegrasyonu var.
- Kullanici buyuk org degisikliklerinden once onay istiyor.
- Destructive / genis kapsamli degisikliklerden kacinilmali.
- Amac mumkun oldugunca native RLM davranisini kurtarmak; custom bypass en son care.

## Ortam

- Salesforce Developer Edition
- Industries CPQ + Revenue Lifecycle Management / RLM aktif
- API komutlarinda `v67.0` kullanildi.
- CLI org alias: `TechnoStore`
- Ana workspace: `C:\Users\DELL\Documents\Projects\TechnoStore`
- Kullanilan quote lar:
  - Demo Quote 4: `0Q0aj000002hDwyCAE`
  - Demo Quote 5: `0Q0aj000002hDwzCAE`

## Baslangic Problemi

Bundle konfigurasyon ekraninda attribute lar secildiginde configurator icindeki hata/warning azalabiliyor, fakat quote line grid uzerinde sari warning kalabiliyor.

Ornek UI mesajlari:

- `Your quote was not updated. Enter an Attribute Picklist Value that's in an active or draft state.`
- `We couldn't create an order for this quote because the calculation status of the quote is invalid. Ask your Salesforce admin for help.`
- Quote line warning:
  - `One or more attributes for product TechNova ProBook 15 are missing. Specify these attributes and try again: Processor, Screen Size.`
  - `One or more attributes for product TechCover 1 Year are missing. Specify these attributes and try again: Subscription Type.`
  - `One or more attributes for product Monitor 27" 165Hz are missing. Specify these attributes and try again: Display, Screen Size.`

Kullanici tarafindan gozlenen ek durum:

- Child lines artik quote line grid e geliyor.
- Soldaki attribute secimleri yapiliyor.
- Ancak sari uyari her zaman kaybolmuyor.
- `Update Prices` bazen parent price/summary tarafini tam guncellemiyor.
- Attribute upcharge lari configurator summary tarafinda gorunse bile quote line grid / quote total tarafina tam yansimiyor.
- Alt component urunleri secildiginde fiyatlar guncellenebiliyor, fakat RAM/Processor/Storage/Screen Size gibi attribute upcharge lari quote total tarafinda native olarak tam oturmuyor.

## Ilgili Kod

Ana dosya:

- `force-app-handlers/main/default/classes/QuoteLineItemTriggerHandler.cls`

Ek invocable action:

- `force-app-actions/main/default/classes/BundleDecompositionAction.cls`

Onemli yardimci scriptler:

- `scripts/repair_native_bundle_relationships.apex`
- `scripts/repair_existing_bundle_child_default_attrs.apex`
- `scripts/reprice_existing_bundle_parent_totals.apex`
- `scripts/touch_current_demo_quote_lines_for_recalc.apex`
- `scripts/request_run_pricing_quote5.json`
- `scripts/request_headless_pricing_quote5_quote_entities.json`
- `scripts/describe_quote_pricing_fields.apex`
- `scripts/describe_bundle_relationship_fields.apex`

## Yapilan Kod Degisiklikleri

### 1. Bundle parent insert sonrasi child line decomposition

`QuoteLineItemTriggerHandler.cls` icine async bundle decomposition eklendi.

Davranis:

- Yeni eklenen `Product2.Type = 'Bundle'` quote line lar yakalaniyor.
- `ProductRelatedComponent` kayitlarindan default component ler okunuyor.
- Child product lar icin ayni quote pricebook icinde aktif `PricebookEntry` bulunuyor.
- Included component ise child `UnitPrice = 0`.
- Add-on component ise child `UnitPrice = PricebookEntry.UnitPrice`.
- Evergreen / TermDefined selling model tipleri skip ediliyor.
- Insert sonrasi child line lar icin default `QuoteLineItemAttribute` kayitlari yaziliyor.

Async kullanilma nedeni:

- Configure UI Save & Exit transaction icinde child insert edilince managed LWC kendi in-memory session state i ile karisabiliyor.
- Async future transaction ile child rows Configure UI commit transaction i bittikten sonra ekleniyor.

### 2. Duplicate bundle cleanup

Configure UI bazen Save & Exit sirasinda ayni bundle parent i tekrar insert edebiliyor gibi gorundu.

Handler icinde:

- Aynu Quote + Product2 icin eski bundle korunuyor.
- Sonradan gelen duplicate bundle parent lar async temizleniyor.

### 3. Parent bundle attribute-based price adjustment

`beforeUpdate` icinde parent bundle `UnitPrice` attribute secimlerine gore hesaplandi.

Data source:

- `Techno_Attribute_Price_Rule__mdt`

Ornek:

- Home Office Bundle base price: 1599
- RAM 16GB: +100
- Storage 512GB: +100
- Processor i7: +200
- Screen Size 15 Inch: +100
- Beklenen adjusted parent UnitPrice: 2099

Creator Studio Bundle:

- Base price: 1449
- Ayni attribute secimleri ile +500
- Beklenen adjusted parent UnitPrice: 1949

Kod gercekte `UnitPrice` alanini set ediyor.

Kritik bulgu:

- `QuoteLineItem.UnitPrice` updateable.
- `QuoteLineItem.NetUnitPrice`, `NetTotalPrice`, `Subtotal`, `TotalPrice` updateable degil.
- Bu yuzden Apex parent `UnitPrice` i degistirse bile RLM native pricing engine calismadan net/total alanlari stale kalabiliyor.

### 4. Child default attributes

Handler icinde child product code bazli default attribute map eklendi.

Ornek map:

- `COMP-LAP-001`
  - Memory = RAM 16GB
  - Storage = SSD Hard Drive 512GB
  - Processor = i7-CPU 4.7GHz
  - Screen Size = 15 Inch
- `COMP-LAP-003`
  - Memory = RAM 8GB
  - Storage = SSD Hard Drive 256GB
  - Processor = i5-CPU 4.4GHz
  - Screen Size = 13 Inch
- `AV-MON-001`
  - Display = 2k Built-in Display
  - Screen Size = 27 Inch
- `SVC-WAR-001`
  - Subscription Type = Business

Bu kayitlar `Database.insertImmediate` ile `QuoteLineItemAttribute` objesine yaziliyor.

## Org Uzerinde Yapilan Kucuk Repair / Test Degisiklikleri

### 1. Native QuoteLineRelationship repair

Script:

- `scripts/repair_native_bundle_relationships.apex`

Neden yapildi:

- Ilk durumda Apex ile eklenen child quote line lar parent a platform-native bagli gorunmuyordu.
- `ParentQuoteLineItemId`, `RelatedQuoteLineItemId`, `BindingInstanceTargetId` null kalmisti.
- Sonradan `QuoteLineRelationship` objesi createable bulundu.

Script ne yapti:

- Parent bundle quote line ile child quote line arasina native `QuoteLineRelationship` kayitlari insert etti.
- `MainQuoteLineId = parent QLI`
- `AssociatedQuoteLineId = child QLI`
- `RootQuoteLineId = parent QLI`
- `ProductRelatedComponentId = ilgili ProductRelatedComponent`
- `ProductRelationshipTypeId = component.ProductRelationshipTypeId`
- `AssociatedQuoteLinePricing`:
  - Included component icin `IncludedInBundlePrice`
  - Add-on component icin `NotIncludedInBundlePrice`
- `AssociatedQuantScaleMethod = Constant`

Sonuc:

- 8 adet `QuoteLineRelationship` insert edildi.
- Quote 4 icin 3 iliski:
  - Creator Studio Bundle -> SlimAir UltraBook 14
  - Creator Studio Bundle -> WebCam Pro 4K Studio
  - Creator Studio Bundle -> Monitor 27" 165Hz
- Quote 5 icin 5 iliski:
  - Home Office Bundle -> TechNova ProBook 15
  - Home Office Bundle -> Wireless Combo Set
  - Home Office Bundle -> TechCover 1 Year
  - Home Office Bundle -> ErgoMouse Vertical
  - Home Office Bundle -> WebCam Pro 4K Studio

Verify sonucu:

- `QuoteLineRelationship.IsPriceInclusive = true` for included children.
- `QuoteLineRelationship.IsPriceInclusive = false` for add-on children.
- `MainQuoteLineRole = Bundle`
- `AssociatedQuoteLineRole = BundleComponent`
- Sonraki query de child line larda `ParentQuoteLineItemId` dolu gorundu.

Bu cok onemli:

- Native relationship repair sonrasi `ParentQuoteLineItemId` artik platform tarafindan dolu gorunuyor.
- Bu, native bundle yapisina yaklasildigini gosteriyor.

## Kesin Dogrulanan Mevcut Veri Durumu

### Demo Quote 4

Quote:

- Id: `0Q0aj000002hDwyCAE`
- Name: `Demo Quote 4`
- Status: `Approved`
- CalculationStatus: `SaveFailedOrIncomplete`
- ValidationResult: `TransactionIncomplete`
- LastPricedDate: null
- TotalPrice: 1898
- Tax: 360.62
- GrandTotal: 2258.62

Parent line:

- Product: Creator Studio Bundle
- QLI Id: `0QLaj00000332ErGAI`
- ProductCode: `BUNDLE-CREATOR-001`
- Type: Bundle
- UnitPrice: 1949
- NetUnitPrice: 1449
- NetTotalPrice: 1449
- TotalPrice: 1449
- ValidationResult: null

Child lines:

- SlimAir UltraBook 14
  - QLI Id: `0QLaj00000332GTGAY`
  - ProductCode: `COMP-LAP-003`
  - ParentQuoteLineItemId: `0QLaj00000332ErGAI`
  - UnitPrice: 0
  - NetUnitPrice: 0
  - TotalPrice: 0
  - ValidationResult: Warning
- WebCam Pro 4K Studio
  - QLI Id: `0QLaj00000332GUGAY`
  - ProductCode: `AV-CAM-003`
  - ParentQuoteLineItemId: `0QLaj00000332ErGAI`
  - UnitPrice: 0
  - ValidationResult: null
- Monitor 27" 165Hz
  - QLI Id: `0QLaj00000332GVGAY`
  - ProductCode: `AV-MON-001`
  - ParentQuoteLineItemId: `0QLaj00000332ErGAI`
  - UnitPrice: 449
  - NetUnitPrice: 449
  - TotalPrice: 449
  - ValidationResult: Warning

Not:

- Parent UnitPrice dogru adjusted: 1449 + 500 = 1949.
- Ancak NetUnitPrice/TotalPrice hala 1449.
- Quote TotalPrice 1898 = 1449 + 449 gibi davranmaya devam ediyor.
- Yani RLM quote total, parent UnitPrice 1949 u dikkate almiyor.

### Demo Quote 5

Quote:

- Id: `0Q0aj000002hDwzCAE`
- Name: `Demo Quote 5`
- Status: `Approved`
- CalculationStatus: `SaveFailedOrIncomplete`
- ValidationResult: `TransactionIncomplete`
- LastPricedDate: null
- TotalPrice: 1648
- Tax: 313.12
- GrandTotal: 1961.12

Parent line:

- Product: Home Office Bundle
- QLI Id: `0QLaj00000332I5GAI`
- ProductCode: `BUNDLE-OFFICE-001`
- Type: Bundle
- UnitPrice: 2099
- NetUnitPrice: 1599
- NetTotalPrice: 1599
- TotalPrice: 1599
- ValidationResult: null

Child lines:

- TechNova ProBook 15
  - QLI Id: `0QLaj00000332JhGAI`
  - ProductCode: `COMP-LAP-001`
  - ParentQuoteLineItemId: `0QLaj00000332I5GAI`
  - UnitPrice: 0
  - ValidationResult: Warning
- Wireless Combo Set
  - QLI Id: `0QLaj00000332JiGAI`
  - ProductCode: `PER-KB-002`
  - ParentQuoteLineItemId: `0QLaj00000332I5GAI`
  - UnitPrice: 0
  - ValidationResult: null
- TechCover 1 Year
  - QLI Id: `0QLaj00000332JjGAI`
  - ProductCode: `SVC-WAR-001`
  - ParentQuoteLineItemId: `0QLaj00000332I5GAI`
  - UnitPrice: 49
  - ValidationResult: Warning
- ErgoMouse Vertical
  - QLI Id: `0QLaj00000332JkGAI`
  - ProductCode: `PER-KB-003`
  - ParentQuoteLineItemId: `0QLaj00000332I5GAI`
  - UnitPrice: 0
  - ValidationResult: null
- WebCam Pro 4K Studio
  - QLI Id: `0QLaj00000332JlGAI`
  - ProductCode: `AV-CAM-003`
  - ParentQuoteLineItemId: `0QLaj00000332I5GAI`
  - UnitPrice: 0
  - ValidationResult: null

Not:

- Parent UnitPrice dogru adjusted: 1599 + 500 = 2099.
- Ancak NetUnitPrice/TotalPrice hala 1599.
- Quote TotalPrice 1648 = 1599 + 49 gibi davranmaya devam ediyor.

## QuoteLineItemAttribute Durumu

`QuoteLineItemAttribute` describe sonucu:

Writable alanlar:

- `ExternalId`
- `AttributeValue`
- `AttributeDefinitionId`
- `AttributePicklistValueId`

Read-only / platform-set alanlar:

- `AttributeName`
- `IsPriceImpacting`
- `QuoteLineItemId` updateable degil ama createable

Mevcut kayitlar:

### Parent bundle attributes

Creator Studio Bundle ve Home Office Bundle parent line larinda attribute kayitlari var:

- Memory = RAM 16GB
- Storage = SSD Hard Drive 512GB
- Processor = i7-CPU 4.7GHz
- Screen Size = 15 Inch

Ancak `IsPriceImpacting` sadece Memory satirinda true, digerlerinde false gorundu:

- Memory: true
- Processor: false
- Screen Size: false
- Storage: false

Bu fiyat etkisi icin dikkat cekici ama tek basina yeterli aciklama olmayabilir, cunku custom metadata fallback ile Apex UnitPrice i yine dogru set ediyor.

### Child line attributes

TechNova ProBook 15:

- Memory = RAM 16GB
- Storage = SSD Hard Drive 512GB
- Processor = i7-CPU 4.7GHz
- Screen Size = 15 Inch

SlimAir UltraBook 14:

- Memory = RAM 8GB
- Storage = SSD Hard Drive 256GB
- Processor = i5-CPU 4.4GHz
- Screen Size = 13 Inch

Monitor 27" 165Hz:

- Display = 2k Built-in Display
- Screen Size = 27 Inch

TechCover 1 Year:

- Subscription Type = Business

Sonuc:

- UI warning "attributes missing" dese de attribute rows gercekte mevcut.
- Bu nedenle child warnings muhtemelen stale `QuoteLineItem.ValidationResult = Warning` flag inden veya native configurator cache/session state inden geliyor.

## AttributePicklistValue Durumu

Kritik picklist value query sonucu:

- Business: `Status = Active`
- RAM 16GB: `Status = Draft`
- SSD Hard Drive 512GB: `Status = Draft`
- i7-CPU 4.7GHz: `Status = Draft`
- 15 Inch: `Status = Draft`
- RAM 8GB: `Status = Draft`
- SSD Hard Drive 256GB: `Status = Draft`
- i5-CPU 4.4GHz: `Status = Draft`
- 13 Inch: `Status = Draft`
- 2k Built-in Display: `Status = Draft`
- 27 Inch: `Status = Draft`

UI hata metni:

- `Enter an Attribute Picklist Value that's in an active or draft state.`

Bu degerler active veya draft oldugu icin bu hata dogrudan status invalid gibi gorunmuyor.

## Pricebook / PBE Durumu

Current quote line larda `PricebookEntryId` dolu.

Ornek:

- Creator Studio Bundle PBE: `01uaj0000074OcSAAU`
- SlimAir PBE: `01uaj000007C8yhAAC`
- WebCam PBE: `01uaj000007C8zJAAS`
- Monitor PBE: `01uaj000007C8zDAAS`
- Home Office Bundle PBE: `01uaj0000074OcQAAU`
- TechNova PBE: `01uaj000007C8yfAAC`
- TechCover PBE: `01uaj0000074KC8AAM`

Bu nedenle son UI toast `Required fields are missing: [Price Book Entry]` buyuk ihtimalle gercek PBE eksikliginden degil, RLM/configurator stale transaction state veya native pricing context eksikliginden geliyor.

## RLM Pricing / Context Bulgulari

Default pricing setup:

- CalculationProcedure:
  - Id: `0k0aj000000I52wAAC`
  - Name: `Revenue Management Default Pricing Procedure V1`
  - UniqueName: `Revenue_Management_Default_Pricing_Procedure_V1`
- CalculationProcedureVersion:
  - Id: `0k1aj000000HkksAAC`
  - CalculationProcedureId: `0k0aj000000I52wAAC`
  - IsEnabled: true
  - VersionNumber: 1
  - Rank: 1
  - StartDateTime: `2025-02-02T20:56:40.000+0000`
  - EndDateTime: null

Context definitions:

- `RLM_SalesTransactionContext`
  - ContextDefinition Id: `11Oaj000000whZGEAY`
  - Active ContextDefinitionVersion: `11paj00000PLbpOAAT`
  - VersionNumber: 10
  - IsActive: true
- `RevSalesTransactionContext`
  - ContextDefinition Id: `11Oaj000000whZIEAY`
  - Active ContextDefinitionVersion: `11paj00000PLbpQAAT`
  - VersionNumber: 5
  - IsActive: true

Mappings:

- RLM QuoteEntitiesMapping:
  - Id: `11jaj000032RUAdAAO`
  - Title: `QuoteEntitiesMapping`
  - ContextDefinitionVersionId: `11paj00000PLbpOAAT`
  - Description: `Mapping to map quote and related entities with SalesTransaction context`
- RLM SalesTransaction:
  - Id: `11jaj000032RUAqAAO`
  - Title: `SalesTransaction`
  - ContextDefinitionVersionId: `11paj00000PLbpOAAT`
  - IsDefault: true
- Rev QuoteEntitiesMapping:
  - Id: `11jaj000032RUAoAAO`
  - Title: `QuoteEntitiesMapping`
  - ContextDefinitionVersionId: `11paj00000PLbpQAAT`
- Rev SalesTransaction:
  - Id: `11jaj000032RUAsAAO`
  - Title: `SalesTransaction`
  - ContextDefinitionVersionId: `11paj00000PLbpQAAT`
  - IsDefault: true

ContextNodeMapping icinde QuoteEntitiesMapping, su objeleri map ediyor:

- Quote -> SalesTransaction
- QuoteLineItem -> SalesTransactionItem
- QuoteLineItemAttribute -> SalesTransactionItemAttribute
- QuoteLineRelationship -> SalesTrxnItemRelationship
- QuoteLinePriceAdjustment -> SalesTransactionItemPriceAdjustment__std

Bu onemli:

- Native context mapping `QuoteLineRelationship` ve `QuoteLinePriceAdjustment` objelerini tanıyor.
- Dolayisiyla native RLM pricing engine teorik olarak bu kayitlari okuyabilecek durumda.

## ProcedurePlan / Product Discovery Bulgulari

Product Discovery plan tarafinda:

- ProcedurePlanSection kayitlari var.
- SectionType:
  - `ProductQualificationProcedure`
  - `PricingProcedure`
- Ama sorgulanan ProcedurePlanDefinitionVersion kayitlari `IsActive = false` dondu.
- ProcedurePlanOption kayitlarinda yalnizca `Product_Discovery_Pricing_Procedure` gorundu.
- Bu taraf daha once Browse Catalog icin kullanilmisti; quote pricing probleminden ayri olabilir.

Kesin sonuc:

- Browse/ProductDiscovery planlari bu bundle quote pricing sorununu tek basina aciklamiyor.

## Denenen Native Pricing Endpointleri

### 1. runSalesforcePricing

Endpoint:

```http
POST /services/data/v67.0/actions/standard/runSalesforcePricing
```

Request:

```json
{
  "inputs": [
    {
      "contextInstanceId": "0Q0aj000002hDwzCAE",
      "pricingProcedureName": "Revenue_Management_Default_Pricing_Procedure_V1",
      "isDeveloperName": true,
      "skipDiscovery": false,
      "isSkipWaterfall": false
    }
  ]
}
```

Result:

```text
NO_CONTEXT_RUNTIME_FOUND: This context instance is no longer active.
```

Yorum:

- Bu action quote Id degil, aktif runtime UI context instance Id bekliyor gibi.
- Quote Id ile calismadi.

### 2. runSalesforceHeadlessPricing

Endpoint:

```http
POST /services/data/v67.0/actions/standard/runSalesforceHeadlessPricing
```

Action describe sonucu gerekli input lar:

- `contextDefinitionId`
- `contextMappingId`
- `pricingProcedureId`
- `pricingData`

Deneme request:

```json
{
  "inputs": [
    {
      "contextDefinitionId": "11Oaj000000whZGEAY",
      "contextMappingId": "11jaj000032RUAdAAO",
      "pricingProcedureId": "0k1aj000000HkksAAC",
      "pricingData": "{\"Quote\":{\"Id\":\"0Q0aj000002hDwzCAE\"}}",
      "isSkipWaterfall": false,
      "useSessionScopedContext": false,
      "persistContext": false,
      "taggedData": false,
      "skipDiscovery": false,
      "displayContext": true,
      "isHighVolumeLineItems": false
    }
  ]
}
```

Ayni endpoint hem `CalculationProcedureVersion.Id` (`0k1...`) hem de `CalculationProcedure.Id` (`0k0...`) ile denendi.

Result:

```text
SF-Pricing-00004: We couldn't find the pricing procedure. Activate a pricing procedure for your org and set it as default, and try again.
```

Yorum:

- Procedure gercekte var ve active version enabled.
- Bu nedenle hata muhtemelen:
  - yanlis contextDefinition/contextMapping kombinasyonu,
  - yanlis `pricingData` JSON kok yapisi,
  - headless action in baska tip `pricingProcedureId` beklemesi,
  - veya Salesforce Pricing Setup default binding/cache sorunu.

### 3. createOrderFromQuote

Endpoint describe:

```http
GET /services/data/v67.0/actions/standard/createOrderFromQuote
```

Input:

- `quoteRecordId`

UI tarafinda Create Order hatasi:

```text
We couldn't create an order for this quote because the calculation status of the quote is invalid.
```

veya:

```text
We couldn't create an order from your quote because there are existing Revenue Transaction Error Logs. Resolve the errors and try again.
```

Guncel RevenueTransactionErrorLog sorgusunda Demo Quote 4/5 icin aktif log bulunmadi.

Bu nedenle su anki ana blokaj:

- `Quote.CalculationStatus = SaveFailedOrIncomplete`
- `Quote.ValidationResult = TransactionIncomplete`

Bu alanlar platform tarafindan yonetiliyor; direct Apex ile yazilamiyor.

## QuoteLinePriceAdjustment Bulgusu

`QuoteLinePriceAdjustment` objesi createable/updateable/queryable.

Writable alanlar:

- `QuoteLineItemId`
- `AdjustmentSource`
  - System
  - Discretionary
  - Promotion
  - Rule
- `AdjustmentType`
  - `AdjustmentPercentage`
  - `AdjustmentAmount`
  - `OverrideAmount`
- `AdjustmentAmountScope`
  - `Unit`
  - `Total`
  - `UnproratedTotal`
- `AdjustmentValue`
- `TotalAmount`
- `Priority`
- `Description`
- `PriceAdjustmentCauseId`

Mevcut parent quote line lar icin hic `QuoteLinePriceAdjustment` kaydi yok.

Onemli:

- ContextNodeMapping, `QuoteLinePriceAdjustment` objesini `SalesTransactionItemPriceAdjustment__std` node una map ediyor.
- Bu, attribute upcharge lari UnitPrice set etmek yerine native adjustment record olarak yazmanin daha dogru bir yol olabilecegini gosteriyor.

Ancak henuz test edilmedi:

- Parent line icin `QuoteLinePriceAdjustment` insert edilirse RLM reprice veya UI total bunu kabul eder mi?
- Insert sonrasi `Reprice All` veya `Update Prices` bunu quote total a yansitir mi?
- CalculationStatus CompletedWithPricing olur mu?

## Kesin Root Cause Degil Ama En Guclu Hipotezler

### Hipotez 1: Attribute rows var ama stale ValidationResult kaldi

Evidence:

- Child line larda required attribute rows var.
- UI hala missing attribute warning gosteriyor.
- `QuoteLineItem.ValidationResult` warning olan line larda hala `Warning`.

Olasilik:

- `ValidationResult` field i stale kaldi.
- Native configurator/session validation tekrar calismadan veya warning clear edilmeden grid warning gitmiyor.

Risk:

- Sadece `ValidationResult = null` yapmak sari uyariyi kaldirabilir ama quote `CalculationStatus` problemini cozmezse order yine fail eder.

### Hipotez 2: Apex UnitPrice degisiyor ama RLM pricing totals recalculation yapmiyor

Evidence:

- Parent `UnitPrice` dogru adjusted:
  - Home: 2099
  - Creator: 1949
- Fakat read-only RLM fields stale:
  - Home `NetUnitPrice = 1599`, `TotalPrice = 1599`
  - Creator `NetUnitPrice = 1449`, `TotalPrice = 1449`
- Quote TotalPrice de stale native total lari baz aliyor.

Olasilik:

- RLM pricing engine quote line update transactionindan sonra native total recompute etmiyor.
- `Reprice All` / `Update Prices` flow context i incomplete oldugu icin net/total fields update olmuyor.

### Hipotez 3: Attribute upcharge native adjustment record olarak yazilmali

Evidence:

- `QuoteLinePriceAdjustment` objesi var ve context mapping icinde map edilmis.
- RLM net/total fields muhtemelen `QuoteLinePriceAdjustment` uzerinden hesaplanmak istiyor.
- Biz su an sadece `UnitPrice` set ediyoruz.

Olasilik:

- Parent bundle attribute upcharge larini `QuoteLinePriceAdjustment` olarak yazarsak RLM total daha native hesaplanabilir.

Soru:

- `QuoteLinePriceAdjustment` records manuel/API ile insert edildikten sonra native pricing engine bunlari total a dahil ediyor mu?

### Hipotez 4: Headless pricing JSON kok yapisi yanlis

Evidence:

- `runSalesforceHeadlessPricing` endpoint schema dogru.
- Procedure active ve version enabled.
- Buna ragmen action "procedure bulunamadi" diyor.

Olasilik:

- `contextMappingId = QuoteEntitiesMapping` kullanirken `pricingData` kok objesi `"Quote"` degil `"SalesTransaction"` veya baska bir envelope bekliyor.
- `contextMappingId = SalesTransaction` kullanilirsa data yapisi farkli olmali.
- `pricingProcedureId` olarak action baska bir setup binding id si bekliyor olabilir.

### Hipotez 5: Salesforce Pricing Setup default binding/cache eksik veya bozuk

Evidence:

- UI setup tarafinda default pricing procedure gorunuyor.
- CalculationProcedureVersion active.
- Headless pricing "activate pricing procedure and set as default" diyor.

Olasilik:

- Setup UI default gorunse bile headless/runtime cache sync eksik.
- Salesforce Pricing Setup Sync veya ContextDefinitionSync sadece BrowseProducts icin basarili; SalesTransaction context icin sync kaydi gorunmedi.

## Denenmemis / Dikkatli Denenecek Adimlar

### A. Code fix: future decomposition icinde QuoteLineRelationship insert et

Su an relationship repair script ile mevcut quote larda yapildi.

Kalici hale getirmek icin:

- `QuoteLineItemTriggerHandler.autoDecomposeBundles` child insert ettikten sonra `QuoteLineRelationship` records insert etmeli.
- Bu sayede yeni quote larda child lines native parent-child relation ile dogar.

Beklenen fayda:

- Yeni quote larda native configurator/reprice child lines i daha dogru tanir.

Risk:

- Iliski alanlari yanlis set edilirse child lines duplicate veya invalid olabilir.
- Ama mevcut repair script ile bu model basarili insert oldu ve platform ParentQuoteLineItemId doldurdu.

### B. Current child line warnings safe clear

Sadece attribute lari tam olan child line larda:

- `QuoteLineItem.ValidationResult = null`

Beklenen fayda:

- Sari warning ikonlari UI grid den kalkabilir.

Risk:

- Bu sadece gorsel/validation flag temizligi olabilir.
- Quote CalculationStatus hala invalid kalirsa order yine fail eder.

### C. QuoteLinePriceAdjustment test

Kucuk test:

1. Parent line icin mevcut generated/manual adjustment yoksa insert:
   - `QuoteLineItemId = parent`
   - `AdjustmentSource = Rule`
   - `AdjustmentType = AdjustmentAmount`
   - `AdjustmentAmountScope = Unit`
   - `AdjustmentValue = 500`
   - `TotalAmount = 500`
   - `Priority = 1`
   - `Description = TechnoStore bundle attribute adjustment`
2. Parent UnitPrice i base price a geri cekmek gerekebilir:
   - Home: 1599
   - Creator: 1449
3. UI `Reprice All` veya API pricing denenir.

Beklenen:

- Native price waterfall adjustment olarak gorunebilir.
- NetUnitPrice/NetTotalPrice quote total a yansiyabilir.

Risk:

- Pricing engine bu adjustment lari sadece kendi olusturdugu zaman dikkate aliyor olabilir.
- Manual insert total a etki etmeyebilir.
- Yanlis olursa adjustment records kolayca delete edilebilir.

### D. Headless pricing mapping varyasyonlari

Denenecek kombinasyonlar:

1. RLM QuoteEntitiesMapping:
   - contextDefinitionId `11Oaj000000whZGEAY`
   - contextMappingId `11jaj000032RUAdAAO`
   - pricingProcedureId `0k1aj000000HkksAAC`
   - pricingData with root `SalesTransaction` instead of `Quote`

2. RLM SalesTransaction:
   - contextDefinitionId `11Oaj000000whZGEAY`
   - contextMappingId `11jaj000032RUAqAAO`

3. Rev QuoteEntitiesMapping:
   - contextDefinitionId `11Oaj000000whZIEAY`
   - contextMappingId `11jaj000032RUAoAAO`

4. Rev SalesTransaction:
   - contextDefinitionId `11Oaj000000whZIEAY`
   - contextMappingId `11jaj000032RUAsAAO`

Unknown:

- Correct `pricingData` schema for each mapping.
- Whether `pricingProcedureId` should be CP id, CPV id, or another setup binding id.

## Sister AI lara Sorulacak Net Sorular

### Soru 1

Salesforce RLM / Revenue Lifecycle Management `runSalesforceHeadlessPricing` action icin `pricingData` JSON schema tam olarak nasil olmali?

Bizim mapping:

- ContextDefinition: `RLM_SalesTransactionContext`
- ContextMapping: `QuoteEntitiesMapping`
- Mapping objects:
  - Quote -> SalesTransaction
  - QuoteLineItem -> SalesTransactionItem
  - QuoteLineItemAttribute -> SalesTransactionItemAttribute
  - QuoteLineRelationship -> SalesTrxnItemRelationship
  - QuoteLinePriceAdjustment -> SalesTransactionItemPriceAdjustment__std

Denediğimiz JSON:

```json
{
  "Quote": {
    "Id": "0Q0aj000002hDwzCAE"
  }
}
```

Hata:

```text
SF-Pricing-00004: We couldn't find the pricing procedure.
```

Bu JSON dogru mu, yoksa tam quote + lines + attributes + relationships payload mi verilmeli?

### Soru 2

`runSalesforceHeadlessPricing.pricingProcedureId` hangi record id olmalidir?

Denendi:

- CalculationProcedure Id: `0k0aj000000I52wAAC`
- CalculationProcedureVersion Id: `0k1aj000000HkksAAC`

Ikisi de procedure not found verdi.

Salesforce Pricing Setup icindeki default procedure binding id si baska bir obje midir?

### Soru 3

RLM quote line attribute upcharge lari icin dogru native persisted object hangisidir?

Opsiyonlar:

- `QuoteLineItem.UnitPrice` update etmek
- `QuoteLinePriceAdjustment` insert etmek
- `AttributeBasedAdjustment` / `AttributeAdjustmentCondition` setup objelerini kullanmak
- Configurator runtime context icinde transient price impact olusturmak

Context mapping `QuoteLinePriceAdjustment` i tanidigi icin bu obje dogru yol olabilir mi?

### Soru 4

`QuoteLineItemAttribute` kayitlari mevcut oldugu halde `QuoteLineItem.ValidationResult = Warning` ve UI "attribute missing" diyorsa, native RLM bu warning i nasil recompute/clear eder?

Direct update ile `ValidationResult = null` guvenli midir, yoksa native validation action mi calistirilmalidir?

### Soru 5

`QuoteLineRelationship` insert edildikten sonra platform child `ParentQuoteLineItemId` alanlarini dolduruyor. Bu, native bundle relationship icin yeterli midir?

Ek olarak gereken bir alan/obje var mi?

Ornek relationship fields:

- MainQuoteLineId
- AssociatedQuoteLineId
- RootQuoteLineId
- ProductRelatedComponentId
- ProductRelationshipTypeId
- AssociatedQuoteLinePricing
- AssociatedQuantScaleMethod

### Soru 6

Quote `CalculationStatus = SaveFailedOrIncomplete`, `ValidationResult = TransactionIncomplete`, fakat current `RevenueTransactionErrorLog` yoksa, native olarak bu state nasil reset/recompute edilir?

Direct field update mumkun degil.

Muhtemel action lar:

- Reprice All UI
- runSalesforcePricing with runtime context
- runSalesforceHeadlessPricing
- baska Revenue Cloud ConnectApi / REST endpoint

Hangisi dogru?

## Kisa Teknik Sonuc

Su ana kadar native bundle line structure buyuk olcude olustu:

- Child quote lines geliyor.
- Child `ParentQuoteLineItemId` dolu.
- `QuoteLineRelationship` records var.
- Required child attributes gercekte var.
- PBE ler dolu.

Ama native RLM calculation henuz tamamlanmiyor:

- Child `ValidationResult` bazi line larda stale `Warning`.
- Parent `UnitPrice` adjusted ama RLM `NetUnitPrice/TotalPrice` stale.
- Quote `CalculationStatus` invalid kaliyor.
- Create Order bu nedenle fail ediyor.

En muhtemel eksik:

1. Native pricing engine yeniden calistirilamadi.
2. Attribute upcharge lari `UnitPrice` yerine `QuoteLinePriceAdjustment` olarak modellenmeli olabilir.
3. Headless pricing action icin dogru `pricingData` / `pricingProcedureId` binding henuz bulunamadi.

## Dikkat Edilecekler

- `Quote.CalculationStatus`, `Quote.LastPricedDate`, `Quote.TotalPrice`, `Quote.GrandTotal` writeable degil.
- `QuoteLineItem.NetUnitPrice`, `NetTotalPrice`, `Subtotal`, `TotalPrice` writeable degil.
- Bu alanlari Apex ile force update edemeyiz.
- Apex ile sadece `UnitPrice`, `ValidationResult`, `DiscountAmount`, `PartnerUnitPrice`, `UnitPriceUplift` gibi alanlar update edilebilir.
- Bu nedenle gercek native sonuc icin RLM pricing/validation engine in calismasi gerekiyor.

## Sonraki Mantikli Yol

Kucuk ve geri alinabilir sirayla:

1. `QuoteLineRelationship` insert logic i handler a kalici ekle.
2. Attribute lari tam olan child line larda stale `ValidationResult` temizleme testi yap.
3. Sadece bir test quote veya bir parent line uzerinde `QuoteLinePriceAdjustment` denemesi yap.
4. Headless pricing icin dogru JSON schema bulunursa API ile reprice et.
5. Yeni temiz quote uzerinde bundle ekle, Configure, Update Prices, Reprice All, Create Order flow unu tekrar dene.

Custom bypass en son care:

- Native Create Order yerine custom Apex/Flow ile Order + OrderItem yaratmak mumkun olabilir.
- Ama bu demo icin native RLM flagship davranisi istendiginden simdilik tercih edilmedi.

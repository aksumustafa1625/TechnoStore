# ADR-033: RLM Bundle Pricing Forensic Debug Log and Lessons Learned

## Status

Accepted as forensic record - created 2026-06-30. This ADR documents what happened, what was tried, what was learned, and where the investigation stopped. It does not accept a final technical fix.

## Date

2026-06-30

## Author

Mustafa Aksu

## Context

TechnoStore needs a convincing native-looking Salesforce Revenue Lifecycle Management / Industries CPQ bundle demo. The target workflow is:

1. A sales rep opens a Quote.
2. The rep clicks Browse Catalogs.
3. The rep selects a bundle such as Home Office Bundle or Creator Studio Bundle.
4. The rep opens Configure.
5. The rep selects attributes such as Memory, Storage, Processor, Graphics, Screen Size, Display, or Subscription Type.
6. Child component products appear as quote lines.
7. Attribute upcharges affect the price.
8. Validation warnings disappear after required attributes are completed.
9. Quote pricing status becomes valid.
10. Native Create Order creates the order.

The demo matters because it is part of a DACH-focused Salesforce portfolio. The org contains many other integrations and demo assets, including SAP, tax, invoice, DocuSign, Lexoffice, DATEV, Notion, Jira, email, and webhook flows. Because the org is not disposable, destructive or broad experimental changes are unacceptable without explicit approval.

The bundle work reached a difficult middle state:

- Child lines can be created.
- Native relationship records can be created.
- Child `ParentQuoteLineItemId` can be made visible.
- Required attribute records can be present.
- Parent `UnitPrice` can be adjusted by Apex.
- But the RLM pricing runtime still does not complete the transaction.

This ADR captures the full debugging story so that any future engineer, AI assistant, reviewer, or Salesforce specialist can understand exactly what was done and why the investigation pivoted to context sync and pricing runtime diagnosis.

## Decision

Record the investigation as a forensic ADR separate from ADR-032.

ADR-032 is the high-level architectural decision: stop adding more repair logic and investigate Salesforce Pricing runtime/context sync first.

ADR-033 is the detailed operational memory: it preserves the data state, failed attempts, scripts, endpoint behavior, likely false leads, and concrete next steps.

This ADR is intentionally longer than a normal ADR. Its purpose is memory and handoff, not just decision rationale.

## Initial User-Facing Symptoms

### Symptom 1 - Bundle configure warning disappears in modal but quote line warning remains

The user observed that the bundle Configure page could be filled in without obvious errors, but the quote line grid still showed a yellow warning icon.

Example warning messages:

```text
One or more attributes for product Home Office Bundle are missing.
Specify these attributes and try again: Processor, Screen Size, Memory, Storage.
```

```text
One or more attributes for product TechNova ProBook 15 are missing.
Specify these attributes and try again: Processor, Screen Size.
```

```text
One or more attributes for product Monitor 27" 165Hz are missing.
Specify these attributes and try again: Display, Screen Size.
```

```text
One or more attributes for product TechCover 1 Year are missing.
Specify these attributes and try again: Subscription Type.
```

### Symptom 2 - Native Create Order fails

UI error:

```text
We couldn't create an order for this quote because the calculation status of the quote is invalid.
Ask your Salesforce admin for help.
```

Another UI error seen earlier:

```text
We couldn't create an order from your quote because there are existing Revenue Transaction Error Logs.
Resolve the errors and try again.
```

### Symptom 3 - Quote update fails with attribute picklist message

UI toast:

```text
Your quote was not updated.
Enter an Attribute Picklist Value that's in an active or draft state.
```

This was confusing because many relevant AttributePicklistValue records were already in Draft or Active status, which should be acceptable according to the message.

### Symptom 4 - Price updates are partial

The Configure summary can show selected attributes and sometimes component prices, but the quote line grid and quote totals remain inconsistent.

Examples:

- Parent bundle `UnitPrice` changes to the expected adjusted value.
- Parent `NetUnitPrice`, `NetTotalPrice`, `Subtotal`, and `TotalPrice` remain at the original base price.
- Quote total uses the stale native total fields, not the adjusted parent `UnitPrice`.

This became the strongest evidence that Apex was updating an editable field but the RLM pricing engine was not recomputing the native pricing waterfall.

## Important Files and Scripts

### Main code

- `force-app-handlers/main/default/classes/QuoteLineItemTriggerHandler.cls`
- `force-app-actions/main/default/classes/BundleDecompositionAction.cls`

### Key diagnostic and repair scripts

- `scripts/describe_quote_pricing_fields.apex`
- `scripts/describe_bundle_relationship_fields.apex`
- `scripts/repair_native_bundle_relationships.apex`
- `scripts/repair_existing_bundle_child_default_attrs.apex`
- `scripts/reprice_existing_bundle_parent_totals.apex`
- `scripts/touch_current_demo_quote_lines_for_recalc.apex`
- `scripts/clear_demo_quote_rte_logs.apex`
- `scripts/diagnose_rlm_pricing_context_readonly.apex`
- `scripts/diagnose_rlm_pricing_context_focused_readonly.apex`

### REST request and output files

- `scripts/request_run_pricing_quote5.json`
- `scripts/request_headless_pricing_quote5_quote_entities.json`
- `scripts/describe_runSalesforceHeadlessPricing.out.json`
- `scripts/describe_runSalesforcePricing.out.json`
- `scripts/query_context_definition_sync.out.json`
- `scripts/diagnose_rlm_pricing_context_focused_readonly.out.txt`

### Research / handoff docs

- `troubleshot.md`
- `research_rlm_pricing.md`
- `docs/adr/ADR-032-rlm-bundle-pricing-research-first-diagnostic.md`
- This file, `docs/adr/ADR-033-rlm-bundle-pricing-forensic-debug-log.md`

## What Was Changed Before This ADR

### Bundle decomposition was added to QuoteLineItemTriggerHandler

The handler detects newly inserted quote lines whose product type is Bundle. It then:

- Reads `ProductRelatedComponent` records.
- Finds active `PricebookEntry` records for child products in the quote pricebook.
- Inserts child `QuoteLineItem` records asynchronously.
- Sets included children to `UnitPrice = 0`.
- Sets add-on children to their pricebook unit price.
- Adds default child `QuoteLineItemAttribute` records based on product code.

Why async:

- The Configure UI has its own transaction/session state.
- Inserting child lines synchronously inside the same configure save transaction caused inconsistent UI behavior.
- A future transaction allowed the configurator transaction to finish before children were added.

Trade-off:

- Async decomposition may run after the native pricing runtime already built its context, so RLM pricing may not see the child lines during the original pricing transaction.

This timing issue remains a serious hypothesis.

### Duplicate bundle cleanup was added

The UI sometimes appeared to create duplicate bundle parent lines after Save & Exit. Logic was added to preserve the original and clean later duplicates.

This reduced duplicate rows but also made the flow more custom and therefore harder to reason about as native RLM behavior.

### Parent UnitPrice adjustment was added

The handler adjusts bundle parent `QuoteLineItem.UnitPrice` based on selected attributes.

Examples:

Home Office Bundle:

- Base price: 1599
- RAM 16GB: +100
- Storage 512GB: +100
- Processor i7: +200
- Screen Size 15 Inch: +100
- Expected adjusted `UnitPrice`: 2099

Creator Studio Bundle:

- Base price: 1449
- Same selected attribute uplift: +500
- Expected adjusted `UnitPrice`: 1949

What worked:

- Parent `UnitPrice` became 2099 / 1949.

What did not work:

- `NetUnitPrice`, `NetTotalPrice`, `Subtotal`, and `TotalPrice` did not update.
- Quote totals did not reflect the adjusted parent `UnitPrice`.
- Create Order still failed.

Key lesson:

Updating `UnitPrice` is not equivalent to completing the RLM pricing waterfall.

### Default child attributes were inserted

Default child attributes were added to reduce validation warnings.

Examples:

`COMP-LAP-001` / TechNova ProBook 15:

- Memory = RAM 16GB
- Storage = SSD Hard Drive 512GB
- Processor = i7-CPU 4.7GHz
- Screen Size = 15 Inch

`COMP-LAP-003` / SlimAir UltraBook 14:

- Memory = RAM 8GB
- Storage = SSD Hard Drive 256GB
- Processor = i5-CPU 4.4GHz
- Screen Size = 13 Inch

`AV-MON-001` / Monitor:

- Display = 2k Built-in Display
- Screen Size = 27 Inch

`SVC-WAR-001` / TechCover:

- Subscription Type = Business

The attribute rows exist, but some line warnings remain. That suggests stale validation status or incomplete native validation runtime, not simply missing rows.

## Native Bundle Relationship Repair

### Problem before repair

Child quote lines existed, but native relationship fields were not populated in a way the UI/runtime fully understood.

Observed issue:

- Child lines did not reliably show as native bundle components.
- `ParentQuoteLineItemId` was null in earlier states.
- Pricing and validation did not treat the group as a coherent native bundle.

### Object discovered

`QuoteLineRelationship` was found to be createable and relevant.

Important writable fields:

- `MainQuoteLineId`
- `AssociatedQuoteLineId`
- `RootQuoteLineId`
- `ProductRelatedComponentId`
- `ProductRelationshipTypeId`
- `AssociatedQuoteLinePricing`
- `AssociatedQuantScaleMethod`

### Repair script

Script:

- `scripts/repair_native_bundle_relationships.apex`

What it inserted:

- 8 `QuoteLineRelationship` rows.

Quote 4:

- Creator Studio Bundle -> SlimAir UltraBook 14
- Creator Studio Bundle -> WebCam Pro 4K Studio
- Creator Studio Bundle -> Monitor 27" 165Hz

Quote 5:

- Home Office Bundle -> TechNova ProBook 15
- Home Office Bundle -> Wireless Combo Set
- Home Office Bundle -> TechCover 1 Year
- Home Office Bundle -> ErgoMouse Vertical
- Home Office Bundle -> WebCam Pro 4K Studio

Important field values:

- `MainQuoteLineId = parent`
- `AssociatedQuoteLineId = child`
- `RootQuoteLineId = parent`
- `ProductRelatedComponentId = matching ProductRelatedComponent`
- `ProductRelationshipTypeId = component.ProductRelationshipTypeId`
- `AssociatedQuantScaleMethod = Constant`
- `AssociatedQuoteLinePricing = IncludedInBundlePrice` for included children
- `AssociatedQuoteLinePricing = NotIncludedInBundlePrice` for paid add-ons

### Result of repair

Good result:

- Platform showed `ParentQuoteLineItemId` populated on child lines.
- Relationship roles appeared native:
  - `MainQuoteLineRole = Bundle`
  - `AssociatedQuoteLineRole = BundleComponent`
- Price inclusiveness matched expectations:
  - Included child lines were price-inclusive.
  - Paid add-ons were not price-inclusive.

Important lesson:

`QuoteLineRelationship` appears necessary and effective for native-looking bundle structure. However, it was not sufficient to make pricing calculation complete.

## Current Quote State

### Demo Quote 4

Quote:

- Id: `0Q0aj000002hDwyCAE`
- Name: Demo Quote 4
- Status: Approved
- `CalculationStatus = SaveFailedOrIncomplete`
- `ValidationResult = TransactionIncomplete`
- `LastPricedDate = null`
- `TotalPrice = 1898`
- `Tax = 360.62`
- `GrandTotal = 2258.62`

Parent line:

- Product: Creator Studio Bundle
- QLI Id: `0QLaj00000332ErGAI`
- ProductCode: `BUNDLE-CREATOR-001`
- Product type: Bundle
- `UnitPrice = 1949`
- `NetUnitPrice = 1449`
- `NetTotalPrice = 1449`
- `Subtotal = 1449`
- `TotalPrice = 1449`
- `ValidationResult = null`

Child lines:

SlimAir UltraBook 14:

- QLI Id: `0QLaj00000332GTGAY`
- ProductCode: `COMP-LAP-003`
- `ParentQuoteLineItemId = 0QLaj00000332ErGAI`
- `UnitPrice = 0`
- `NetUnitPrice = 0`
- `TotalPrice = 0`
- `ValidationResult = Warning`

WebCam Pro 4K Studio:

- QLI Id: `0QLaj00000332GUGAY`
- `ParentQuoteLineItemId = 0QLaj00000332ErGAI`
- `UnitPrice = 0`
- `ValidationResult = null`

Monitor 27" 165Hz:

- QLI Id: `0QLaj00000332GVGAY`
- ProductCode: `AV-MON-001`
- `ParentQuoteLineItemId = 0QLaj00000332ErGAI`
- `UnitPrice = 449`
- `NetUnitPrice = 449`
- `TotalPrice = 449`
- `ValidationResult = Warning`

Critical arithmetic:

- Expected adjusted parent price: 1449 + 500 = 1949.
- Actual parent `UnitPrice`: 1949.
- Native parent `TotalPrice`: 1449.
- Quote total behaves like 1449 + 449 = 1898.

Conclusion:

- Apex adjustment is visible on `UnitPrice`.
- Native totals ignore that adjusted `UnitPrice`.

### Demo Quote 5

Quote:

- Id: `0Q0aj000002hDwzCAE`
- Name: Demo Quote 5
- Status: Approved
- `CalculationStatus = SaveFailedOrIncomplete`
- `ValidationResult = TransactionIncomplete`
- `LastPricedDate = null`
- `TotalPrice = 1648`
- `Tax = 313.12`
- `GrandTotal = 1961.12`

Parent line:

- Product: Home Office Bundle
- QLI Id: `0QLaj00000332I5GAI`
- ProductCode: `BUNDLE-OFFICE-001`
- Product type: Bundle
- `UnitPrice = 2099`
- `NetUnitPrice = 1599`
- `NetTotalPrice = 1599`
- `Subtotal = 1599`
- `TotalPrice = 1599`
- `ValidationResult = null`

Child lines:

TechNova ProBook 15:

- QLI Id: `0QLaj00000332JhGAI`
- ProductCode: `COMP-LAP-001`
- `ParentQuoteLineItemId = 0QLaj00000332I5GAI`
- `UnitPrice = 0`
- `ValidationResult = Warning`

Wireless Combo Set:

- QLI Id: `0QLaj00000332JiGAI`
- `ParentQuoteLineItemId = 0QLaj00000332I5GAI`
- `UnitPrice = 0`
- `ValidationResult = null`

TechCover 1 Year:

- QLI Id: `0QLaj00000332JjGAI`
- ProductCode: `SVC-WAR-001`
- `ParentQuoteLineItemId = 0QLaj00000332I5GAI`
- `UnitPrice = 49`
- `NetUnitPrice = 49`
- `TotalPrice = 49`
- `ValidationResult = Warning`

ErgoMouse Vertical:

- QLI Id: `0QLaj00000332JkGAI`
- `ParentQuoteLineItemId = 0QLaj00000332I5GAI`
- `UnitPrice = 0`
- `ValidationResult = null`

WebCam Pro 4K Studio:

- QLI Id: `0QLaj00000332JlGAI`
- `ParentQuoteLineItemId = 0QLaj00000332I5GAI`
- `UnitPrice = 0`
- `ValidationResult = null`

Critical arithmetic:

- Expected adjusted parent price: 1599 + 500 = 2099.
- Actual parent `UnitPrice`: 2099.
- Native parent `TotalPrice`: 1599.
- Quote total behaves like 1599 + 49 = 1648.

Conclusion:

- Same pattern as Quote 4. The issue is systematic, not a one-off line defect.

## QuoteLineItemAttribute Findings

### Describe result

Writable fields:

- `ExternalId`
- `AttributeValue`
- `AttributeDefinitionId`
- `AttributePicklistValueId`

Important read-only/platform-managed fields:

- `AttributeName`
- `IsPriceImpacting`

### Parent attributes exist

Parent bundle lines contain:

- Memory = RAM 16GB
- Storage = SSD Hard Drive 512GB
- Processor = i7-CPU 4.7GHz
- Screen Size = 15 Inch

Observed concern:

- `IsPriceImpacting` is true for Memory in some rows.
- Other attributes often show `IsPriceImpacting = false`.

Interpretation:

- This may matter for native pricing.
- It does not explain why Apex-computed `UnitPrice` worked but native totals stayed stale.

### Child attributes exist

Required child attributes exist for:

- TechNova ProBook 15
- SlimAir UltraBook 14
- Monitor 27" 165Hz
- TechCover 1 Year

Interpretation:

- The UI warning "attributes missing" is not simply true at the database row level.
- It is likely a native validation/context/cache state issue or a mismatch between what the configurator expects and what was inserted after the native transaction.

## AttributePicklistValue Findings

Relevant picklist values were Active or Draft.

Examples:

- Business = Active
- RAM 16GB = Draft
- SSD Hard Drive 512GB = Draft
- i7-CPU 4.7GHz = Draft
- 15 Inch = Draft
- RAM 8GB = Draft
- SSD Hard Drive 256GB = Draft
- i5-CPU 4.4GHz = Draft
- 13 Inch = Draft
- 2k Built-in Display = Draft
- 27 Inch = Draft

UI error said:

```text
Enter an Attribute Picklist Value that's in an active or draft state.
```

Interpretation:

- The status values themselves do not appear invalid.
- The message may be thrown because the pricing/configuration transaction cannot bind the inserted attribute values into its active context.
- Another possibility is that some UI-selected value is not the same record as the inserted `AttributePicklistValueId`.

## Pricebook Findings

All current quote lines had `PricebookEntryId` populated during diagnostics.

Examples:

- Creator Studio Bundle PBE: `01uaj0000074OcSAAU`
- Home Office Bundle PBE: `01uaj0000074OcQAAU`
- SlimAir PBE: `01uaj000007C8yhAAC`
- TechNova PBE: `01uaj000007C8yfAAC`
- WebCam PBE: `01uaj000007C8zJAAS`
- Monitor PBE: `01uaj000007C8zDAAS`
- TechCover PBE: `01uaj0000074KC8AAM`

UI sometimes showed:

```text
Required fields are missing: [Price Book Entry]
```

Interpretation:

- The live records do not support a simple "PBE missing" explanation.
- The toast may come from stale client/runtime state, not the final committed rows.
- Another possibility is that a transient line in the configure transaction lacked PBE before repair logic completed.

## Salesforce Pricing Runtime Findings

### Calculation procedure exists

Revenue pricing procedure:

- `CalculationProcedure.Id = 0k0aj000000I52wAAC`
- Name: `Revenue Management Default Pricing Procedure V1`
- UniqueName: `Revenue_Management_Default_Pricing_Procedure_V1`

Enabled version:

- `CalculationProcedureVersion.Id = 0k1aj000000HkksAAC`
- VersionNumber = 1
- `IsEnabled = true`
- `Rank = 1`
- StartDateTime = `2025-02-02 20:56:40`

Interpretation:

- The pricing procedure record is not absent.
- "Procedure not found" likely means the action cannot resolve it in runtime context.

### Context definitions exist

Relevant context definitions:

`RLM_SalesTransactionContext`:

- ContextDefinition Id: `11Oaj000000whZGEAY`
- Active version: `11paj00000PLbpOAAT`
- VersionNumber = 10
- IsActive = true

`RevSalesTransactionContext`:

- ContextDefinition Id: `11Oaj000000whZIEAY`
- Active version: `11paj00000PLbpQAAT`
- VersionNumber = 5
- IsActive = true

`BrowseProductsCtxDefinition`:

- ContextDefinition Id: `11Oaj000000whZFEAY`
- Active version: `11paj00000PLbpNAAT`
- VersionNumber = 11

### Context sync evidence

Read-only query returned exactly one `ContextDefinitionSync` row:

```text
ContextDefinitionName = BrowseProductsCtxDefinition
Status = success
StartDateTime = 2026-06-17T11:24:05.000+0000
EndDateTime = 2026-06-17T11:24:07.000+0000
```

No sync row was found for:

- `RLM_SalesTransactionContext`
- `RevSalesTransactionContext`

Interpretation:

- Browse catalog/product discovery context was synced.
- SalesTransaction pricing context may not be synced into runtime.
- This is currently the strongest next diagnostic path.

### Context mappings exist

Known mappings:

RLM:

- QuoteEntitiesMapping: `11jaj000032RUAdAAO`
- SalesTransaction default mapping: `11jaj000032RUAqAAO`

Rev:

- QuoteEntitiesMapping: `11jaj000032RUAoAAO`
- SalesTransaction default mapping: `11jaj000032RUAsAAO`

Known node mappings include:

- Quote -> SalesTransaction
- QuoteLineItem -> SalesTransactionItem
- QuoteLineItemAttribute -> SalesTransactionItemAttribute
- QuoteLineRelationship -> SalesTrxnItemRelationship
- QuoteLinePriceAdjustment -> SalesTransactionItemPriceAdjustment__std

Interpretation:

- The context model knows about quote lines, attributes, relationships, and price adjustments.
- This supports the theory that `QuoteLineRelationship` and `QuoteLinePriceAdjustment` are part of the native data graph.

## Standard Action Findings

### runSalesforcePricing

Action category:

- Salesforce Pricing

Required inputs:

- `contextInstanceId`
- `pricingProcedureName`

Earlier attempt:

```json
{
  "contextInstanceId": "0Q0aj000002hDwzCAE",
  "pricingProcedureName": "Revenue_Management_Default_Pricing_Procedure_V1",
  "isDeveloperName": true
}
```

Result:

```text
NO_CONTEXT_RUNTIME_FOUND: This context instance is no longer active.
```

Interpretation:

- Quote Id is not a runtime context instance Id.
- This action is likely meant for a UI/session-created context.
- It is not the best API for headless quote reprice from a saved Quote Id.

### runSalesforceHeadlessPricing

Action category:

- Salesforce Pricing

Required inputs:

- `contextDefinitionId`
- `contextMappingId`
- `pricingProcedureId`
- `pricingData`

Important optional inputs:

- `isSkipWaterfall`
- `useSessionScopedContext`
- `persistContext`
- `taggedData`
- `discoveryProcedure`
- `skipDiscovery`
- `effectiveDate`
- `displayContext`
- `isHighVolumeLineItems`

Earlier attempt:

```json
{
  "contextDefinitionId": "11Oaj000000whZGEAY",
  "contextMappingId": "11jaj000032RUAdAAO",
  "pricingProcedureId": "0k1aj000000HkksAAC",
  "pricingData": "{\"Quote\":{\"Id\":\"0Q0aj000002hDwzCAE\"}}",
  "displayContext": true
}
```

Also tried:

- `pricingProcedureId = 0k0aj000000I52wAAC`

Result:

```text
SF-Pricing-00004: We couldn't find the pricing procedure.
Activate a pricing procedure for your org and set it as default, and try again.
```

Interpretation:

- The procedure exists and has an enabled version.
- The error may be caused by:
  - Wrong payload root.
  - Wrong context mapping.
  - Missing SalesTransaction context sync.
  - Missing default binding.
  - Wrong expected `pricingProcedureId` record type.
  - A Salesforce runtime cache issue.

### createOrderFromQuote

Required input:

- `quoteRecordId`

Interpretation:

- Create Order is not a repair action.
- It expects the quote to already be in a valid calculation state.
- It fails when `CalculationStatus` is invalid.

## RevenueTransactionErrorLog Findings

Recent logs included old errors:

```text
Exception while fetching matching records from Decision Table ID: 0lDaj000000DanFEAS
Invalid Configuration. Please see Configurator ErrorMessage for details.
```

However, later focused investigation did not show an active current RTE directly explaining Quote 4/5 after cleanup.

Interpretation:

- Earlier transaction errors existed.
- Current primary blocker is the quote calculation/validation state, not necessarily an active RTE row.
- RTE logs should still be checked after every new pricing attempt.

## QuoteLinePriceAdjustment Findings

`QuoteLinePriceAdjustment` is:

- Queryable
- Createable
- Updateable

Relevant writable fields:

- `QuoteLineItemId`
- `AdjustmentSource`
- `AdjustmentType`
- `AdjustmentAmountScope`
- `AdjustmentValue`
- `TotalAmount`
- `Priority`
- `Description`
- `PriceAdjustmentCauseId`

Relevant picklists:

`AdjustmentSource`:

- System
- Discretionary
- Promotion
- Rule

`AdjustmentType`:

- AdjustmentPercentage
- AdjustmentAmount
- OverrideAmount

`AdjustmentAmountScope`:

- Unit
- Total
- UnproratedTotal

Current state:

- No QLPA rows existed for the current bundle parent lines during diagnostic.

Interpretation:

- QLPA is a plausible native way to represent attribute uplift.
- But manual QLPA insert is not accepted as a fix yet.
- It should be tested only on a clean, reversible quote after pricing context behavior is better understood.

## Sister-AI Review Summary

External/sister AI feedback converged on several points:

1. The bundle skeleton is mostly correct now.
2. The root blocker is pricing runtime completion.
3. Updating `UnitPrice` is insufficient for RLM native totals.
4. `QuoteLinePriceAdjustment` is a plausible more-native representation for uplifts.
5. Old repaired quotes may be unreliable test beds.
6. `ValidationResult = null` can hide warnings but not fix `CalculationStatus`.
7. Headless pricing likely needs the correct context mapping and payload graph.
8. Context sync/default binding is a strong suspect.

Where the advice differed:

- Some suggested clearing `ValidationResult` sooner.
- Others warned it would only mask symptoms.
- Some suggested immediate QLPA insertion.
- Others recommended context sync first.

Chosen interpretation:

- Do not hide warnings first.
- Do not add QLPA permanently yet.
- Investigate SalesTransaction context sync/default binding first.

## Public Web Research Summary

Broad searches were performed across:

- Salesforce Help
- Salesforce Developer Docs
- Trailhead / Trailblazer public pages
- Salesforce StackExchange
- GitHub
- General web search

Terms searched included:

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

Result:

- No public, exact, actionable solution was found for this RLM-specific action/payload problem.

Interpretation:

- This problem is niche.
- RLM documentation may be behind login or partner/customer channels.
- Org runtime metadata is more useful than public search for this specific issue.

## What We Now Know For Sure

1. The child quote lines exist.
2. Native `QuoteLineRelationship` rows can be inserted.
3. After relationship insertion, child `ParentQuoteLineItemId` is populated.
4. Required `QuoteLineItemAttribute` rows exist for warned lines.
5. Current quote lines have `PricebookEntryId`.
6. Parent `UnitPrice` can be adjusted by Apex.
7. Parent native totals do not follow the adjusted `UnitPrice`.
8. Quote totals do not follow adjusted parent `UnitPrice`.
9. Quote `CalculationStatus` remains invalid.
10. Create Order fails because calculation status is invalid.
11. `runSalesforcePricing` is not usable with a plain Quote Id.
12. `runSalesforceHeadlessPricing` exists and has a clear input contract, but the correct payload/binding is still unknown.
13. Only `BrowseProductsCtxDefinition` has a visible sync row.
14. SalesTransaction context sync is currently the strongest suspect.

## What We Do Not Know Yet

1. Whether `RLM_SalesTransactionContext` or `RevSalesTransactionContext` is the correct runtime context for quote pricing in this org.
2. Whether SalesTransaction context sync is required and missing.
3. Where in Setup the official sync/default binding UI for SalesTransaction context lives.
4. Whether `pricingProcedureId` should be the procedure Id, version Id, or another setup/binding record.
5. The exact `pricingData` JSON schema expected by `runSalesforceHeadlessPricing`.
6. Whether minimal quote Id payload is supported.
7. Whether full quote graph payload is required.
8. Whether `QuoteLinePriceAdjustment` will be honored if inserted manually.
9. Whether old Quote 4/5 can ever be recovered, or only new clean quotes can validate correctly.
10. Whether the async timing of child decomposition prevents the native pricing context from seeing the children.

## Major Lessons Learned

### Lesson 1 - Native-looking data is not the same as native runtime completion

It is possible to make the database shape look close to native:

- Parent quote line.
- Child quote lines.
- Parent-child relationship.
- Attribute rows.
- Pricebook entries.

But RLM still requires its pricing runtime to process that graph successfully. Without that runtime pass, managed fields remain stale and Create Order fails.

### Lesson 2 - Editable fields can be misleading

`QuoteLineItem.UnitPrice` is editable. Updating it gives a satisfying visible clue, but RLM's important totals are in read-only fields:

- `NetUnitPrice`
- `NetTotalPrice`
- `Subtotal`
- `TotalPrice`

If those do not move, the platform still considers pricing incomplete.

### Lesson 3 - Warning cleanup is not root-cause repair

`ValidationResult = Warning` may be stale. But clearing it manually would not prove native validation completed. It could make the UI quieter while leaving `CalculationStatus` invalid.

### Lesson 4 - Existing repaired quotes are poor final test cases

Demo Quote 4 and Demo Quote 5 are useful forensic records, but they have seen multiple repair attempts. A clean quote is needed for final validation after context/pricing setup is corrected.

### Lesson 5 - Context sync is probably more important than product data now

Product, pricebook, component, relationship, and attribute data are largely present. The missing visible sync for SalesTransaction context may explain why Browse Catalog works while quote pricing does not.

## Recommended Next Session Flow

### Step 1 - Do not change data immediately

Start by re-reading:

- ADR-032
- ADR-033
- `research_rlm_pricing.md`
- `troubleshot.md`

### Step 2 - Inspect UI setup

Look for:

- Salesforce Pricing Setup
- Context Definitions
- `RLM_SalesTransactionContext`
- `RevSalesTransactionContext`
- Sync / Activate / Default controls
- Default pricing procedure binding
- Last sync timestamps

Goal:

- Find an official UI path to sync SalesTransaction pricing context.

### Step 3 - If UI sync is found, ask for explicit approval before clicking

Even though sync is lower risk than DML scripts, it changes runtime cache and should be approved.

Expected post-sync evidence:

- New `ContextDefinitionSync` row for `RLM_SalesTransactionContext` or `RevSalesTransactionContext`.

### Step 4 - Create a clean test quote

After sync/default binding is confirmed:

- Create a new quote.
- Add one bundle.
- Configure attributes through UI.
- Save & Exit.
- Use Update Prices / Reprice All.
- Try Create Order.

Avoid using Quote 4/5 as the first validation case.

### Step 5 - Only then test QLPA

If pricing runtime works but attribute uplift still does not flow correctly:

- Test `QuoteLinePriceAdjustment` on one clean quote.
- Keep it reversible.
- Do not add it permanently to handler until proven.

### Step 6 - Only then consider validation cleanup

If all required attributes exist and pricing completes but warnings remain:

- Consider clearing stale `ValidationResult`.
- This should be a final cleanup, not a root-cause fix.

## Known Risk Areas

### Async decomposition timing

Because child lines are inserted after the native configure transaction, RLM may create pricing context before children/relationships exist.

Possible future mitigation:

- Find a native way to let configurator create child lines.
- Or insert relationships immediately in the same async transaction and run a successful reprice afterward.

### Native Pricing Procedure Builder bug history

ADR-002 and ADR-016 document earlier issues where native Pricing Procedure Builder showed 0 steps or did not execute expected native attribute pricing logic. This org has a history of pricing procedure/runtime weirdness.

Implication:

- If context sync does not fix the problem, the org may have a broader Developer Edition / feature-flag limitation.

### Manual repair debt

Every repair script makes the quote less representative of a clean native transaction. The current quotes are valuable evidence but not ideal final demos.

### Custom Create Order temptation

A custom order creation path could bypass the issue, but it would weaken the native RLM demo. It remains the last fallback only.

## Final State at Time of ADR

No final fix accepted.

Current accepted direction:

- Pause broad Apex repair.
- Research and diagnose SalesTransaction pricing context.
- Use read-only checks first.
- Prefer official sync/default binding path.
- Validate on a clean quote.
- Keep QLPA and validation cleanup as controlled later experiments.

## References

- ADR-002: `docs/adr/ADR-002-custom-metadata-over-attribute-based-adjustment.md`
- ADR-016: `docs/adr/ADR-016-pricing-apex-workaround.md`
- ADR-032: `docs/adr/ADR-032-rlm-bundle-pricing-research-first-diagnostic.md`
- `troubleshot.md`
- `research_rlm_pricing.md`
- `scripts/diagnose_rlm_pricing_context_readonly.apex`
- `scripts/diagnose_rlm_pricing_context_focused_readonly.apex`
- `scripts/diagnose_rlm_pricing_context_focused_readonly.out.txt`
- `scripts/describe_runSalesforceHeadlessPricing.out.json`
- `scripts/describe_runSalesforcePricing.out.json`
- `scripts/query_context_definition_sync.out.json`
- `scripts/repair_native_bundle_relationships.apex`
- `scripts/repair_existing_bundle_child_default_attrs.apex`
- `scripts/reprice_existing_bundle_parent_totals.apex`

## 2026-06-30 Continuation - Native Pricing Binding and Quote 5 Bundle Relationship Repair

This section records the next investigation session after the research-first pause. The goal was still to avoid broad custom workaround logic and first prove whether native Salesforce Pricing / Context Service could be made to calculate the bundle correctly.

### User Approval and Scope

The user explicitly approved continuing with Salesforce CLI/API checks and narrowly scoped org changes. The work stayed focused on:

- Quote 5: `0Q0aj000002hDwzCAE`
- Home Office Bundle parent product: `01taj00000Qp7IFAAZ`
- Native pricing context/procedure binding
- Native bundle relationship records

No destructive cleanup was performed.

### PricingActionParameters Binding Was Created

A native `PricingActionParameters` record was created for Quote pricing:

- Id: `17gaj00000069ILAAY`
- ObjectName: `Quote`
- ContextDefinition: `RevSalesTransactionContext`
- ContextMapping: `QuoteEntitiesMapping`
- PricingProcedure: `Rev_Mgmt_Default_Pricing_Procedure2`
- EffectiveFrom: `2026-06-30T00:00:00.000+0000`

Important observation:

- The platform accepted `RevSalesTransactionContext + QuoteEntitiesMapping + Rev_Mgmt_Default_Pricing_Procedure2`.
- This confirms the earlier `RLM_SalesTransactionContext + Revenue_Management_Default_Pricing_Procedure_V1` attempt was the wrong binding for this org.
- Salesforce rewrote the visible `DeveloperName` / `MasterLabel` to `Quote_1782820367004`, but retained the important context/procedure fields.

Request file:

- `scripts/create_pricing_action_parameters_quote_rev.request.json`

### Correct Pricing Procedure API Name

The active default pricing procedure is not addressed by the CalculationProcedure unique name in the headless action. The accepted API value is:

- `Rev_Mgmt_Default_Pricing_Procedure2`

The following values were tested and failed:

- `Revenue_Management_Default_Pricing_Procedure_V1`
- CalculationProcedure Id `0k0aj000000I52wAAC`
- CalculationProcedureVersion Id `0k1aj000000HkksAAC`
- ExpressionSetVersion API name `Rev_Mgmt_Default_Pricing_Procedure2_V1`

The active metadata behind the accepted name:

- ExpressionSetDefinition Id: `9QAaj000000FAyLGAW`
- ExpressionSetDefinition DeveloperName: `Rev_Mgmt_Default_Pricing_Procedure2`
- ExpressionSetDefinitionVersion Id: `9QBaj0000008qJGGAY`
- ExpressionSetDefinitionVersion DeveloperName: `Rev_Mgmt_Default_Pricing_Procedure2_V1`
- ExpressionSetVersion Id: `9QMaj000000Vq0oGAC`
- ExpressionSetVersion ApiName: `Rev_Mgmt_Default_Pricing_Procedure2_V1`

### Discovery Procedure Finding

When `runSalesforceHeadlessPricing` was called without `skipDiscovery`, the action failed with:

```text
The rule API name Default Discovery Procedure is invalid. Specify a valid API name and try again.
```

The actual DeveloperName exists as:

- `Default_Discovery_Procedure`

Passing `discoveryProcedure = Default_Discovery_Procedure` avoided the invalid-rule-name error, but the pricing run still failed later with the output-tag exception.

Request files:

- `scripts/run_headless_pricing_quote5_rev_exprset_with_discovery.request.json`
- `scripts/run_headless_pricing_quote5_rev_exprset_explicit_discovery.request.json`

### Persistent Pricing Runtime Failure

Even after the correct pricing procedure and explicit discovery procedure were used, `runSalesforceHeadlessPricing` continued to fail with:

```text
SF-Pricing-00008: The output tags for the pricing procedure aren't valid. Ask your Salesforce admin to update the output tags.
java.util.NoSuchElementException: No value present
```

Variants tested:

- `skipDiscovery=true`
- explicit `discoveryProcedure=Default_Discovery_Procedure`
- `persistContext=true`
- `displayContext=true`
- `useSessionScopedContext=true`
- `pricingData` as `{"Quote":{"Id":"..."}}`
- `pricingData` as `{"Quote":[{"Id":"..."}]}`

All still failed with `SF-Pricing-00008`, except the version API name test, which failed earlier as an invalid rule API name.

Interpretation:

- The procedure name and context binding are now mostly correct.
- The remaining failure is likely one of:
  - SalesTransaction context runtime/tag cache is not properly synced.
  - The default pricing procedure has an invalid or incomplete output tag mapping.
  - The headless pricing API needs a richer tagged pricingData payload than a root Quote Id.
  - This Developer Edition / Spring 26 RLM environment has a native runtime defect around output tag extraction.

### Context Service Limitation Observed

`buildContext` with `RevSalesTransactionContext + QuoteEntitiesMapping + Quote 5` succeeded and returned a context id.

However, both `runSalesforcePricing` and `queryContextTags` failed immediately afterward with expired/inactive context messages:

```text
NO_CONTEXT_RUNTIME_FOUND: This context instance is no longer active.
Context with id ... doesn't exist or expired.
```

This happened even when build and query/pricing were run sequentially in the same PowerShell process.

Interpretation:

- The standard `runSalesforcePricing` action is probably not usable from this CLI/REST context in this org.
- The browser UI may be using a session-scoped context path that the CLI cannot reproduce.
- Headless pricing remains the better diagnostic path, but it currently hits `SF-Pricing-00008`.

Generated files:

- `scripts/build_context_quote5_rev_quote_mapping.request.json`
- `scripts/run_pricing_quote5_rev_context.request.json`
- `scripts/run_pricing_quote5_rev_context_live.request.json`
- `scripts/query_context_tags_quote5_rev.request.json`

### ContextTag Evidence

`runSalesforceHeadlessPricing` describe says:

```text
pricingResult: The outcome of the executed pricing process based on the output tags defined in the associated context definition.
```

`ContextTag` and `ContextAttribute` inspection showed that `RevSalesTransactionContext` does have output/value tags, including:

- `ItemContractDiscountType`
- `ItemContractDiscountValue`
- `ItemContractPrice`
- `AttributeValue`
- `LineAttributeValue`
- `ASPAttributeValue`

The tag records exist, so the error is not simply "there are zero output tags." It is more likely that the pricing procedure expects a tag/path/value that is missing at runtime.

### Quote 5 Concrete Bundle Relationship Issue

A separate, concrete data issue was found on Quote 5:

- Quote had 6 lines:
  - Home Office Bundle
  - TechNova ProBook 15
  - Wireless Combo Set
  - TechCover 1 Year
  - ErgoMouse Vertical
  - WebCam Pro 4K Studio
- But `QuoteLineRelationship` had zero rows for Quote 5.
- Child `ParentQuoteLineItemId` values were null.

This meant the child lines existed, but native RLM did not have the bundle junction records proving they were components of the Home Office Bundle.

The Home Office Bundle product structure had 5 `ProductRelatedComponent` records:

- TechNova ProBook 15 - included in bundle price
- Wireless Combo Set - included in bundle price
- TechCover 1 Year - not included in bundle price
- ErgoMouse Vertical - included in bundle price
- WebCam Pro 4K Studio - included in bundle price

### Relationship Repair Performed

A narrow, idempotent Apex repair script was created and executed:

- `scripts/repair_quote5_home_bundle_relationships.apex`

The first two compile attempts stopped before DML because fields were not writeable:

- `QuoteLineRelationship.QuoteId`
- `QuoteLineItem.ParentQuoteLineItemId`

The final version inserted only native `QuoteLineRelationship` rows.

Result:

```text
Inserted QuoteLineRelationship rows: 5
```

Verification after insert:

- 5 `QuoteLineRelationship` records now exist for Quote 5.
- `MainQuoteLineRole = Bundle`
- `AssociatedQuoteLineRole = BundleComponent`
- `RootQuoteLineId` points to the Home Office Bundle line.
- `ProductRelatedComponentId` and `ProductRelationshipTypeId` are populated.
- `AssociatedQuoteLinePricing` correctly reflects included vs not-included child pricing.
- Salesforce automatically populated child `ParentQuoteLineItemId` after the relationship insert.

This was a major native-data improvement.

### Quote Status After Relationship Repair

After relationship repair, Quote 5 still showed:

- `CalculationStatus = SaveFailedOrIncomplete`
- `ValidationResult = null`
- `LastPricedDate = null`
- `TotalPrice = 1648`
- `Tax = 313.12`
- `GrandTotal = 1961.12`

Headless pricing still failed with `SF-Pricing-00008`.

Interpretation:

- The missing bundle relationships were real and are now repaired.
- They were not the only cause of the invalid calculation status.
- The pricing runtime / output-tag issue remains unresolved.

### Important Current State for UI Testing

At the end of this session, Quote 5 has native bundle relationships repaired. The next useful manual UI test is:

1. Open Demo Quote 5.
2. Refresh the page.
3. Open the Home Office Bundle configurator.
4. Check whether the child warning state changed now that `QuoteLineRelationship` exists.
5. Click `Update Prices`.
6. Return to quote.
7. Click `Refresh` / `Reprice All` if shown.
8. Try `Create Order`.

If UI pricing succeeds after the relationship repair, then the CLI headless pricing path is not representative of the browser runtime. If UI pricing still fails with the same calculation status, the remaining blocker is definitely the native pricing procedure/context output-tag runtime.

### Safe Next Steps

Recommended next sequence:

1. Manual UI test after refreshing Quote 5, because the relationship repair changed the native bundle graph.
2. If yellow warnings remain, inspect the exact warning bubbles again after refresh.
3. If warnings reference child attributes, create or persist child `QuoteLineItemAttribute` defaults through the configurator first, not Apex.
4. If warnings disappear but order creation still fails, focus only on `SF-Pricing-00008` / SalesTransaction context sync / output tags.
5. Avoid adding more custom Apex pricing workarounds until this UI test is done.

### Current Hypothesis

There are two separate issues:

1. Bundle decomposition issue:
   - Fixed for Quote 5 by inserting missing `QuoteLineRelationship` rows.
   - This caused Salesforce to populate `ParentQuoteLineItemId` automatically.

2. Pricing runtime issue:
   - Not fixed.
   - Correct procedure/context/discovery names are now known.
   - Remaining failure is `SF-Pricing-00008` around output tags.

This is progress, but not yet a final native RLM pricing/order solution.

# ADR-032: RLM Bundle Pricing - Research-First Diagnostic Before More Org Changes

## Status

Accepted - diagnostic/research direction established 2026-06-29. No org data-changing fix has been accepted yet.

## Date

2026-06-29

## Author

Mustafa Aksu

## Context

TechnoStore's Revenue Lifecycle Management demo uses native-looking bundle configuration for products such as Home Office Bundle and Creator Studio Bundle. By 2026-06-28, the bundle data model had improved substantially: child quote lines were being created, `ParentQuoteLineItemId` was populated, `QuoteLineRelationship` records existed, and `QuoteLineItemAttribute` records for RAM, storage, processor, screen size, display, and subscription type were present.

The remaining blocker moved from "bundle children do not appear" to "RLM pricing runtime does not complete the transaction." Demo Quote 4 and Demo Quote 5 both had `Quote.CalculationStatus = SaveFailedOrIncomplete` and `Quote.ValidationResult = TransactionIncomplete`. Parent bundle `QuoteLineItem.UnitPrice` was updated by Apex to include attribute uplifts, but read-only RLM pricing fields stayed stale: for example, Demo Quote 5 parent had `UnitPrice = 2099` while `NetUnitPrice`, `NetTotalPrice`, and `TotalPrice` stayed at `1599`. Native Create Order therefore failed with the UI message that the calculation status of the quote is invalid.

Several sister-AI reviews converged on the same diagnosis: the bundle skeleton is mostly correct, but the Salesforce Pricing / RLM runtime pipeline is not successfully repricing and validating the quote. The org is sensitive because it contains many demo integrations and a Q2C story used for DACH Salesforce job applications, so broad experimental changes are risky.

## Decision

Pause further data-changing bundle/pricing experiments and switch to a research-first diagnostic path. Treat `ContextDefinitionSync`, `RLM_SalesTransactionContext` / `RevSalesTransactionContext`, standard Salesforce Pricing actions, pricing procedure binding, and headless pricing payload shape as the next root-cause area before adding more Apex workaround logic.

Specifically:

1. Preserve the current forensic state in `docs/troubleshooting/rlm-bundle-troubleshooting-notes.md`.
2. Preserve the research and evidence in `docs/research/rlm-bundle-pricing-notes.md`.
3. Use only read-only REST action describe, SOQL, Apex describe, and documentation research until the next explicit experiment is approved.
4. Do not permanently add `QuoteLinePriceAdjustment`, validation cleanup, or trigger changes until pricing context/runtime behavior is understood.

## Evidence Collected

### Standard action schema

The org exposes `runSalesforceHeadlessPricing` as a standard action in category `Salesforce Pricing`.

Required inputs from `/services/data/v67.0/actions/standard/runSalesforceHeadlessPricing`:

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

The org also exposes `runSalesforcePricing`, but that action requires `contextInstanceId` and `pricingProcedureName`. A quote record Id is not a context instance Id, which explains the earlier `NO_CONTEXT_RUNTIME_FOUND` result.

### Context sync evidence

Read-only REST query of `ContextDefinitionSync` returned exactly one sync row:

```text
ContextDefinitionName = BrowseProductsCtxDefinition
Status = success
StartDateTime = 2026-06-17T11:24:05.000+0000
EndDateTime = 2026-06-17T11:24:07.000+0000
```

No sync row was found for:

- `RLM_SalesTransactionContext`
- `RevSalesTransactionContext`

This is now the strongest diagnostic clue. Product discovery / Browse Catalog context was synced, but SalesTransaction pricing context does not show a sync record.

### Pricing procedure evidence

The default revenue pricing procedure exists:

- `CalculationProcedure.Id = 0k0aj000000I52wAAC`
- Name: `Revenue Management Default Pricing Procedure V1`
- UniqueName: `Revenue_Management_Default_Pricing_Procedure_V1`

It has an enabled version:

- `CalculationProcedureVersion.Id = 0k1aj000000HkksAAC`
- Version 1
- `IsEnabled = true`
- `Rank = 1`
- StartDateTime = `2025-02-02 20:56:40`

Therefore "pricing procedure not found" probably does not mean the procedure record is absent. It more likely means the action cannot resolve the procedure through the supplied context/payload/default binding/runtime cache.

### Quote state evidence

Demo Quote 4:

- Id: `0Q0aj000002hDwyCAE`
- `CalculationStatus = SaveFailedOrIncomplete`
- `ValidationResult = TransactionIncomplete`
- Total = `1898`

Demo Quote 5:

- Id: `0Q0aj000002hDwzCAE`
- `CalculationStatus = SaveFailedOrIncomplete`
- `ValidationResult = TransactionIncomplete`
- Total = `1648`

Parent bundle examples:

- Creator Studio parent line: `UnitPrice = 1949`, but `NetUnitPrice = 1449`.
- Home Office parent line: `UnitPrice = 2099`, but `NetUnitPrice = 1599`.

This proves the Apex update path changes `UnitPrice`, but does not complete the native RLM pricing waterfall.

### Public web research evidence

Broad web searches were performed across official docs, Salesforce Help, Developer Docs, StackExchange, Trailblazer public pages, GitHub, and general web search using terms such as:

- `SF-Pricing-00004`
- `NO_CONTEXT_RUNTIME_FOUND`
- `runSalesforceHeadlessPricing`
- `runSalesforcePricing`
- `ContextDefinitionSync Salesforce`
- `QuoteLinePriceAdjustment Salesforce`
- `Revenue Lifecycle Management pricing procedure`

No public, exact, actionable solution was found for the RLM-specific action/payload error. This is treated as a research finding, not proof that no solution exists; much of Salesforce Industries/RLM guidance may sit behind login or partner/customer support channels.

## Consequences

### Positive

- Avoids compounding quote state corruption by layering more repair scripts onto already-incomplete quotes.
- Creates a durable handoff for future work: `docs/troubleshooting/rlm-bundle-troubleshooting-notes.md` contains the forensic timeline, while `docs/research/rlm-bundle-pricing-notes.md` separates facts, hypotheses, and next experiments.
- Narrows the next root-cause investigation to SalesTransaction context sync/default binding and headless pricing payload shape.
- Keeps the org safe: the latest diagnostics used read-only SOQL, Apex describe, REST action describe, and local documentation changes only.

### Negative / Trade-offs

- Does not immediately unblock the demo. Native Create Order remains blocked for bundle quotes whose calculation status is invalid.
- Leaves Apex `UnitPrice` workaround in an uncomfortable middle state: useful for display, insufficient for native RLM completion.
- The public web did not provide enough implementation detail, so the next useful step likely requires Salesforce UI inspection or controlled org experiments.
- Demo Quote 4 and Demo Quote 5 may no longer be reliable clean test cases because they have seen multiple repair/reprice scripts.

### Neutral

- `QuoteLinePriceAdjustment` remains a plausible experiment because the context mapping includes item price adjustment data, but it is not yet accepted as the implementation path.
- Clearing `QuoteLineItem.ValidationResult` remains a possible cleanup step, but it is explicitly not considered a root-cause fix.

## Alternatives Considered

### Alternative A - Continue adding Apex repair logic immediately

Rejected for now. Adding permanent logic for `QuoteLineRelationship`, `QuoteLinePriceAdjustment`, or validation cleanup could hide symptoms while the pricing runtime still fails. It also risks making future diagnosis harder.

### Alternative B - Clear warnings by setting `ValidationResult = null`

Rejected as a primary fix. It may remove yellow UI icons, but it will not make `Quote.CalculationStatus` valid or make native Create Order succeed if pricing never completes.

### Alternative C - Treat `QuoteLinePriceAdjustment` as the accepted native pricing workaround

Deferred. It is technically plausible and should be tested on a clean, reversible quote, but only after context sync/runtime behavior is understood. Otherwise the test may fail for the same context reason and give a false negative.

### Alternative D - Build a custom Create Order bypass now

Rejected for now. A custom Apex/Flow quote-to-order path may be a final fallback, but the demo goal is to show native RLM capability. Bypassing native Create Order too early weakens the flagship RLM story.

### Alternative E - Abandon old quotes and only use new clean quotes

Partially accepted as a future test strategy. Demo Quote 4 and Demo Quote 5 are still useful forensic records, but final validation should happen on a fresh quote after context/pricing setup is understood.

## Next Steps

When work resumes:

1. Inspect Salesforce Pricing Setup / Context Definition UI for `RLM_SalesTransactionContext` and `RevSalesTransactionContext`.
2. Look for official Sync / Activate / Default binding controls for SalesTransaction context.
3. If a UI sync exists, run it only after explicit approval and then re-query `ContextDefinitionSync`.
4. Create a new clean test quote after sync/default binding is confirmed.
5. Test bundle add/configure/update prices/create order on the clean quote.
6. Only then consider a reversible `QuoteLinePriceAdjustment` experiment on one parent bundle line.

## References

- `docs/troubleshooting/rlm-bundle-troubleshooting-notes.md`
- `docs/research/rlm-bundle-pricing-notes.md`
- `scripts/diagnose_rlm_pricing_context_readonly.apex`
- `scripts/diagnose_rlm_pricing_context_focused_readonly.apex`
- `scripts/diagnose_rlm_pricing_context_focused_readonly.out.txt`
- `scripts/describe_runSalesforceHeadlessPricing.out.json`
- `scripts/describe_runSalesforcePricing.out.json`
- `scripts/query_context_definition_sync.out.json`
- ADR-002: Custom Metadata Type over native AttributeBasedAdjustment
- ADR-016: Bundle Attribute Pricing - Apex Workaround for RLM Pricing Procedure Builder

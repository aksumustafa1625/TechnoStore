# ADR-002: Custom Metadata Type over Native AttributeBasedAdjustment for Bundle Pricing

## Status

**Accepted (workaround)** — will revisit when Salesforce fixes the underlying platform bug

## Date

2026-05-04

## Author

Mustafa Aksu

## Context

TechnoStore's workstation bundle architecture supports attribute-driven upcharges: selecting **32 GB RAM** (vs base 16 GB) on Workstation Pro adds €200 to `QuoteLineItem.UnitPrice`; selecting **1 TB SSD** (vs base 512 GB) adds €150; selecting **Pro GPU** adds €400. The canonical Salesforce Industries CPQ path for this requirement is **`AttributeBasedAdjustment` records** driving a `PricingProcedureStep` of `StepType=AttributeBasedAdjustment` in the Workstation pricing procedure.

Investigation across ~6 hours documented in [Notion entry 16](https://www.notion.so/) confirmed the native path is structurally broken in our Dev Edition org:

- `AttributeBasedAdjustment` records exist and are queryable via SOQL: `SELECT Id, AttributeName, AdjustmentValue, ProductClassificationId FROM AttributeBasedAdjustment` returns 18 valid rows.
- The parent `PricingProcedure` (Status=Active, BasedOnId=CLASS_WORKSTATION) registers `PricingProcedureStep` records queryable via SOQL: 6 rows.
- But the **Pricing Procedure Builder UI renders the procedure as "0 steps"** despite the data layer being internally consistent.
- The **runtime engine appears to skip the procedure entirely** — `QuoteLineItem.save()` lifecycle does not invoke any step handler, no debug log entries from the adapter, no exception trace.

Deploying a brand-new diagnostic `PricingProcedure` with one trivial step reproduces the same "0 steps" rendering, confirming the issue is **org-level, not procedure-specific**. Salesforce Trailblazer Community had 3+ similar reports as of 2026-Q2 with no published vendor-blessed workaround.

A working bundle attribute pricing mechanism is **demo-critical** — without it, RAM/SSD/GPU configuration is purely cosmetic and the configurator demo falls flat.

## Decision

Bypass the native RLM Pricing Procedure engine for bundle attribute pricing. Implement an equivalent in Apex:

- **Custom Metadata Type** `Techno_Attribute_Price_Rule__mdt` with fields `Product2_Id__c`, `Attribute_Name__c`, `Attribute_Value__c`, `Price_Adjustment__c` — schema is a 1:1 mirror of `AttributeBasedAdjustment` so eventual migration back is config-only.
- **`AttributePricingHandler` class** with `@future(callout=false)` method `recalcAttributePricing(Set<Id> qliIds)` invoked from `QuoteLineItemTriggerHandler.afterInsert()` and `afterUpdate()`.
- **Idempotency guard** via `QuoteLineItem.Configured_Price_Adjustment__c` field — handler subtracts previous adjustment before applying new one, preventing double-charge on repeated save.
- **Native `PricingProcedure` metadata kept intact** in the org as documentation + future migration target. When Salesforce resolves the Builder UI bug, migration is: (1) copy `Techno_Attribute_Price_Rule__mdt` data into `AttributeBasedAdjustment` records via Apex script, (2) drop the trigger handler, (3) verify native engine fires.

## Consequences

### Positive

- **Demo unblocked** — configuring 32 GB RAM on Workstation Pro adds €200 to `UnitPrice` within 2-5 seconds (async @future settling).
- **1:1 schema parity with native** means migration back is config-only — no code rewrite, no data migration when Salesforce fixes the engine.
- **Custom Metadata Type advantages over Custom Settings**: deployable via SFDX (version-controlled), supports relationships, no governor cost on `Techno_Attribute_Price_Rule__mdt.getAll()`.
- **`@future` async pattern** isolates the recompute from trigger context governor limits and allows retry via Async Apex Errors monitoring on failure.
- **Idempotency guard** survives repeated `QuoteLineItem.save()` invocations without compounding adjustments.

### Negative / Trade-offs

- **Two-engine pricing landscape** until the native fix lands — base UnitPrice comes from PricebookEntry + RLM pricing procedure (working portion), attribute adjustments come from the Apex trigger. Engineers must know both paths.
- **Async settling delay** (~2-5 sec after save) is visible to the user; the Configure UI does not display the adjusted price until the @future completes.
- **Vendor lock-in tech debt risk** if Salesforce never fixes the engine — we live with the Apex trigger indefinitely. Mitigated by the 1:1 data layer mirror.
- **Migration burden** — when the native fix lands, someone must run the migration script + verify behavior + remove the trigger. Not a silent automatic upgrade.

## Alternatives Considered

### Alternative A — Continue debugging the native engine

Rejected because:
- 6 hours of investigation across data layer + Builder UI + Setup-sync triggers + diagnostic procedure deploy yielded no root cause.
- Salesforce Known Issues database had related but not identical reports with no workaround.
- Time budget: 4 weeks of demo prep remaining. Continued investigation would have displaced Stripe + Sendcloud + Slack integration work (entries 30-37) which collectively deliver more demo value than one working pricing step.

### Alternative B — Custom Setting instead of Custom Metadata Type

Rejected because:
- Custom Settings are not version-controlled via SFDX — they exist as data in the org, not metadata in source. Schema changes don't ripple through git.
- Custom Settings don't support compound primary keys naturally; would need to encode `Product2Id|Attribute|Value` as a single text field.
- Custom Metadata Types render in Setup → Custom Metadata Types with a proper list view, useful for non-developers reviewing pricing rules.

### Alternative C — Inline UnitPrice update in QuoteLineItem trigger (synchronous)

Rejected because:
- Synchronous DML in trigger context risks recursion if a downstream handler also updates the same line item.
- Synchronous execution adds latency to the user-perceived save action; async @future is invisible to the user.
- Cannot retry on transient failure — `@future` is registered in the Async Apex Errors queue and can be replayed.

### Alternative D — Native AttributeBasedAdjustment via SOQL injection workaround

Rejected because:
- The data layer is correct; the issue is the engine's failure to register the steps for execution. SOQL workarounds cannot force engine execution.

## References

- **Memory**: `bundle_attribute_pricing_trigger.md`
- **Notion portfolio entries**: 14 (Bundle Attribute Pricing workaround), 16 (Native Pricing Procedure 0-steps diagnosis)
- **Code**: `force-app-services/main/default/classes/AttributePricingHandler.cls`
- **Schema**: `force-app/main/default/objects/Techno_Attribute_Price_Rule__mdt/`
- **Related ADRs**: ADR-005 (TriggerHandler framework — the trigger handler uses Kevin O'Hara base)

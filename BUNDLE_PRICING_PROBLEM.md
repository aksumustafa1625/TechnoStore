# Salesforce Revenue Cloud (RLM) — Bundle Attribute Pricing: Stuck on "Required fields are missing: [Price Book Entry]" Toast

## Context

Building a Salesforce Revenue Lifecycle Management (RLM) demo (Developer Edition org). The use case: a configurable Bundle product ("Home Office Bundle") whose price changes based on a RAM attribute selection (16GB = +$100, 32GB = +$200, 64GB = +$400). The Bundle ships with 3 default child components (Wireless Combo Set, ErgoMouse Vertical, WebCam Pro 4K Studio) whose prices are absorbed in the bundle price ($0 line items, parent covers everything).

Stack:
- Default OOTB Configure UI (managed LWC, not custom) — gear icon on Bundle QLI
- Standard QLI / Quote / PricebookEntry / Product2
- AttributeBasedAdjustment + AttributeBasedAdjRule + AttributeAdjustmentCondition + PriceAdjustmentSchedule (all configured)
- ProductRelatedComponent (3 default children, IsDefaultComponent=true)
- Pricing Procedure exists but has 0 CalculationProcedureSteps (Builder UI is risky/blocked)
- Custom QuoteLineItem trigger to apply attribute-based pricing as workaround

## Architecture Decisions Already Made

1. **Native Pricing Procedure path was abandoned** — the org's Pricing Procedure has 0 steps. Adding an Attribute-Based-Price step requires the Pricing Procedure Builder UI, which has been unreliable in this Dev Edition org. We accepted that we can't make the native engine pick up the AttributeBasedAdjustment data.

2. **Custom Apex trigger reads the same data** the native engine would — AttributeBasedAdjustment + AttributeAdjustmentCondition records — so the data layer is identical to native config. Migration to native path later would be config-only.

3. **Configure UI is managed LWC, can't be modified.** We work around its quirks from the trigger side.

## What Works ✓

1. **Picklist label trick**: `AttributePicklistValue.DisplayValue = "RAM 32GB (+$200)"` — recruiter sees price differential in dropdown without breaking trigger matching (which uses `Value` field).

2. **Attribute-based pricing in beforeUpdate** (synchronous, in-place mutation, NO DML):
   ```apex
   protected override void beforeUpdate() {
       autoPopulateDescription();
       applyAttributeAdjustmentsInPlace(records);
   }
   ```
   Trigger reads `QuoteLineItemAttribute` records, matches against `AttributeAdjustmentCondition`, sums `AttributeBasedAdjustment.AdjustmentValue`, sets `q.UnitPrice = PBE.UnitPrice + adjustment` directly on `Trigger.new`. Idempotent (always rebases from PBE.UnitPrice). Verified working in apex debug log:
   ```
   USER_DEBUG|applyAttributeAdjustmentsInPlace: QLI 0QLaj... base=1599.00 adj=200.000000 new=1799.00
   ```

3. **Auto-decomposition on bundle insert** — afterInsert reads ProductRelatedComponent (IsDefaultComponent=true), inserts 3 child QLIs at $0. Required because **the OOTB Configure UI does NOT auto-render or auto-add child component cards** for default-included children — without this trigger, only the bundle parent appears on the quote.

4. **Recursion guard** (`isBundleDecompositionRunning` static flag) and **dedupe guards**:
   - Skip child if `(QuoteId, Product2Id)` already exists (prevents Configure UI's draft re-insert from duplicating children)
   - Skip ENTIRE bundle decomposition if a bundle of the same Product2 already exists on the quote (prevents Configure UI's transient draft bundles from getting their own children)

## The Bug We Can't Fix ✗

After clicking **Save & Exit** in Configure UI (with attributes selected), a red toast appears:

> **"Your quote was not updated. Required fields are missing: [Price Book Entry]"**

Simultaneously, a green toast: **"Quote 'X' was updated."** — these contradictory toasts come from different code paths.

Symptoms:
- Toast appears every time Save & Exit is clicked
- Quote line items grid initially shows Bundle = $1,599 (UI lag/cache)
- Click "Reprice All" once → Sales Price column updates to $1,799 but Subtotal column still $1,599
- Click "Reprice All" again → Subtotal also updates to $1,799
- Final state IS correct in the database (our beforeUpdate did its job), but UI requires manual repricing to display

## Diagnostic Test Results

We disabled `autoDecomposeBundles` entirely (so no auto-children inserted). Result:
- ✅ **Toast disappeared** (no children = no toast)
- ❌ Lost the visual of children on quote
- Confirmed: the auto-decomposed children ARE the cause of the toast, not the bundle itself

## Smoking Gun: ParentQuoteLineItemId is Read-Only

`QuoteLineItem` has a field `ParentQuoteLineItemId` (Tooling API confirms it exists, IsNillable=true). This is the standard RLM field that links a child component QLI to its parent bundle QLI in a hierarchy.

When we tried to set it in our trigger:
```apex
child.ParentQuoteLineItemId = parent.Id;
```

Deploy failed with:
> **"Field is not writeable: QuoteLineItem.ParentQuoteLineItemId"**

So the field exists but can only be populated by the platform itself (Configure UI when it does its own bundle decomposition). Our Apex-inserted children remain "orphans" — Product is bundled in metadata, but the QLI has no parent link.

**Theory**: Configure UI's Save & Exit validation walks the QLIs on the quote, expects bundle children to have `ParentQuoteLineItemId` populated, finds our orphan children, and throws "Required fields missing: [Price Book Entry]" as a (misleading) error message. The actual missing field is the parent link, not Price Book Entry.

## Tried and Failed

| Attempt | Result |
|---|---|
| `@future` async DML pattern (avoid sync DML conflict) | Worked but needed 2-3 reprice clicks to converge |
| Move to `beforeUpdate` in-place mutation (no DML) | Reduced to 1 reprice click; toast still appears |
| Skip duplicate child inserts (dedupe by `QuoteId+Product2Id`) | Helped with draft bundles; toast still appears |
| Skip entire decomposition if same-product bundle exists | Toast still appears with single original bundle |
| Set `ParentQuoteLineItemId` on children | **Field is not writeable** — blocked at compile/deploy |

## Apex Debug Log Evidence

During Configure UI Save & Exit, log shows:
- `industries.epc.impl.rulesengine.runtime.ProductQualificationProcessTypeHandler` runs (managed)
- `industries.pricing.rulesengine.runtime.processtype.DefaultPricingProcessTypeHandler` runs (managed)
- Multiple `Workflow:Quote` and `Flow:Quote` code units fire
- Our `applyAttributeAdjustmentsInPlace` fires correctly, sets new=1799.00
- Multiple bundle inserts happen during Save & Exit (transient drafts):
  - Y5qXGAS (original — has attributes)
  - Y5s9GAC (transient draft — Configure UI internal)
  - Y5sDGAS (transient draft — Configure UI internal)
- Drafts get rolled back / cleaned up by Configure UI before final save

NO `EXCEPTION_THROWN`, `FATAL_ERROR`, `REQUIRED_FIELD_MISSING`, or `FIELD_INTEGRITY_EXCEPTION` in the log. The toast is likely client-side (LWC) validation or a managed-package-thrown error that doesn't surface to the Apex log.

## What We Need

A way to either:
1. **Set `ParentQuoteLineItemId` on auto-decomposed children** — is there a system-context Apex API, an invocable action, a managed-package method, or a metadata config that allows us to populate this field on a custom-inserted QLI?
2. **Replace our trigger-based auto-decomposition** with a platform-native mechanism that properly sets the parent link — e.g., an invocable Apex action like `ConnectApi.QuoteLineItem.decomposeBundle()` (does this exist?), or a Standard Action that triggers the same decomposition logic Configure UI uses internally.
3. **Suppress the Configure UI Save & Exit validation** that throws this toast — feature flag, custom permission, ConfigurationOptions metadata.
4. **Identify the actual validation source** (it's not a custom validation rule, not a custom flow — confirmed via Tooling API queries) so we can disable just that one piece.

## Schema Snapshot

```
Quote 0Q0aj000002IHalCAG
├─ QLI Y5qXGAS  Home Office Bundle (BUNDLE-OFFICE-001) UnitPrice=1799 (after trigger) PricebookEntryId=01uaj0000074OcQAAU
├─ QLI Y5qYGAS  Wireless Combo Set  UnitPrice=0  PricebookEntryId=01uaj000007C8zoAAC  ParentQuoteLineItemId=NULL ⚠
├─ QLI Y5qZGAS  ErgoMouse Vertical  UnitPrice=0  PricebookEntryId=01uaj000007C8zpAAC  ParentQuoteLineItemId=NULL ⚠
└─ QLI Y5qaGAC  WebCam Pro 4K       UnitPrice=0  PricebookEntryId=01uaj000007C8zJAAS  ParentQuoteLineItemId=NULL ⚠
```

The 3 children have no parent link — that's the suspected root cause.

## Question for Consultants

**How do we populate `ParentQuoteLineItemId` on auto-decomposed bundle children when the field is marked non-writeable in standard Apex DML?** Or what's the canonical RLM API to add child components to a Bundle QLI such that the bundle hierarchy is properly established?

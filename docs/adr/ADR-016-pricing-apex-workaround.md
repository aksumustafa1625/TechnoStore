# ADR-016: Bundle Attribute Pricing — Apex Workaround for RLM Pricing Procedure Builder

## Status

Accepted — interim. Active in the org since 2026-05-04 (commit history in memory `bundle_attribute_pricing_trigger.md`). Will be reconsidered when Salesforce ships the Pricing Procedure Builder fix referenced in known-issue ID-???.

## Context

TechnoStore sells bundle products with attribute-driven add-on pricing — pick a Creator Studio Bundle, configure RAM (16GB / 32GB / 64GB), pick a monitor size (27" / 32" / dual), pick a keyboard switch type. Each attribute selection adjusts the bundle line price by an amount stored in the `AttributeBasedAdjustment` Industries CPQ data table (e.g., RAM 16GB → 32GB = +$200, RAM 16GB → 64GB = +$700).

The right way to handle this in Industries CPQ / Revenue Cloud is the **Pricing Procedure** — a no-code, admin-configurable pipeline that reads attribute selections at Configure time, looks up the delta in `AttributeBasedAdjustment`, and applies it to the line price. The data model is built around this pattern (the `AttributeBasedAdjustment` records ARE the canonical input).

Two problems blocked the no-code path:

1. **Pricing Procedure Builder bug**: when configured against the Creator Studio Bundle in this Developer Edition org, the Builder UI loaded with **0 steps visible** despite the underlying procedure metadata being present. Saving from the empty Builder overwrites the procedure with an empty step list. Reported as a Salesforce known issue; no ETA on fix as of 2026-05.
2. **No CLI workaround**: editing Pricing Procedure steps via metadata API alone is partial — the Builder owns step-ordering and dependency graph state that doesn't deploy cleanly outside the UI. So even hand-writing the XML, the Builder would corrupt it on next open.

Demo deadline forced a path that:

- Reads the same `AttributeBasedAdjustment` rows (admin/finance-editable)
- Applies the delta to QuoteLineItem at Configure save time
- Does not depend on the broken Builder
- Migrates cleanly to native Pricing Procedure when the Builder is fixed (no data migration, no logic re-write)

## Decision

An async `@future` Apex trigger on QuoteLineItem reads `AttributeBasedAdjustment` after Configure save, computes the delta sum across selected attributes, and updates the line price. The data layer (`AttributeBasedAdjustment` records) is unchanged from what native Pricing Procedure would consume.

Implementation:

- `QuoteLineItemTriggerHandler.afterInsert` / `.afterUpdate` queues `@future(callout=false)` work when ConfigurationAttributes change.
- The `@future` method queries `AttributeBasedAdjustment` records keyed by `ProductId + AttributeId + AttributeValue`, sums the deltas, and updates QuoteLineItem.UnitPrice + Discount.
- `bundle_attribute_pricing_trigger.md` (memory) documents the implementation history and exception cases.

Key choice: **async over sync**. Sync triggers run inside the Configure transaction and would cause "uncommitted DML" failures if the user is mid-edit; async also lets us batch multiple attribute changes into one repricing pass.

Same data layer feeds either engine: `AttributeBasedAdjustment` is admin-managed (Setup → Object Manager → AttributeBasedAdjustment → records). Sales operations can update RAM-upgrade pricing without a developer involved. When the Pricing Procedure Builder is fixed, the same records flow into the native engine and the Apex trigger is removed in one PR — no data migration.

## Consequences

### Positive

- **Pricing functions today** — the demo's bundle Configure UI shows the right price changes; recruiter sees the working flow.
- **Admin-editable** — business owns the rate table, not engineering. Counter to the reviewer's "Apex pricing is developer-bound" critique: the Apex reads admin-edited data, it doesn't contain the rates.
- **Zero-cost migration to native engine** — `AttributeBasedAdjustment` is the same data model Pricing Procedure uses. Migration is "remove trigger + enable procedure", config-only.
- **Async pattern is independently defensible** — async pricing is correct for any compute-heavy reprice anyway (volume discounts, region overrides). The Apex pattern stands on its own merit, not just as a workaround.

### Negative

- **Apex in the pricing path** — recruiters trained on "no-code-first" methodology will flag this. Defense: the data is no-code (admin-edited mdt-equivalent), the trigger is glue. The full no-code path returns when the Builder is fixed.
- **Two systems of pricing logic if subscription products land** — subscription pricing uses different rules (proration, ramp pricing) and would need either a second Apex trigger or — better — wait for Pricing Procedure to be production-ready by then.
- **Test data dependency** — Apex tests must seed `AttributeBasedAdjustment` records explicitly; can't rely on org-level pricing config in test context.

### Future state — exit ramp

The day the Builder fix lands (or we move to a different org without the bug):

1. Build the Pricing Procedure with one step per attribute family (RAM, monitor, keyboard).
2. Activate the procedure.
3. Disable `QuoteLineItemTriggerHandler.afterInsert/afterUpdate` reprice path via `TriggerHandler.bypass('QuoteLineItemTriggerHandler')` Custom Setting.
4. Verify Configure UI prices match — same `AttributeBasedAdjustment` data, different engine path.
5. Delete the trigger handler methods after one full sales cycle of validation.

Migration is 2-4 hours total.

## Alternatives Considered

1. **Wait for the Builder fix** — rejected because no ETA. Demo couldn't ship without working bundle pricing.
2. **Hard-code prices on Product2 / Pricebook entries** — rejected because attribute combinations explode (3 RAM × 3 monitor × 3 keyboard = 27 SKUs per bundle). The `AttributeBasedAdjustment` delta model is the only sane way to manage it.
3. **Calculated formula fields on QuoteLineItem** — rejected because formula fields can't read from a different sObject (`AttributeBasedAdjustment`) with the filter logic needed. Would need a Roll-Up Summary on Bundle, which doesn't support multi-attribute lookups either.
4. **Flow-based reprice** — considered. The async Flow vs async Apex tradeoff lands on Apex because the lookup pattern (multi-key join with summing) reads cleaner in Apex than in Flow visual steps; also Flow doesn't natively handle bulk Quote configuration changes as gracefully.
5. **Inline price entry by sales rep** — rejected for governance reasons. Manual entry is the path before any pricing logic; defeats the purpose of CPQ.

## Related Decisions

- ADR-002 (Custom Metadata over AttributeBasedAdjustment) — partial overlap. The mdt was an earlier proposal that didn't ship because the `AttributeBasedAdjustment` object was already populated. This ADR uses the existing data; ADR-002 is a deprecated proposal.
- ADR-015 (Production Externalization Strategy) — the Pricing row of the externalisation table refers to this ADR: "config-only migration to native engine."
- Future ADR-???: SAP SD Condition Records for production pricing. When SAP integration covers pricing, condition records replace both this Apex and the native Pricing Procedure.

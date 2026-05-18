# ADR-021: Customer Master / BillTo Source — Demo Backfill vs Production SAP BP Sync

## Status

Accepted — directional. Demo uses Account-based backfill of `BillToContactId` + Billing/Shipping address on Order create / update. Production target is a one-way nightly sync from SAP Business Partner (BP) master into Salesforce Account, with Order backfill still happening but reading from the SAP-sourced Account fields.

## Context

When an Order is created from a Quote (or directly on an Account), the `BillToContactId`, `ShipToContactId`, and the Billing/Shipping address blocks need to be populated. Salesforce's standard Order activation validation refuses `Status = 'Activated'` if these are blank.

The demo's `OrderTriggerHandler.beforeInsert / beforeUpdate` runs `backfillFromAccount()`:

- Queries the parent Account.
- Pulls the first associated Contact (by CreatedDate ascending) as the default `BillToContactId` and `ShipToContactId`.
- Pulls the Account's Billing/Shipping address fields and applies them to the Order if blank.
- Falls back to Billing address for Shipping if Shipping is empty on the Account.

This works because in the demo:

- Account records have address fields populated (seeded by demo data scripts).
- Account has at least one Contact (also seeded).
- The first-Contact-by-CreatedDate heuristic happens to pick a useful name (Mustafa Aksu for the demo).

In production this is wrong on multiple axes:

1. **Account address might not be authoritative.** In a SAP-running enterprise, the Customer Master (`SAP BP` / Business Partner) is the source of truth for addresses. Sales reps editing Account.BillingAddress in Salesforce creates a fork between systems.
2. **"First Contact by CreatedDate" is a heuristic, not a business rule.** Production needs an explicit "Primary BillTo Contact" relationship — could be via a custom lookup on Account (`Primary_BillTo_Contact__c`), a junction object, or a flag on Contact (`Is_Primary_BillTo__c`).
3. **Shipping address rules can be complex.** Same customer might have multiple ship-to locations (their distribution warehouses) and the rep picks which one per Order. The demo's "use Account ShipTo, fall back to BillTo" rule doesn't capture the multi-location reality.
4. **Audit trail for address changes** has to live somewhere — when a customer moves offices, every open Order that references the old address needs review. In SAP, the BP master change triggers downstream alerts; in our demo, an Account address update just silently propagates.

The Apex backfill is the right minimum for the demo. The production architecture is different in source of data, not in the trigger point.

## Decision

### Demo (today)

`OrderTriggerHandler.beforeInsert / beforeUpdate` backfills from Account if Order fields are blank:

- `BillToContactId` ← Account.Contacts[first by CreatedDate].Id
- `ShipToContactId` ← same
- Billing address block ← Account.Billing*
- Shipping address block ← Account.Shipping* with Billing fallback

If Account doesn't have a Contact or addresses, fields stay blank and Order activation will fail validation (correct behaviour — caller must populate first).

### Production (target)

Three-layer model:

1. **SAP BP master** = source of truth for customer address, tax ID (USt-IdNr in DE), payment terms, credit limit.
2. **Salesforce Account** = mirror of SAP BP, updated nightly via Mule batch job (one-way, SAP → SF). Account fields become read-only for sales reps; edits route through "Request Customer Master Update" workflow that fires a SAP IDoc.
3. **Salesforce Order** = backfilled from Account at create-time using the same `OrderTriggerHandler.beforeInsert` pattern, but the Account it reads from is the SAP-sourced one. `Primary_BillTo_Contact__c` and `Primary_ShipTo_Contact__c` custom lookups on Account replace the "first Contact by CreatedDate" heuristic.

The trigger handler stays the same; the data source upstream changes.

## Consequences

### Positive

- **Demo works without SAP.** The backfill is self-contained, no integration dependency. Demo data populates Account, Order picks it up.
- **Production trigger point doesn't move.** When SAP is wired, the Order backfill code doesn't change — only the Account fields it reads from change source. This is a clean seam.
- **Address-of-truth question has an answer**: SAP BP in production, Account in demo. Reviewer asking "what's authoritative?" gets a clear answer.
- **Audit trail naturally lives in SAP** in production — the SAP BP change history is preserved by SAP's master data audit logging. Salesforce doesn't need to track it independently.
- **Multi-ship-to scenario** has a documented future path (`Primary_BillTo_Contact__c` + per-Order ship-to picker), even if not built today.

### Negative

- **Demo Address can drift from real customer address** in the demo if Account is edited but real customer moves. Not a real concern because demo data is synthetic; production sync handles it.
- **Trigger handler runs on every Order create/update** even when fields are already populated — small CPU cost. Mitigated by the `needsBackfill()` short-circuit check at the top of the handler.
- **SAP one-way sync is harsh** — sales reps can't fix an Account address from Salesforce in production. Every correction goes through a SAP ticket. UX cost; common in DACH enterprise architectures, expected by SAP-trained reps but jarring for Salesforce-native reps.

### Future state — production rollout

1. Build Mule batch job `sap-customer-master-sync` that pulls BP records from SAP via OData (`API_BUSINESS_PARTNER`) and upserts into Salesforce Account by External ID (`SAP_BP_Number__c`).
2. Make Account address fields read-only for non-admin profiles via Field-Level Security; expose a "Request BP Update" Quick Action that fires a SAP IDoc.
3. Add `Primary_BillTo_Contact__c` and `Primary_ShipTo_Contact__c` lookups on Account.
4. Update `OrderTriggerHandler.backfillFromAccount` to prefer the lookups over the first-Contact heuristic; fall back to the heuristic if lookups are blank.
5. (Multi-ship-to) Build a Quick Action on Order to override the default ship-to with a different Account location address. Out of scope unless the customer base requires it.

Effort: 3-4 weeks for the SAP sync + permission model + Account UI changes. The Order trigger update is ~1 hour.

## Alternatives Considered

1. **Require explicit BillTo / ShipTo entry on every Order, no backfill.** Rejected — too much typing for sales reps, breaks the "fast Quote → Order conversion" UX. Backfill is the right default with explicit override.
2. **Two-way sync between SAP BP and Salesforce Account** (sales rep edits Account, Mule writes to SAP). Rejected — violates the "single source of truth" rule. Two-way sync without conflict resolution leads to data drift; conflict resolution adds operational cost.
3. **Master Data Management (MDM) layer** (Reltio, Informatica, Riversand) as the BP master, both SF and SAP read from it. Production-grade but adds a third system. Reasonable for very large enterprises; overkill for TechnoStore Mittelstand profile.
4. **Skip BP sync entirely, rely on rep-typed Order data.** Rejected — violates the SAP-as-source-of-truth principle and would mean Salesforce data drifts from SAP over time.

## Related Decisions

- ADR-005 (Kevin O'Hara TriggerHandler) — `OrderTriggerHandler.backfillFromAccount` is the handler method that this ADR governs.
- ADR-011 (Inventory Approval Two Convergent Activation Paths) — backfill happens in `beforeUpdate` regardless of which activation path (VF approve / JIRA Done) triggers the status change; both paths benefit from the same backfill logic.
- ADR-015 (Production Externalization Strategy) — the Customer Master row of the externalisation table points to this ADR for the demo-to-production migration plan.
- Future ADR-???: SAP IDoc Outbound for Customer Master Update Requests when the production rollout happens.

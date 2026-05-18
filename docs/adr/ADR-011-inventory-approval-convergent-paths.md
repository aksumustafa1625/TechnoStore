# ADR-011: Inventory Approval — Two Convergent Activation Paths

## Status

Accepted — implemented across two sessions (2026-05-06 initial VF approve path, 2026-05-16 JIRA Done branch and convergent activation handler enhancement).

## Context

TechnoStore Order activation is gated by a warehouse inventory check (the "ATP Gate before commitment" pattern — see ADR-012 for the broader transactional-vs-subscription rationale). The naive design is one approval path: warehouse user approves stock confirmation, Order activates. Reality is messier:

- When the warehouse user confirms stock available, Order should activate immediately.
- When the warehouse user rejects (out of stock), Order should NOT activate. Instead, a JIRA ticket should open so the warehouse / procurement team can replenish.
- Once stock is replenished, the warehouse team marks the JIRA ticket Done. At that point, the Order should auto-activate without any further sales-rep action — the rep should not have to babysit the deal between rejection and replenishment.

This creates two independent triggers that need to converge on the same endpoint (`Order.Status = 'Activated'`):

1. **Path 1 — VF approve**: Warehouse marks In Stock on the Visualforce approval page → standard approval workflow field updates set `Inventory_Status__c = 'In Stock'` AND `Status = 'Activated'`.
2. **Path 2 — JIRA Done**: Warehouse marks the linked JIRA ticket Done → JIRA Cloud webhook fires → `JiraStatusWebhook` REST endpoint validates secret + dedup → publishes `Inventory_Status_Update__e` platform event → `InventoryStatusUpdateTriggerHandler` updates Order in system context.

The handler for Path 2 also has to be smart enough to ALSO activate the Order when the inventory transitions In Stock and the Order is still Draft. Without that, the JIRA Done would only flip `Inventory_Status__c` and the Order would sit Draft forever.

There are three production constraints that shape the design:

- **Site Guest User can't edit Order directly.** The JIRA webhook lands as the Guest User. Granting Order edit to the guest user would expose every Order to public-internet anonymous modification. The platform event indirection (ADR-003) is the standard escape: guest user publishes an event, a trigger handler in system context does the update.
- **Approval-process record locking.** When Order is submitted to `Inventory_Approval`, the record gets `recordEditability=AdminOnly`. The trigger handler that wants to update Status=Activated has to either wait for approval completion (which unlocks the record) or run before the approval transaction's record-lock fires. Path 1 satisfies this by chaining the activation as a workflow field update inside the approval's `finalApprovalActions` — same transaction, same lock holder. Path 2 satisfies this differently: by the time the JIRA Done webhook fires, the approval has already completed with a Rejection, so the Order is unlocked again.
- **Built-in Order activation validation.** Salesforce's standard Order activation validates that BillToContactId and Billing/Shipping address blocks are populated; without them, `Status = 'Activated'` throws `FAILED_ACTIVATION: Enter the bill to contact associated with the account`. Demo accounts often have `BillToContactId = null`. The `OrderTriggerHandler.beforeUpdate` backfills these from the related Account so both paths pass validation on the first try.

## Decision

Two paths, one destination. The activation logic lives in two places:

### Path 1 — VF Approve (synchronous, approval workflow)

- `WarehouseInventoryApprovalController.markInStock()` calls `Approval.process(Approve)` on the pending `Inventory_Approval` workitem.
- The approval process's `finalApprovalActions` runs three workflow field updates in the same transaction:
  - `Inventory_Set_In_Stock` → `Inventory_Status__c = 'In Stock'`
  - `Order_Activate` → `Status = 'Activated'`
  - (audit comment captured by the Process Instance Step)
- `OrderTriggerHandler.beforeUpdate` fires inside the same transaction, sees `Status` transitioning to `'Activated'`, calls `backfillFromAccount` to populate `BillToContactId` + address fields.
- `OrderTriggerHandler.afterUpdate` detects the Status transition and runs `createAssetsForActivatedOrders` (Pattern 1 asset creation — see ADR-012).
- Single transaction, single audit trail (Process Instance Step shows "Inventory confirmed in stock via the Warehouse Inventory Review page").

### Path 2 — JIRA Done (asynchronous, platform event)

- `WarehouseInventoryApprovalController.markOutOfStock()` calls `Approval.process(Reject)` → approval workflow sets `Inventory_Status__c = 'Out of Stock'`. Order stays Draft.
- Apex `@future(callout=true)` opens a JIRA ticket via `JiraTicketService.createTicketAsync()`. Ticket key (e.g. `TS-25`) is written back to `Order.JIRA_Ticket_Id__c`. (Reject is a DML in the parent transaction; the callout has to be async to avoid the "uncommitted work pending" exception.)
- Warehouse replenishes stock externally. They transition the JIRA ticket to Done.
- JIRA Cloud webhook (registered via `/rest/webhooks/1.0/webhook` API — see related decision below) POSTs to the `JiraStatusWebhook` REST endpoint at `/services/apexrest/jira/webhook?secret=...`.
- `JiraStatusWebhook.handle()` validates HMAC-style shared secret (header OR query-string fallback because v1.0 webhooks can't send custom headers), extracts `issueKey + status + timestamp`, runs `WebhookEventLogger.checkAndRecord` for idempotency (ADR-013), queries Order by `JIRA_Ticket_Id__c`, and publishes an `Inventory_Status_Update__e` platform event with `New_Status__c = 'In Stock'` and `Confirmed_By__c = 'JIRA TS-25'`.
- `InventoryStatusUpdateTriggerHandler.handleAfterInsert` runs in system context (Automated Process User), does a three-pass update: (1) `Inventory_Status__c = 'In Stock'`, (2) `Status = 'Activated'` with `Database.update(allOrNone=false)` so an RLM pricing-validation failure doesn't poison the batch, (3) creates a completed Task on the Order's Activity Timeline with subject "Inventory confirmed in stock via JIRA TS-25" — the JIRA-path equivalent of the VF page's Process Instance Step audit.
- `OrderTriggerHandler.beforeUpdate` + `afterUpdate` fire as in Path 1 — same backfill, same Asset creation. The downstream is identical regardless of upstream path.

Convergence at: **`Order.Status = 'Activated'`** + **`createAssetsForActivatedOrders`** + **`Inventory_Status__c = 'In Stock'`**. The Asset creation is idempotent (dedup key Account+Product+OrderNumber) so even if both paths somehow fired for the same Order (e.g. user marks In Stock, then someone separately closes the JIRA ticket) the Assets don't duplicate.

### Sales rep experience

Zero manual steps post-Request Inventory Check. The rep clicks Request Inventory Check, waits for either:

- the warehouse to approve (Path 1 — Order activates seconds later), or
- the warehouse to reject → JIRA opens → eventually JIRA Done → Order activates (Path 2 — hours to days later, but no rep action needed).

The convergent design is the value: the rep doesn't need to know which path is firing or have to flip Status manually. Both paths end at Activated automatically.

## Consequences

### Positive

- "Fire and forget for sales" — sales rep doesn't babysit inventory follow-ups. The narrative "set up the deal, let operations close the loop" is a recognizable B2B operations pattern.
- Audit symmetry — Path 1 produces a Process Instance Step ("Inventory confirmed in stock via the Warehouse Inventory Review page"), Path 2 produces an Activity Timeline Task ("Inventory confirmed in stock via JIRA TS-25"). Both surfaces are visible on the Order page; both are queryable in Reports.
- The pattern is reusable: any future binary-decision approval-with-fallback can route through the same two-path scaffolding. E.g., credit-check approve → activate / reject → finance follow-up ticket → finance approves → activate.
- Decoupling between SF and JIRA via the webhook + platform event indirection (ADR-003) means JIRA can be replaced with ServiceNow, Asana, or Jira Service Management without changing any Apex on the activation side — only the inbound webhook secret config moves.

### Negative

- Two activation code paths to test. The Asset-creation idempotency dedup has to be solid because two paths firing on the same Order is now a real (rare) scenario.
- The JIRA Done path depends on a registered webhook in JIRA Cloud that has a configured target URL with the shared secret in the query string. Token rotation requires re-registering the webhook because v1.0 webhooks don't have a re-key API; you delete and recreate.
- The activation chain in Path 2 is async (platform event → trigger handler → ~1 second), so the JIRA Done click → Order Activated latency is observable. In demo it lands at 1-3 seconds; in production under load it could be 5-15 seconds. Sales rep watching the Order page would see a brief "Draft" → "Activated" transition.
- `InventoryStatusUpdateTriggerHandler` has to be defensive (Database.update allOrNone=false, try/catch around the audit Task insert) because the activation can fail validation on Orders missing pricing data. The handler logs to `Integration_Error__c` (ADR-013) when this happens so the demo doesn't silently swallow failures.

### Future state

- **Path 3 — Mule warehouse callback** (deferred): If the warehouse-team moves off the VF page and onto a Mule-driven workflow (e.g. integration with SAP MM stock-confirmation IDocs), the third path lands at the same `Inventory_Status_Update__e` platform event with `Confirmed_By__c = 'SAP <doc-number>'`. The trigger handler doesn't need changes — it already handles any `New_Status__c = 'In Stock'` event.
- **Confidence-weighted activation**: when SAP integration goes live, the SAP ATP API returns a confidence score (e.g. "8 units available, 99% confidence" vs "soft reserve only"). Path 1 could become "always activate" and Path 2 could become "activate only when SAP confirms hard reserve." Out of scope for the current demo.

## Alternatives Considered

1. **Single path — VF approve only**, no JIRA branch. Rejected: when out of stock, sales rep has to manually re-submit the inventory check later after replenishment. Doesn't fit the "fire-and-forget for sales" narrative.
2. **Mark Out of Stock = manual JIRA + manual SF re-activation later**. Rejected: too many manual steps, breaks the convergent-paths value proposition.
3. **JIRA Automation Rule** instead of webhook v1.0. The cleaner JIRA-native path, but JIRA Automation Rules can ONLY be created in the JIRA Cloud web UI — no public REST API. The webhook v1.0 API is publicly accessible and lets us register the integration programmatically (which we did during setup). Functional outcome is identical; the difference is who creates the rule (us via API vs. user clicking in JIRA UI).
4. **Slack interactive buttons** as a third decision surface, in addition to the VF page. Considered but skipped — Slack is the notification surface, the VF page is the decision surface. Mixing decision and notification (the Slack-interactivity pattern) adds Block Kit complexity and another auth scope.

## Related Decisions

- ADR-003 (Site Guest User + platform event indirection) — the mechanism for Path 2's Order update in system context.
- ADR-005 (Kevin O'Hara TriggerHandler) — the framework `OrderTriggerHandler` and `InventoryStatusUpdateTriggerHandler` both extend.
- ADR-012 (Order-First Activation Pattern 1) — explains why this gate exists upstream of contract signing rather than downstream of it.
- ADR-013 (Webhook idempotency + integration error logging) — protects Path 2's JIRA-webhook entry point from at-least-once delivery duplicates and routes failures to the Integration Health log.

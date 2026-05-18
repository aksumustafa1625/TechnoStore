# ADR-022: SAP MM ATP Integration — SAP-First, JIRA-Fallback Hybrid for Inventory Check

## Status

Accepted — implemented 2026-05-18 in the SAP Sprint Phase 1 session. SapMaterialStockService + Product2.SAP_Material_Number__c + Order.SAP_Available_Quantity__c + Order.SAP_Inventory_Checked_At__c live in the org; InventoryCheckService refactored to call SAP first and fall back to the legacy warehouse approval path when SAP can't confirm sufficient stock.

## Context

The Order inventory check (per ADR-011) originally had two convergent activation paths: warehouse user marks In Stock on a VF page (Path 1) or the linked JIRA ticket transitions to Done (Path 2). Both required a human warehouse decision before the Order could activate, which is reasonable for demo but slow for real B2B operations.

In a DACH manufacturing or distribution enterprise, the warehouse user generally doesn't make the "is this in stock?" decision from scratch — they look up real-time stock in SAP MM (Material Management). The warehouse decision exists for exception handling (split shipments, allocation conflicts, quality holds), not for routine ATP (Available-to-Promise) checks. Routing every Order through a manual approval when SAP could answer "yes, 50 units available" in 200 milliseconds is friction without value.

The reviewer's enterprise-realism critique flagged this directly: "ATP check should hit SAP MM, not Slack notify the warehouse." Fair point — but absolutist. Real Mittelstand integrations use SAP for stock data AND keep the warehouse approval path as the exception handler. Going SAP-only would drop the warehouse-team workflow that's already built (Slack + VF + JIRA, ADR-011) and remove the human-in-the-loop for cases SAP can't decide (out-of-stock + needs-replenishment).

The right architecture is hybrid: SAP first, warehouse-approval fallback. SAP handles the routine ATP query for routine deals. Warehouse handles the exceptions. JIRA stays as the replenishment-task tracker (Atlassian JSM has explicit warehouse use cases; reviewer's "JIRA isn't a warehouse tool" stance is overstated — see ADR-019 defense notes).

Three production constraints shape the design:

1. **DML / callout ordering.** Approval.process() is DML. If we call SAP MM after submitting to approval, we hit "uncommitted work pending." The SAP callout MUST happen first in the InventoryCheckService flow.
2. **SAP API Hub Sandbox limitations.** The trial sandbox at sandbox.api.sap.com returns valid material records but reports qty=0 for almost everything (sparse data, read-mostly). Production SAP S/4HANA returns real numbers. The integration code path is identical; only the data differs.
3. **Material join from SF to SAP.** Salesforce Product2 IDs are 18-char Salesforce-internal; SAP material numbers are SAP-internal (typically 18 chars but in different format). A bridge field is required: `Product2.SAP_Material_Number__c`.

## Decision

`InventoryCheckService.requestCheck` is refactored to a two-phase flow:

### Callout phase (runs before any DML)

For each Order, `SapMaterialStockService.checkOrderStock(orderId)` is called:

- Looks up the primary OrderItem (first by CreatedDate) and its Product2.SAP_Material_Number__c.
- Calls SAP API Hub: `GET /s4hanacloud/sap/opu/odata/sap/API_MATERIAL_STOCK_SRV/A_MatlStkInAcctMod?$filter=Material eq 'XXX'&$format=json`.
- Headers: APIKey from SAP_Config__c Custom Setting, Accept-Encoding: identity (SAP API Hub gzip workaround per ADR-???).
- Parses OData v2 response: `{ d: { results: [ { MatlWrhsStkQtyInMatlBaseUnit, ... } ] } }`. Sums quantities across rows for the total available number.
- Writes `Order.SAP_Available_Quantity__c` + `Order.SAP_Inventory_Checked_At__c` back to the Order.
- Returns the available quantity + status to the caller.

### Decision phase

For each Order, compare SAP-reported available qty to the sum of requested OrderItem quantities:

- If SAP-available >= requested → **auto-activate**. Bulk update sets `Inventory_Status__c = 'In Stock'`, `Inventory_Confirmed_By__c = 'SAP MM'`, `Status = 'Activated'`. OrderTriggerHandler picks up the Status transition and runs Pattern 1 asset creation (ADR-012). Zero human approval, ~3 seconds end-to-end from rep click.
- Else (SAP-available < requested, OR SAP returned null because no SAP_Material_Number__c on the product, OR the SAP callout failed) → **fall back to warehouse approval path**. Same as ADR-011: publish Inventory_Check_Requested__e for the Slack notification, submit Order to Inventory_Approval, warehouse decides via the VF page, etc.

The Database.update for auto-activation uses allOrNone=false so RLM pricing-validation failures on demo Orders don't poison the whole batch. Any Order that fails activation in the auto path falls through to the warehouse path automatically.

### Why hybrid is the right answer, not pure SAP

- **JIRA stays valuable.** When SAP says "out of stock", the next step is "open a replenishment task." JIRA Service Management does that natively. Dropping JIRA would break the Path 2 from ADR-011 with no replacement.
- **Warehouse user keeps the exception surface.** Quality holds, allocation conflicts, dropship overrides all need a human. The VF page (ADR-011, ADR-020 for the LWC migration plan) is still where that happens.
- **Demo storyline is richer.** "When SAP can confirm, we skip the warehouse. When SAP can't, the warehouse decides." That's a defensible architecture story; "we replaced the warehouse with an API call" is naïve.

## Consequences

### Positive

- **Routine deals close ~3 seconds end-to-end.** Sales rep clicks Request Inventory Check → SAP responds → Order auto-activates → Assets mint → flow continues. No 12-hour wait for the warehouse to look at Slack.
- **Audit symmetry preserved.** SAP_Available_Quantity__c + SAP_Inventory_Checked_At__c are on the Order regardless of which path activates it. The Activity Timeline + ProcessInstanceStep audit (ADR-011) still works for the warehouse-decided cases.
- **JIRA workflow unaffected** for replenishment. ADR-011's Path 2 (JIRA Done → Order activate) still works — when SAP says insufficient and the warehouse routes to JIRA, the JIRA Done webhook converges on Order activation as before.
- **Sandbox demo works the same as production.** Sandbox returns qty=0 → every Order goes warehouse path → recruiter sees the fallback running. Production SAP returns real numbers → most Orders auto-activate. The code is identical; data drives behavior.
- **Recruiter signal: "Salesforce orchestrates SAP."** This is one of the more defensible Mittelstand DACH architecture patterns. SF is the customer-facing orchestrator; SAP is the master data + transaction backbone.

### Negative

- **Data dependency on Product2.SAP_Material_Number__c.** Products without a SAP material number fall through to warehouse approval. Operations team needs to maintain the SAP material mapping. The future Material Master sync (deferred SAP sprint item) will automate this.
- **SAP API Hub Sandbox sparse data.** Sandbox-based demos look like everything is "Out of Stock from SAP, falls back to warehouse." Demo narrative has to explain this transparently rather than claiming "look, SAP says 8 in stock!"
- **CPU cost on every inventory check.** Each request to SAP adds 200-500ms callout latency before the rep's "request submitted" feedback. Mitigated by async UX if it becomes a complaint (TBD; demo doesn't hit volume thresholds where this matters).
- **The auto-activate path skips the warehouse approval audit trail.** Demos compare poorly when one Order activates instantly with just a "SAP MM" Confirmed_By stamp, and another goes through 3 approval steps + JIRA tickets. Both are correct demo behaviors but the visual asymmetry is noticeable.

### Future state

- **Material Master nightly sync** (deferred from this sprint): a Mule scheduled flow pulls SAP Product master into SF Product2 to populate SAP_Material_Number__c automatically. Eliminates the data-dependency negative above.
- **SAP-side stock-level subscription** (further deferred): SAP Event Mesh publishes "stock changed" events; Mule listens; SF Product2 `SAP_Cached_Stock__c` field updates. Lets the demo show "SAP says 8 in stock!" without per-request callouts.
- **Per-line ATP** (deferred): current code checks the primary OrderItem only. Real B2B order with 5 line items needs ATP per line, with allocation-conflict resolution if some lines are short. ~2 days of additional work; out of demo scope.
- **Mule-mediated path** (per ADR-015 production externalisation): the direct Apex callout to SAP can route through Mule for retry / DLQ / transformation. The Apex contract (`SapMaterialStockService.checkOrderStock(orderId)`) is the same; only the URL it calls changes from SAP direct to Mule-as-proxy.

## Alternatives Considered

1. **SAP-only — no warehouse fallback.** Rejected because it would orphan the entire Slack + VF + JIRA workflow built in ADR-011 with no replacement for the exception cases (out of stock, quality holds, dropship overrides).
2. **Warehouse-only (current ADR-011, no SAP).** Already in place; this ADR keeps it as fallback. Going SAP-first speeds up the routine cases without losing the existing flow.
3. **SAP via Mule from the start.** Cleaner architecture (consistent with ADR-001's Mule-vs-Apex decision matrix) but added a Mule deployment dependency to the demo. The Apex-direct path ships faster; Mule migration is mechanical when needed.
4. **Mock SAP responses for the demo.** Considered — would let the demo show "SAP says 8 in stock!" without sandbox quirks. Rejected because mocking obscures the real integration code; recruiter would (correctly) ask "is this actually calling SAP or simulating?" The transparent "sandbox says 0, fallback fires" narrative is stronger.
5. **Synchronous Apex call vs async via platform event.** The synchronous path is fine here because SAP MM responses are fast (200-500ms) and the user is waiting on the Request Inventory Check button. Async would add ambiguity ("did it work? when does my Order activate?"). Phase 2 of the SAP sprint (ADR-023) uses async because the Order is already activated when SAP push runs — no user waiting.

## Related Decisions

- ADR-011 (Inventory Approval — Two Convergent Activation Paths) — the fallback path this ADR routes to when SAP can't confirm.
- ADR-012 (Order-First Pattern 1) — explains why Asset creation hangs off Order activation; this ADR triggers that activation directly when SAP says yes.
- ADR-013 (Webhook idempotency + Integration_Error__c) — the audit substrate for SAP failures.
- ADR-015 (Production Externalization Strategy) — the Inventory row of the externalisation table refers to this ADR.
- ADR-019 (Slack notification vs decision surface) — defends keeping JIRA as the replenishment tracker rather than replacing it.
- ADR-023 (SAP SD Sales Order Acknowledgment) — companion. ATP check happens upstream of Order activation; SD push happens downstream.
- Future ADR-???: Material Master Sync — automates the Product2.SAP_Material_Number__c population that this ADR depends on.

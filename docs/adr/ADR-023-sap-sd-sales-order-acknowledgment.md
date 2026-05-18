# ADR-023: SAP SD Sales Order Acknowledgment — Platform Event Decoupling on Order Activation

## Status

Accepted — implemented 2026-05-18 in the SAP Sprint Phase 2 session. Order_Activated__e platform event + SapSalesOrderService + OrderActivatedTrigger + Order.SAP_Sales_Order_Number__c + Order.Status_In_SAP__c live in the org. End-to-end verified against the SAP API Hub Sandbox.

## Context

ADR-018 documents the directional choice: SAP FI is the system of record for legal invoices and accounting postings; Salesforce Invoice is a billing intent. For that to work, every Order activation in Salesforce needs to land in SAP SD as a real Sales Order so SAP can drive fulfillment, billing, and the eventual FI posting.

The integration question: how does an Order activation in Salesforce get pushed to SAP SD?

Three constraints shape it:

1. **The activation is already a busy transaction.** OrderTriggerHandler.afterUpdate currently runs Pattern 1 asset creation (ADR-012). Adding a synchronous SAP callout to the same transaction creates "uncommitted work pending" failures (the activation DML has already happened by the time the trigger runs).
2. **SAP push is slow and can fail.** A real SAP S/4HANA POST to API_SALES_ORDER_SRV is typically 500-2000ms and can fail for many reasons (CSRF token expired, network blip, validation error, customer master not synced). A failure should NOT roll back the Salesforce activation — the customer-facing flow already committed; the SAP push is a downstream concern.
3. **SAP Sandbox is read-mostly.** The API Hub trial accepts POST requests but doesn't persist new sales orders. The integration code path is fully exercisable; the SAP-side state is not. Production SAP S/4HANA persists; the same code writes the SO number back to SF unchanged.

The classic pattern that handles all three: platform event indirection (ADR-003 mechanism, applied here to SF→SAP outbound instead of SAP→SF inbound).

## Decision

A new `Order_Activated__e` high-volume platform event with `publishBehavior=PublishAfterCommit`. OrderTriggerHandler.afterUpdate publishes the event when an Order transitions to Status=Activated; the new OrderActivatedTrigger picks it up and calls SapSalesOrderService.pushOrders. The service runs `@future(callout=true)` so the SAP callout happens in a fresh async context with no DML pending.

Concretely:

### Event publish (sync, within activation transaction)

- OrderTriggerHandler.afterUpdate detects Status transitions to Activated (same loop as Pattern 1 asset creation).
- For each newly-activated Order, builds an Order_Activated__e event with Order_Id__c, Order_Number__c, Account_Name__c, Total_Amount__c.
- `EventBus.publish(events)` — enqueues; doesn't block; publishBehavior=PublishAfterCommit guarantees the event is delivered only if the activation transaction commits successfully.

### Event consume (async, fresh transaction)

- OrderActivatedTrigger fires after-insert on Order_Activated__e in a new transaction with the Automated Process User context.
- Extracts the Order Ids and calls SapSalesOrderService.pushOrders(orderIds).
- pushOrders launches `publishToSapAsync(orderIds)` as `@future(callout=true)`. The async context has full callout permissions and no DML pending (clean slate).

### SAP push (async, full callout context)

- publishToSapAsync queries Orders that need pushing (skips ones with SAP_Sales_Order_Number__c already populated — idempotency).
- Marks each as Status_In_SAP__c='Pushing' (DML) BEFORE the callout, so concurrent retries or repeat events see in-progress state.
- Fetches CSRF token via HEAD on the API_SALES_ORDER_SRV root (SAP requires X-CSRF-Token on writes; HEAD with X-CSRF-Token: Fetch returns the token in response headers).
- POST `/s4hanacloud/sap/opu/odata/sap/API_SALES_ORDER_SRV/A_SalesOrder` with the OData v2 deep-insert payload: SO header + to_Item items.
- Payload uses sandbox-friendly defaults (SalesOrderType=OR, SalesOrganization=1010, DistributionChannel=10, SoldToParty=17100001 default customer). Production migration replaces these with config-driven values per ADR-015.
- On 2xx: parses SO number from `d.SalesOrder` of the response; writes back SAP_Sales_Order_Number__c + Status_In_SAP__c='Created'.
- On non-2xx: Status_In_SAP__c='Push Failed'; logs to Integration_Error__c via IntegrationErrorLogger.logHttpFailure (ADR-013 audit substrate).
- On callout exception: same as non-2xx, but logged via IntegrationErrorLogger.log(Exception) with stack trace.

### Where this differs from the sync ADR-022 Phase 1 pattern

ADR-022 (SAP MM ATP) calls SAP synchronously because the rep is actively waiting on the inventory-check button click. The latency (200-500ms) is acceptable and the result drives the UI ("auto-activated" vs "routed to warehouse").

ADR-023 (SAP SD Acknowledgment) calls SAP asynchronously because the Order is already activated — there's no UI to update at the call moment. The async pattern absorbs SAP-side latency and failures cleanly: the activation commits, the rep sees their Order Active, and the SAP push catches up later (~5-15 seconds in production, sandbox shows Status_In_SAP transition in <30 seconds).

## Consequences

### Positive

- **Activation transaction stays clean.** No callouts mixed with the activation DML; no risk of rolling back the activation due to a SAP-side hiccup.
- **Audit trail visible on the Order.** SAP_Sales_Order_Number__c + Status_In_SAP__c are queryable + reportable. Sales rep glances at the Order and sees "yes, this is in SAP, SO number 0090000456."
- **Failure surfaces transparently.** Push Failed status + Integration_Error__c row visible in the Integration Health dashboard (ADR-013). No silent integration loss.
- **Idempotent.** Re-firing the platform event (e.g., from manual retry or re-activation cycle) skips Orders that already have a SAP_Sales_Order_Number__c. The Push Failed status is the explicit "retry me" signal.
- **CSRF token handling is built in.** The HEAD + X-CSRF-Token: Fetch dance is a quirky SAP requirement; encapsulating it in fetchCsrfToken means callers don't think about it.
- **Same code works for sandbox AND production.** Sandbox returns non-2xx → Push Failed + error log row. Production returns 2xx + SO number → SAP_Sales_Order_Number__c populated. Different data, same code.
- **Recruiter narrative is clean.** "Order activates in Salesforce; SAP receives the SO acknowledgment asynchronously via Mule (or direct Apex in this demo); audit visible on the Order record + Integration Health dashboard."

### Negative

- **End-to-end latency observable.** Rep clicks Activate → Order shows Status=Activated immediately → SAP_Sales_Order_Number__c populates ~5-15 seconds later. Demo storyline should mention this ("watch the field populate in a few seconds").
- **Demo Sandbox doesn't show the happy path persistently.** Sandbox returns non-2xx → demo lands on Push Failed every time. The narrative has to explain "sandbox is read-mostly; production SAP returns the SO number." This is consistent with ADR-022's similar transparency about sandbox sparseness.
- **CSRF token fetch is an extra hop.** Roughly doubles the callout count per push (HEAD for token, then POST for SO). Mitigated by sandbox accepting requests without CSRF; HEAD failure is non-fatal.
- **Two custom fields on Order add to the Page Layout cost.** SAP_Sales_Order_Number__c + Status_In_SAP__c are useful but the Order page is getting crowded. Future Page Layout refactor will probably collapse SAP-related fields into a "SAP Integration" component or sub-tab.
- **Hard-coded SAP defaults in the payload.** SalesOrganization=1010, SoldToParty=17100001 are sandbox defaults. Production needs an Account-to-SAP-Customer mapping (similar to the Product-to-Material mapping in ADR-022). Out of scope for this ADR; planned in the future "SF Account → SAP BP sync" ADR (related to ADR-021).

### Future state

- **Bidirectional events.** SAP publishes "SO status changed" events via SAP Event Mesh; Mule subscribes; SF Order.Status_In_SAP__c updates to Fulfilled, Cancelled, etc. without polling. ~1 sprint of additional work; deferred.
- **Cancellation flow.** If SF Order is cancelled after SAP push, send a cancellation request to SAP. Today SF Order can be edited but the SAP SO isn't synchronised — drift risk. Production design: SF Order changes publish a separate Order_Modified__e event, Mule reconciles with SAP.
- **Per-line allocation conflicts.** SAP can accept a SO but flag specific items as backordered. Today the SF write-back only captures the SO number, not per-line ATP results. Production: add OrderItem.SAP_ATP_Status__c picklist.
- **Mule-mediated path** (per ADR-015): the direct Apex POST migrates behind a Mule HTTP listener that adds retry, DLQ, idempotency, transformation. Apex contract stays; URL changes.

## Alternatives Considered

1. **Synchronous direct call from OrderTriggerHandler.afterUpdate.** Rejected because of "uncommitted work pending" — the activation DML already happened, callouts forbidden.
2. **Queueable instead of @future.** Queueable gives error introspection (Database.executeBatch returns a job id, you can monitor) which @future doesn't. Queueable also allows chaining. Considered; rejected for the demo because @future is simpler and the demo doesn't need the introspection. Production migration to Queueable is mechanical.
3. **Mule platform-event subscriber (replay channel) instead of Apex trigger + @future.** Cleaner externalisation, but adds Mule as a dependency for the demo path. Deferred to the Mule-mediated future state per ADR-015. The Apex path ships now without Mule running.
4. **Sync via Outbound Message metadata.** Outbound Messages are quaint Workflow-era constructs with limited retry and no modern auth. @future is the modern pattern.
5. **Direct SAP push from a Flow without Apex.** Flow can make HTTP callouts (with the right setup) but doesn't have @future / async context cleanly. The audit + error-logging shape ends up rebuilt anyway. Apex is the right tool here.

## Related Decisions

- ADR-003 (Site Guest User + platform event indirection) — the inbound webhook pattern; this ADR applies the same indirection to outbound (SF→SAP).
- ADR-005 (Kevin O'Hara TriggerHandler) — the framework OrderTriggerHandler extends.
- ADR-011 (Inventory Approval Two Convergent Activation Paths) — the upstream activation paths that lead to Status=Activated, which triggers this ADR's flow.
- ADR-013 (Webhook idempotency + Integration_Error__c) — the audit substrate for SAP push failures.
- ADR-015 (Production Externalization Strategy) — the Order Acknowledgment row of the externalisation table points to this ADR.
- ADR-018 (Salesforce Invoice vs SAP Invoice) — the downstream consequence of this ADR. SAP receives the Order via API_SALES_ORDER_SRV; SAP FI then creates the invoice.
- ADR-022 (SAP MM ATP Integration) — companion. ATP runs upstream of activation; this ADR runs downstream.
- Future ADR-???: SF Account → SAP Business Partner sync — fixes the SoldToParty hardcode in this ADR's payload.

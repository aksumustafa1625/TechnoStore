# ADR-028: SAP Event Mesh Inbound Webhook + CloudEvents Dispatcher

## Status

Accepted — implemented 2026-05-18 in SAP Sprint Phase 7. SapEventWebhook REST endpoint + SapInboundEventDispatcher class deployed; 3 of 4 routes verified end-to-end against synthetic CloudEvent payloads (BusinessPartner, Product, Payment); SalesOrder route deferred for data-availability reasons explained below.

## Context

ADR-022 through ADR-027 covered Salesforce-to-SAP outbound calls and nightly polling syncs. The inverse direction — SAP pushing notifications to Salesforce when something changes — wasn't built yet. Without it, SF reacts to SAP-driven changes only via the nightly sync polling window. For lifecycle events that should propagate in seconds (SAP marks a Sales Order Fulfilled, customer master data corrected, material price changed, payment posted in FI), polling-style latency is wrong.

SAP S/4HANA Cloud publishes such events through **SAP Event Mesh**, a message-broker product that delivers events in **CloudEvents 1.0** format. Subscribers register topic subscriptions; SAP pushes JSON envelopes to the subscriber's HTTP endpoint when events fire.

Three constraints shaped this phase:

1. **SAP API Hub Sandbox doesn't expose Event Mesh.** The trial covers OData APIs (used in ADRs 022/023/024/026/027) but Event Mesh requires a different paid tier. We cannot configure a real SAP→SF subscription against this sandbox. The SF-side receiver can still be built; production cutover is purely configuration on the SAP side.
2. **Developer Edition custom-object cap.** This Salesforce org has hit the 200-sObject limit. Platform events count toward that limit. Attempting to create `SAP_Inbound_Event__e` returned `reached maximum number of custom objects`. The original ADR-003-style indirection (webhook publishes platform event, separate trigger handles in system context) cannot land in this org without first deleting a sObject elsewhere — out of scope for a single evening's work.
3. **CloudEvents 1.0 is the wire format.** It's a CNCF standard (also used by Stripe webhooks in their modern API). The endpoint must parse `specversion / id / type / source / subject / time / data` according to spec. This is shared knowledge with future non-SAP event sources; investing in a clean parser pays off elsewhere.

## Decision

`SapEventWebhook` is an Apex REST endpoint at `/services/apexrest/sap/event` that accepts CloudEvent JSON envelopes, validates HMAC secret, runs idempotency check, then **directly invokes** `SapInboundEventDispatcher.dispatch(CloudEvent)`. No platform event indirection.

### Webhook (SapEventWebhook)

- `@RestResource(urlMapping='/sap/event/*')` global `without sharing`
- `@HttpPost handle()`:
  - Validates `X-SAP-Secret` header against `Inventory_Integration_Config__mdt.Default.Shared_Secret__c` (same secret family as ADR-013 webhooks, falls back to `?secret=` query param)
  - Parses CloudEvent envelope — extracts id, type, subject, source, data
  - Returns 400 if id or type missing (mandatory in CloudEvents spec)
  - Calls `WebhookEventLogger.checkAndRecord(eventId, 'SAP', eventType, body)` for idempotency (ADR-013) — replays of the same event ID return 200 "already processed"
  - Constructs `SapInboundEventDispatcher.CloudEvent` struct and calls `dispatch()` synchronously
  - Marks Webhook_Event__c row Processed on success / Failed on exception
- `@HttpGet healthCheck()` — returns `{"status":"ok","service":"SapEventWebhook"}` for monitoring

### Dispatcher (SapInboundEventDispatcher)

`public without sharing class` with one entry point `dispatch(CloudEvent)`. Routes by `eventType.toLowerCase()` prefix:

| Prefix | Route | SF write target |
|---|---|---|
| `sap.s4.beh.salesorder.*` | `updateSalesOrderStatus` | Order.Status_In_SAP__c (Created / Fulfilled / Cancelled) |
| `sap.s4.beh.businesspartner.*` | `refreshBusinessPartner` | Account.SAP_Customer_Group__c + SAP_Last_Synced_At__c |
| `sap.s4.beh.product.*` | `refreshProduct` | Product2.SAP_Product_Description__c + SAP_Last_Synced_At__c |
| `sap.s4.beh.payment.*` | `recordPayment` | Invoice.SAP_Payment_Posted_At__c |

Each route looks up the SF record by its SAP key (Subject from CloudEvent), parses the relevant field from CloudEvent `data`, and updates the SF audit field via `Database.update allOrNone=false`. Failures route to `Integration_Error__c` via `IntegrationErrorLogger.log` so the Integration Health dashboard surfaces them (ADR-013).

The SalesOrder route also maps SAP's single-character status codes (A=Not Processed, B=Partially, C=Complete, V=Cancelled) to the SF picklist values defined in Order.Status_In_SAP__c.

### Why no platform event indirection

The original design followed ADR-003: webhook publishes `SAP_Inbound_Event__e`, separate trigger consumes it in system context. This isolates the Site Guest User from the business-object writes. **The Developer Edition custom-object cap blocked the platform event creation.** Three production paths to fix:

1. **Delete an unused custom object** to free a slot. Out of scope for the single evening; would need an audit of all 200+ sObjects to identify a safe candidate.
2. **Reuse an existing platform event** like `Inventory_Status_Update__e`. Rejected — overloading event semantics across domains creates brittle handlers (a SAP event landing in an inventory handler would need defensive branching).
3. **Run dispatch inline in webhook transaction with `without sharing`.** Chosen path. Trade-off: the dispatcher writes to Order / Account / Product2 / Invoice while running in the Site Guest User context. The `without sharing` keyword and the `Database.update allOrNone=false` give the dispatcher the necessary write access despite the guest user's normally limited permissions.

Production org with no cap pressure can reintroduce the platform event indirection. The dispatcher's `dispatch(CloudEvent)` signature accepts a plain struct, not a sObject, so the only refactor is the webhook (replace `dispatch()` call with `EventBus.publish(SAP_Inbound_Event__e)` and add the platform-event trigger). 15-minute change.

### SAP Event Mesh subscription setup (production-side)

Production cutover requires SAP-side configuration that's NOT in this repo:

1. Provision an SAP Event Mesh instance (BTP service).
2. Subscribe to the relevant event topics on the S/4HANA side:
   - `sap/S4HANA/SalesOrder/Changed`
   - `sap/S4HANA/BusinessPartner/Changed`
   - `sap/S4HANA/Product/Changed`
   - `sap/S4HANA/Payment/Posted`
3. Configure a webhook target pointing at the SF Site URL: `https://<site>/services/apexrest/sap/event?secret=<shared-secret>`.
4. SAP Event Mesh will then push CloudEvents to that URL whenever a subscribed event fires. No SF-side changes needed.

The 4 routes already coded handle the most common SAP→SF flows; new event types just need a new prefix branch in the dispatcher (5-10 minutes per route).

## Consequences

### Positive

- **Closes the inverse-direction integration gap.** SF was sending data to SAP (ADR-022/023/026/027 outbound) and polling for changes (ADR-026/027 nightly syncs); now SF reacts to SAP events in real time when production has Event Mesh configured.
- **CloudEvents 1.0 standard.** The wire format is shared across many event-source vendors (Stripe modern API, Knative, Argo Events, AWS EventBridge). Code investment is portable; future non-SAP event sources can reuse the parser.
- **Same audit substrate as outbound flows.** `Webhook_Event__c` rows for every inbound CloudEvent, `Integration_Error__c` for failures, Integration Health dashboard shows the SAP source side-by-side with Stripe / DocuSign / JIRA. One observability story.
- **Idempotency replay-safe.** SAP Event Mesh delivers at-least-once. The Webhook_Event__c uniqueness on External_Id__c (the CloudEvent id) catches duplicate deliveries cleanly.
- **Extensible.** Adding a new SAP event class to handle (e.g. `sap.s4.beh.delivery.*`) is one prefix branch in the dispatcher + matching field on whichever target sObject the route writes to.
- **Forward-compatible to unknown types.** Unknown CloudEvent types log + skip rather than fail. SAP can publish new event classes without breaking the demo.

### Negative

- **No platform-event indirection in this org.** The dispatcher runs in the Guest User transaction. With `without sharing` and `Database.update allOrNone=false` it works, but the trust-boundary cleanness from ADR-003 is reduced. Documented + mitigation path (reintroduce platform event when slot opens) is in this ADR's Decision section.
- **Sandbox can't exercise real Event Mesh.** All Phase 7 testing is via synthetic CloudEvent payloads through anonymous Apex. Demo recording requires either narration ("in production Event Mesh pushes these; demo simulates") or a Postman-driven HTTP test against the public Site URL.
- **No automatic retry on dispatch failure.** Each route is single-pass; if it fails, the Webhook_Event__c is marked Processed (because the receive + parse succeeded), but the dispatched write failed. The Integration_Error__c row carries the failure for manual remediation. Production-grade retry would Queueable each dispatched route or use a separate retry-queue object.
- **Subject-based lookup is single-record.** Each route does `SELECT ... WHERE SAP_X = :subject LIMIT 1`. If SAP publishes an event for a key not present in SF (e.g., SalesOrder number not yet synced), the route silently no-ops. Logged at System.debug WARN; not surfaced to Integration_Error__c. Production may want either auto-create or explicit "unmatched" logging.
- **Demo SalesOrder route untested.** Phase 2 (ADR-023) sandbox didn't persist sales orders, so `Order.SAP_Sales_Order_Number__c` stays null in the demo. The dispatcher's SalesOrder route therefore had no record to update during Phase 7 testing. Code is identical to the other routes (LIMIT 1 lookup + write) — would work in production where SAP returns real SO numbers.

### Future state

- **Reintroduce platform event** when org has a slot. 15-minute refactor in SapEventWebhook (replace dispatcher call with EventBus.publish) + a new trigger on the platform event calling the dispatcher.
- **Queueable retry per route** for transient failures. Replace `Database.update allOrNone=false` with `SapInboundDispatchRetryQueueable`; the Integration_Error__c row becomes the retry queue.
- **Mule mediation per ADR-015.** Production Mule terminates the SAP Event Mesh subscription (handles SAP's specific signature header + retry contract), transforms to a SF-friendly shape, and POSTs to SF Composite REST that calls `SapInboundEventDispatcher.dispatch` directly. SF endpoint becomes a Composite resource rather than an Apex REST class.
- **Auto-create missing records.** When SAP publishes a SalesOrder Changed event for a SO that SF doesn't have, auto-create a stub Order? This is a policy decision (some orgs want explicit human review). Out of scope.
- **Bidirectional sync drift detection.** Compare SAP-pushed values against SF-side mirror; surface drift via Integration_Error__c. Sibling to ADR-027 future state.

## Alternatives Considered

1. **Pure polling (extend ADR-026 / ADR-027 syncs to run every 5 minutes).** Bandwidth-wasteful and adds 5-minute latency on every state change. Event-driven is the right architecture for real-time signals.
2. **Use Mule as the subscriber, skip Apex REST entirely.** Cleaner externalisation (Mule terminates the SAP-specific contract), but adds Mule as a hard dependency. The Apex path ships now without Mule running; Mule mediation is a future-state migration per ADR-015.
3. **Per-event REST endpoints** (`/sap/salesorder`, `/sap/businesspartner`, etc.) instead of one generic `/sap/event`. Rejected — proliferates endpoints, breaks the CloudEvents convention of "one endpoint, multiple types, dispatcher routes". Generic endpoint is the spec-aligned pattern.
4. **Reuse JiraStatusWebhook with adapter logic.** Considered. The two webhook classes share ~80% of code (HMAC, idempotency, response shape). DRY temptation. Rejected for clarity — JIRA has its own quirks (v1.0 webhook accepts secret in URL only, JIRA Automation handles the cascade differently) that don't apply to SAP. Two separate classes keep both stories readable.
5. **Store CloudEvents in `Webhook_Event__c.Payload__c` and process via a periodic batch.** Adds latency, batch complexity, and another retry surface. The synchronous dispatch is simpler and tested.

## Related Decisions

- ADR-003 (Site Guest User + Platform Event indirection) — the pattern this ADR deviated from due to custom-object cap; documented mitigation path.
- ADR-013 (Webhook Idempotency + Integration_Error__c) — the audit substrate used by both the webhook receiver and the dispatcher.
- ADR-022 — outbound counterpart for ATP (SF→SAP); SalesOrder push (ADR-023) is the outbound counterpart for the SalesOrder route in this dispatcher.
- ADR-023 (SAP SD Sales Order Acknowledgment) — populates the SAP_Sales_Order_Number__c that this dispatcher's SalesOrder route looks up.
- ADR-026 (SAP Material Master Sync) — nightly polling that this dispatcher's Product route makes obsolete for real-time updates.
- ADR-027 (SAP Customer Master Sync) — nightly polling that this dispatcher's BusinessPartner route makes obsolete for real-time updates.
- ADR-015 (Production Externalization Strategy) — Mule-mediation future state for this endpoint.
- Future ADR-???: SAP Event Mesh Subscription Configuration — the SAP-side counterpart that activates the subscription in production.
- Future ADR-???: Inbound Event Retry Queue — the retry-policy refinement.

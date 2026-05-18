# ADR-013: Webhook Idempotency + Centralised Integration Error Logging

## Status

Accepted — implemented 2026-05-18.

## Context

TechnoStore integrates three external systems via inbound webhooks (Stripe payment events, DocuSign Connect signature events, JIRA Cloud automation/webhook v1.0). All three providers explicitly document **at-least-once delivery**: the same event can arrive multiple times because of provider timeout retries, network packet loss after a 200 OK, manual replays from provider dashboards, or multi-region failover.

Without protection, a duplicate webhook means a duplicate side effect: Stripe `checkout.session.completed` firing twice would re-mark the Invoice paid, re-trigger Sendcloud parcel creation, and re-send the receipt email; a DocuSign `envelope-completed` retry would publish two `DocuSign_Status_Update__e` events; a JIRA Done retry would re-activate an already-active Order. None of these are detected by the current code path because each webhook handler is stateless — it processes whatever JSON arrives.

A second, related gap: integration failures are invisible. When Mule's Sendcloud POST returns 500 it logs to Anypoint Runtime Manager (separate UI). When Apex's `@future` callout throws inside a webhook, the error gets a single `System.debug` line that disappears the moment the debug log rotates. There is no central catalogue of "what's broken right now across SF + Mule + the seven providers."

## Decision

Two new custom objects + two helper classes, wired into every inbound webhook handler:

### `Webhook_Event__c`

Idempotency ledger. Seven fields (`External_Id__c` Unique + External Id, `Source__c`, `Event_Type__c`, `Payload__c`, `Status__c`, `Processed_At__c`, `Error_Message__c`, `Related_Record_Id__c`). The Unique constraint on `External_Id__c` is the **DB-level guard**: a duplicate insert with the same key raises `DUPLICATE_VALUE` and the DB never stores two rows for one provider event. AutoNumber `WE-{00000000}` for the Name.

### `Integration_Error__c`

Central error log. Eleven fields (`Source_System__c`, `Operation__c`, `Error_Type__c`, `Error_Message__c`, `Stack_Trace__c`, `Payload__c`, `Related_Record_Id__c`, `Correlation_Id__c`, `Severity__c`, `Status__c`, `Retry_Count__c`, `Resolved_At__c`). AutoNumber `ERR-{00000000}`. Picklists for Source / Type / Severity / Status so dashboards can group.

### `WebhookEventLogger` (Apex, without sharing)

Two-method API: `checkAndRecord(externalId, source, eventType, payload)` returns a `RecordResult{ isDuplicate, row }` — `true` means the handler should short-circuit with 200 OK + a "duplicate delivery dropped" message; `false` means a fresh `Webhook_Event__c` row was inserted with Status=Received and the handler should proceed. Then `markProcessed(row, relatedId)` / `markFailed(row, ex)` close the lifecycle. The pre-check is an SOQL by indexed `External_Id__c`; if it misses, the `insertReceived` call has a try/catch that catches `DUPLICATE_VALUE` and re-queries, so two parallel HTTP calls landing on the endpoint at the same millisecond both end up with one survivor and one duplicate signal — race-condition safe.

### `IntegrationErrorLogger` (Apex, without sharing)

`log(Request)` writes a single row; `log(source, operation, exception, relatedId, correlationId)` and `logHttpFailure(source, operation, response, reqBody, relatedId, correlationId)` are convenience overloads for the two common Apex patterns. `newCorrelationId()` mints a UUID-ish 36-char string from `Crypto.generateAesKey(128)` so SF → Mule → provider can stamp the same id across logs for one business transaction. All inserts use `Database.insert(allOrNone=false)` so a logger failure cannot poison the caller's transaction. The logger never re-throws and never suppresses upstream — its sole job is best-effort write.

### Two-Layer Defense

1. **DB layer**: `External_Id__c` Unique constraint. Even if Apex pre-check misses, the second insert raises DUPLICATE_VALUE and the database is the final arbiter of "one event = one row."
2. **Apex layer**: `WebhookEventLogger.checkAndRecord` does the SOQL pre-check before the insert. The happy path is one query + one insert; the duplicate path is one query, no insert, immediate 200 response. Saves DML on the duplicate case and avoids the exception path noise.

### Site Guest User constraints

Webhooks run as the Site Guest User. That user's license blocks `Edit` on custom objects even with permset grants, so the permission set grants `Create + Read` only. `markProcessed` and `markFailed` therefore wrap their `Database.update` calls in try/catch and swallow update failures — the lifecycle `Status__c` won't transition from Received → Processed under the Guest User, but the core dedup (the existing row blocking duplicates) is independent of this transition and stays correct. The classes are `without sharing` so the SOQL pre-check sees the row inserted milliseconds earlier in a parallel transaction even when sharing rules don't grant the Guest User access to the record. ADR-003 (Site Guest User + platform event indirection) is the prior decision this pattern composes with.

### Wiring

`JiraStatusWebhook.handle()` and `DocuSignConnectWebhook.handle()` both:

1. Mint a correlation id at entry.
2. Extract the event's natural unique key — `issueKey|status|timestamp` for JIRA, `envelopeId|status` for DocuSign.
3. Call `checkAndRecord`. On duplicate → respond 200, return.
4. Run the existing logic (find Order, publish platform event).
5. On success → `markProcessed`. On expected non-2xx response paths (404 no Order, 200 already activated) → still `markProcessed` so the lifecycle reflects "received but no-op."
6. On any exception → `markFailed` plus `IntegrationErrorLogger.log` with the correlation id, then re-respond 500.

Stripe's webhook is handled in Mule, not Apex, and is the **deferred** branch of this ADR. The Mule flow already has structured error handling; what it doesn't have is the SF-side ledger. Either Mule writes to `Webhook_Event__c` via the salesforce:create connector before invoking the SF Invoice-update REST call (preferred), or the SF Invoice REST endpoint itself wraps its body in the same idempotency check. Decision: implement the SF-side wrapper when the next idempotency-sensitive Stripe event type is added (`payment_intent.succeeded`, `charge.refunded`); for the current `checkout.session.completed` flow the Mule built-in retry is sufficient because the downstream actions are themselves idempotent (PATCH Invoice.Status=Paid is a set, not an increment).

## Consequences

### Positive

- Provider retries are no-ops. The end-to-end PowerShell test (three sequential POSTs with the same `issueKey|status`) confirms: call 1 inserts and 404s on the (intentionally missing) Order; calls 2 and 3 both respond 200 with "duplicate delivery dropped" and no extra DB row appears.
- Every webhook event is auditable from inside Salesforce — Reports tab can answer "how many DocuSign events did we receive last 24 hours" and "which failed."
- Every integration failure has a single home with severity, payload, stack trace, and a correlation id to trace across systems. No more grepping debug logs.
- Pattern is reusable: any new inbound webhook (Sendcloud return-notification, SAP outbound IDoc, Slack interactive callback) can wire `checkAndRecord` in two lines.

### Negative

- Two more custom objects to permission-set, monitor, and clean up. Webhook_Event__c grows roughly one row per inbound event — for a demo this is trivial but a production org should add a scheduled batch to archive/purge rows older than 90 days.
- Status lifecycle (`Received` → `Processed` / `Failed`) doesn't transition under the Guest User. Visible incompleteness on the audit dashboard. Future fix: have `InventoryStatusUpdateTriggerHandler` (or a new platform event consumer) flip the status when the downstream work completes — that trigger runs as Automated Process and has full CRUD.
- The DUPLICATE_VALUE catch in `checkAndRecord` swallows the SF DML error and re-queries — minor query cost in the rare race case.

### Out of scope (future work)

- Mule-side `Webhook_Event__c` writes for the Stripe flow.
- Slack notification flow on `Integration_Error__c` Severity=Critical insert (existing pattern: record-triggered flow → MuleSoft platform event → Slack #integration-ops webhook).
- Integration Health dashboard (Last 24h errors by source, top error types, MTTR widget).
- Retry-Count automation: a scheduled Apex that picks `Status=Failed` rows < 1h old, retries the downstream call via `@future`, increments `Retry_Count__c`. Adds resilience but needs an idempotent downstream — the existing handlers already are.

## Alternatives Considered

1. **Platform Event–based idempotency**: publish a wrapper event from the webhook and dedupe in the trigger. Rejected because Platform Events don't have a native Unique-key dedup; we'd still need the custom object.
2. **Cache-based dedup (Platform Cache org partition)**: faster lookup but cache TTLs are lossy and Platform Cache space is limited on Developer Edition.
3. **External Object pointing at a dedup service**: real overkill at this scale.
4. **Per-handler ad-hoc checks** (e.g. set a custom field on the related record): scatters logic across every webhook, breaks reusability.
5. **DB-only (Unique constraint without Apex pre-check)**: works but every duplicate hits the exception path which is noisier in logs and consumes a wasted DML.

## Related Decisions

- ADR-003 (Site Guest User + platform event indirection) — predecessor; this ADR composes with it.
- ADR-001 (Mule vs Apex matrix) — informs why Stripe lives in Mule and JIRA/DocuSign in Apex.
- Future ADR-014: Integration Health dashboard + Slack #integration-ops alert flow (the visible surface for Integration_Error__c).

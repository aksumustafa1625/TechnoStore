# ADR-003: Salesforce Site + Guest User + Platform Event Indirection for Inbound Webhooks

## Status

**Accepted**

## Date

2026-05-06

## Author

Mustafa Aksu

## Context

TechnoStore consumes inbound webhooks from external systems that must update Salesforce records:

- **DocuSign Connect** — when the customer completes signing, fires `envelopeStatus=Completed` event to a configured public URL. Salesforce must flip `Contract.Status` from `Awaiting Signature` to `Signed`.
- **Stripe Connect** — when payment succeeds, fires `payment_intent.succeeded` event. Salesforce must flip `Order.Status` to `Paid` (this path actually goes through Mule first, see ADR-001, but the underlying SF write pattern is the same).
- **Sendcloud delivery tracking** (future) — when DHL updates a parcel's tracking status, Salesforce must update `Order.Tracking_Status__c`.

Inbound webhooks require a **publicly-reachable URL** — Salesforce REST endpoints behind authentication are not reachable from third-party webhook senders without complex OAuth client-credentials setup (and even then, many webhook providers don't support that flow). The native Salesforce primitive for public endpoints is **Salesforce Sites** (`force.com/yourdomain` or `*.my.site.com`), which exposes Apex `@RestResource` classes via Guest User profile.

The Guest User profile, however, has **restrictive Field-Level Security** by default:

- Cannot directly write standard fields like `Contract.Status`, `Order.Status`. These are platform-locked for Guest profiles per Salesforce security best practices.
- Adding FLS write permission for these standard fields to a Guest profile violates the security recommendation surfaced in Setup → Security → Health Check and may not even be permitted by platform validation in newer orgs.

The classic workaround — making the webhook controller `without sharing` and explicitly DMLing in system context — is a foot-gun (it bypasses every sharing rule, not just the FLS restriction on the target field) and gets flagged by PMD Apex security rules.

A clean architectural pattern is needed that:

1. Exposes a public webhook receiver via Salesforce Sites + Guest User
2. Performs strict signature verification (HMAC) at the boundary
3. Updates internal records (Contract.Status, Order.Status) with full FLS + sharing context
4. Is idempotent under webhook retries (DocuSign retries up to 3 days, Stripe retries with exponential backoff)
5. Has a clear audit trail (who/what/when triggered the state change)

## Decision

Adopt the **Salesforce Site + Guest User + Platform Event indirection pattern** for all inbound webhooks that need to update internal records:

1. **Salesforce Site** exposes the webhook URL (e.g., `https://your-org.my.site.com/docusign_webhook`).
2. **Apex `@RestResource` controller** receives the POST under Guest User profile context.
3. **HMAC signature verification** at the controller boundary (DocuSign uses `X-DocuSign-Signature-1`; Stripe uses `Stripe-Signature`). Reject with 401 on mismatch.
4. **Guest User publishes a Platform Event** (`DocuSign_Signed__e`, `Stripe_Payment_Succeeded__e`, etc.) — Guest profiles can publish Platform Events even though they cannot directly write Contract/Order fields. This is a separately-permissioned action.
5. **Apex trigger on the Platform Event channel** runs in **system context** with full FLS + sharing access; it queries internal records by the external correlation key (envelopeId, paymentIntentId) and performs the DML.
6. **Idempotency guard** in the trigger subscriber: filter `WHERE Status != 'Signed'` (or equivalent target state) so re-delivery of the same event does not flip state twice.

For DocuSign signed webhook specifically:

```
Customer signs → DocuSign Connect POST /docusign_webhook
    → Guest User context: DocuSignWebhookController.receiveSignedEvent()
        → HMAC verify (X-DocuSign-Signature-1 vs HMAC-SHA256 of body + DocuSign_Config__c.HMAC_Secret__c)
        → if valid: EventBus.publish(new DocuSign_Signed__e(Envelope_Id__c=envelopeId, Envelope_Status__c='Completed'))
        → return 200 OK to DocuSign within 30 seconds (DocuSign's retry threshold)
    → System context: trigger on DocuSign_Signed__e (after insert)
        → SELECT Id FROM Contract WHERE DocuSign_Envelope_Id__c IN :envIds AND Status != 'Signed'
        → UPDATE Contract.Status = 'Signed' (DML with full FLS)
```

## Consequences

### Positive

- **Security boundary is clean** — Guest User does NOT have direct write access to Contract/Order; the indirection enforces this architecturally.
- **HMAC verification is enforced** at the webhook boundary — webhook spoofing is structurally prevented.
- **System-context DML** in the Platform Event subscriber bypasses Guest FLS restriction without compromising the Guest profile's security posture.
- **Idempotent under retry** — DocuSign + Stripe both retry aggressively on non-2xx; the `Status != 'Signed'` filter makes re-delivery a no-op.
- **Reusable pattern** — same architecture works for DocuSign Connect (Contract.Status), Stripe webhook (Order.Status), Sendcloud delivery webhook (future), JIRA issue update webhook (future). Each new webhook needs: 1 Apex controller + 1 Platform Event + 1 trigger subscriber.
- **Audit trail via Platform Events** — `EventBus.publish` is logged in the org's Platform Event delivery records, giving a "who fired what when" trail visible in Setup.

### Negative / Trade-offs

- **Eventual consistency** — there is a brief delay (typically 100ms-2s) between Platform Event publish and trigger subscriber execution. Not noticeable to users in this demo's use cases, but matters for synchronous response patterns.
- **Two-step debugging** — when a webhook isn't updating a record, the engineer must check both the Guest User log (controller side) AND the system-context log (trigger subscriber side). Standard Debug Log filtering is not Guest-aware, requiring careful trace flag setup.
- **Platform Event delivery is best-effort** — Salesforce guarantees delivery within 24 hours but does not guarantee 100% within seconds. For payment-affecting events this is acceptable (the source of truth is Stripe/DocuSign, Salesforce mirrors); for tighter coupling it would not be.
- **One extra metadata file per webhook** — the Platform Event sObject (`DocuSign_Signed__e`) is a deployable artifact that must be in source control.

## Alternatives Considered

### Alternative A — `without sharing` controller writes Contract directly

Rejected because:
- Bypasses ALL sharing rules, not just the FLS restriction on `Contract.Status`. A bug in the controller could now write to any field on any record.
- PMD Apex security rules (`ApexCRUDViolation`, `ApexSharingViolations`) flag this pattern on every scan.
- Salesforce security review (relevant if the org is later promoted to a managed package or production) explicitly recommends against Guest User direct writes to standard fields.

### Alternative B — Grant Guest User FLS on `Contract.Status` directly

Rejected because:
- Setup → Security → Health Check flags this with a warning.
- Future Salesforce releases may platform-block this for standard fields entirely (the trend is toward more Guest restrictions, not fewer).
- Doesn't generalize — every new webhook target field needs another FLS grant.

### Alternative C — Outbound Message + named credential callback

Rejected because:
- Salesforce Outbound Messages are point-to-point and don't fit the webhook receiver pattern (they fire FROM Salesforce, not TO).
- Wrapping the inbound webhook in an OAuth flow + named credential callback is over-engineering for a simple "external event happened, update internal record" pattern.

### Alternative D — Use MuleSoft as the webhook receiver, write to SF via Salesforce Connector

Considered for DocuSign but rejected because:
- Adds a hop (DocuSign → Mule → SF) for what is otherwise a direct call
- The DocuSign-specific HMAC verification logic ends up in Mule, separated from the Salesforce-side Contract logic that consumes it
- Already using this pattern for Stripe webhook where Mule adds genuine value (Scatter-Gather fan-out to multiple downstream actions); DocuSign webhook fans out to just one update (Contract.Status), so Mule overhead is not justified

## References

- **Memory**: `docusign_integration_progress.md` (full bidirectional integration documentation)
- **Notion portfolio entry**: 28 — "DocuSign Inbound Webhook — Site + Guest User + Platform Event Indirection"
- **Code**: `force-app-handlers/main/default/classes/DocuSignConnectWebhook.cls` + `DocuSignStatusUpdateTriggerHandler.cls`
- **Schema**: `force-app/main/default/objects/DocuSign_Signed__e/`
- **Site**: `force-app/main/default/sites/docusign_webhook.site-meta.xml`
- **Related ADRs**: ADR-001 (Mule vs Apex matrix — this is the inbound-webhook half of the Apex column)
- **Salesforce docs**: [Guest User Security Policies](https://help.salesforce.com/s/articleView?id=sf.networks_guest_user_security_overview.htm)

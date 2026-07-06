# Security Model

This document is the single source of truth for how TechnoStore handles authentication, authorization, secret storage, and webhook verification. It is written to be honest about the current implementation reality and what is on the hardening roadmap.

## Webhook authentication — accurate state

TechnoStore has **eight** inbound webhooks split across two layers. They are NOT all HMAC-verified today. The exact model per webhook:

| Webhook | Layer | Current authentication | Idempotency | HMAC status |
|---------|-------|------------------------|-------------|-------------|
| Stripe payment events | MuleSoft `stripe-webhook-receive.xml` | **True HMAC-SHA256** (DataWeave `Crypto::HMACBinary`) + 5-min timestamp freshness | Stripe `event.id` | ✅ Enforced |
| DocuSign Connect | Apex `DocuSignConnectWebhook` (SF Site) | Payload-shape validation + envelope-id idempotency | `envelopeId + status` | ⏳ Planned (TS-SEC-002) |
| JIRA status change | Apex `JiraStatusWebhook` (SF Site) | `X-Jira-Secret` header **plaintext equality** (fallback `?secret=`) | `issueKey + status + timestamp` | ⏳ Planned (TS-SEC-002) |
| SAP Event Mesh (CloudEvents 1.0) | Apex `SapEventWebhook` (SF Site) | `X-SAP-Secret` header **plaintext equality** (fallback `?secret=`) | CloudEvent `id` | ⏳ Planned (TS-SEC-002) |
| Twilio WhatsApp | Apex `WhatsAppWebhookRestService` (SF Site) | `?secret=` query param **plaintext equality** | Twilio `MessageSid` | ⏳ Planned — for production use `X-Twilio-Signature` (Base64 HMAC-SHA1 of URL + sorted POST params) |
| Inventory approval callback | Apex `InventoryCheckCallback` (SF Site) | Shared secret in JSON body **plaintext equality** | (none — event-based) | ⏳ Planned (TS-SEC-002) |

### Why the split

The MuleSoft layer wraps every integration where MuleSoft adds durable value (retry / DLQ / fan-out) — see ADR-001 for the full Mule-vs-Apex decision matrix. Stripe qualifies because its webhook fans out to Salesforce + Slack + email in parallel via Scatter-Gather; HMAC in DataWeave is one line. The Apex Site webhooks (DocuSign, JIRA, SAP, WhatsApp) are direct because Mule would only add a hop without additional value, and — honestly — because the Apex `Crypto.generateMac('hmacSHA256', ...)` implementation with timing-safe compare has not yet been migrated.

### Hardening roadmap — TS-SEC-002

Migrate all Apex Site webhooks from plaintext shared-secret equality to `Crypto.generateMac('hmacSHA256', Blob.valueOf(payload), Blob.valueOf(secret))` with constant-time comparison and provider-specific signature headers (`X-Twilio-Signature`, `X-Jira-Webhook-Signature`, `X-SAP-Signature`, `X-DocuSign-Signature-1`). Estimated: 1–2 days including tests. Blockers: none — deferred to prioritize the demo E2E flow.

## Secret storage

| Secret | Where it lives | How to rotate |
|--------|----------------|---------------|
| JIRA API token | `Jira_Config__c` protected hierarchy Custom Setting | Setup → Custom Settings → Manage → Edit org defaults |
| Notion Internal Integration token | `Notion_Config__c` protected hierarchy Custom Setting | Same pattern |
| SAP API key | `SAP_Config__c` protected hierarchy Custom Setting | Same pattern |
| DocuSign OAuth | Named Credential `DocuSign` + Auth Provider (Consumer Key + Secret) | Setup → Auth Providers → DocuSign → Edit → re-authenticate |
| DocuSign eSign vendor account id | `ESignatureConfig` record `DocuSigneSignVendorAccountId` (ConfigValue) | Setup → Electronic Signature Configuration → Edit the record |
| Warehouse webhook shared secret | `Inventory_Integration_Config__mdt.Default.Shared_Secret__c` | **After deploy**: Setup → Custom Metadata Types → Inventory Integration Config → Default → Edit. The committed value is `REPLACE-IN-ORG-AFTER-DEPLOY` — the real secret is never stored in git. |
| Lexoffice API key | `Lexoffice_Config__c` protected Custom Setting | Set via `scripts/setup_lexoffice_config.apex` (gitignored) or Custom Settings UI |
| MuleSoft-side secrets (Stripe, Sendcloud, Slack, DACH finance) | `mulesoft/*.yaml` property files — **gitignored** (only `*.template` is committed) | Edit local property file → restart Mule app |

### Rotation procedure

1. Generate new token/secret at the external system (Atlassian, DocuSign, Stripe, etc.).
2. Update the **Salesforce** layer — either the Custom Setting default value or the Custom Metadata record (via Setup UI or `sf data update record`, never by editing the committed XML).
3. Update the **MuleSoft** local property file for the same integration.
4. Test end-to-end via Postman or `sf apex run` anonymous script.
5. Revoke the old token at the external system.
6. Document rotation date in the relevant memory file.

## Authorization model

- **Selector-pattern SOQL** uses `WITH USER_MODE` for FLS enforcement in read paths.
- **DML** is `Database.insert(records, allOrNone=false)` with partial-success handling; sharing enforcement is via record OWD + role hierarchy, not by permission-set bypass.
- **Guest User (SF Site)** webhooks are `without sharing` **only for the controller entry point**; the actual DML happens in a Platform Event subscriber that runs in system context (ADR-003 pattern) — the Guest profile never has direct write access to Contract/Order/Invoice.
- **Permission sets** follow least-privilege: no permission set grants `ViewAll` or `ModifyAll` on business objects. `Bundle_Component_Display_Access` is read-only despite the earlier full-CRUD grant (fixed). `Demo_Invoice_Access` grants CRUD but not sharing-bypass.

## What is intentionally NOT in scope for the demo

- Shield Platform Encryption (would encrypt data at rest — not required for the Dev Edition demo).
- MFA enforcement on integration users (Setup → Session Settings would enforce; deferred until a production tenant).
- Field-Level audit trail beyond standard `LastModifiedBy` / `CreatedBy` (History Tracking is enabled only on business-critical fields — `Order.Status`, `Contract.Status`, `Invoice.Stripe_Payment_Status__c`).
- IP allowlisting on the SF Sites hosting the webhooks (would be added in prod via Setup → Network Access + per-Site Restricted IP settings).

## Reporting a vulnerability

This is a portfolio demo, not a production tenant, but if you find a real issue that could affect a downstream user of this pattern please open a GitHub issue or contact the maintainer.

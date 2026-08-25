# TechnoStore — Integration Inventory

**9 external systems, 2 core platforms.** This document maps every integration to its
implementing code, its configuration storage, its architectural decision record, and —
most importantly — the **live evidence in the org** that proves it ran.

**Verification date**: 2026-08-20
**Org**: TechnoStore Developer Edition (`ORG-TS-DEMOEAK`)
**Method**: SOQL against business records, Tooling API against org configuration. Every
"Live evidence" row below is a query result, not a claim.

---

## Contents

- [The count: why 11, and what each one is](#the-count-why-11-and-what-each-one-is)
- [Live verification summary](#live-verification-summary)
- [Architecture: three integration paths](#architecture-three-integration-paths)
- [Per-system detail](#per-system-detail)
  - [1. Stripe](#1-stripe--payments)
  - [2. DocuSign](#2-docusign--e-signature)
  - [3. Sendcloud](#3-sendcloud--dach-logistics)
  - [4. JIRA](#4-jira--atlassian-issue-tracking)
  - [5. Slack](#5-slack--payment-and-warehouse-notifications)
  - [6. Notion](#6-notion--portfolio-publishing)
  - [7. SAP S/4HANA](#7-sap-s4hana--erp-7-phases)
  - [8. lexoffice](#8-lexoffice--german-sme-cloud-accounting)
  - [9. DATEV](#9-datev--steuerberater-csv-export)
  - [10. Twilio WhatsApp](#10-twilio-whatsapp--inbound-messaging)
  - [11. MuleSoft](#11-mulesoft--integration-middleware)
- [Cross-cutting integration substrate](#cross-cutting-integration-substrate)
- [Honest caveats](#honest-caveats)

---

## The count: why 11, and what each one is

The "11 systems" figure that appears in the demo narration breaks down as:

**2 core platforms** — the ones that run the business logic:

| # | Platform | Role |
|---|----------|------|
| 1 | **Salesforce** | System of engagement. Revenue Cloud (RLM) + Industries CPQ + CLM. Holds Quote → Order → Contract → Invoice. |
| 2 | **MuleSoft** | Integration middleware. Anypoint Studio project mediating three of the external systems. |

**9 external systems** — the ones Salesforce or Mule talks to:

| # | System | Domain | Direction |
|---|--------|--------|-----------|
| 3 | **Stripe** | Card payments | Outbound (Checkout) + Inbound (webhook) |
| 4 | **DocuSign** | E-signature | Outbound (envelope) + Inbound (Connect webhook) |
| 5 | **Sendcloud** | DACH parcel logistics | Outbound (v3 Orders API) |
| 6 | **JIRA** | Issue tracking | Outbound (create issue) + Inbound (status webhook) |
| 7 | **Slack** | Team notifications — 2 channels | Outbound (incoming webhooks) |
| 8 | **Notion** | Portfolio publishing | Outbound (pages API) |
| 9 | **SAP S/4HANA** | ERP | Outbound (5 OData services) + Inbound (Event Mesh CloudEvents) |
| 10 | **lexoffice** | German SME accounting | Outbound (REST) |
| 11 | **DATEV** | Steuerberater bookkeeping | File-based (CSV export, no API) |

**Not counted as systems**: Twilio WhatsApp is the transport for external messages —
counted within the 9 as its own inbound integration in most tellings; if you count it
separately the figure becomes 10 external. **Ngrok** is a development-time tunnel, not a
system — production would use CloudHub URLs or the Salesforce Site URL directly. Be
precise about this in interviews: inflating the count is the fastest way to lose credibility.

---

## Live verification summary

Every row below was queried against the live org on 2026-08-20.

| System | SF-side evidence | Result | Status |
|--------|-----------------|--------|--------|
| **Stripe** | `Invoice.Stripe_Payment_Status__c` populated | **3 of 4** invoices (`Paid`, `Sent`, `Not Started`) | ✅ Verified |
| **DocuSign** | `Contract.DocuSign_Envelope_Id__c` + Named Credential | **1** envelope (`00322c25-…`, Contract 00000310, Activated) | ✅ Verified |
| **Sendcloud** | `Service_Activation__c.Tracking_Number__c` | **2 of 2** activations carry tracking numbers | ✅ Verified |
| **JIRA** | `Order.JIRA_Ticket_Id__c` + Remote Site `JIRA_Cloud` | **3 of 9** orders have tickets | ✅ Verified |
| **Slack** | 2 Incoming Webhooks live (`#payments-team` since 29 Apr, `#warehouse`) | Messages arriving in both channels | ✅ Verified in Slack |
| **Notion** | Remote Site `Notion_API` + `Notion_Config__c` | Config present; 51 entries live in Notion workspace | ✅ Verified externally |
| **SAP** | `Webhook_Event__c` (Source=SAP) | **4** inbound CloudEvents, all `Processed` | ✅ Verified |
| | `Order.Status_In_SAP__c` | **9 of 9** orders stamped | ✅ Verified |
| | `Account.SAP_BP_Number__c` | **10 of 18** accounts synced | ✅ Verified |
| | `Product2.SAP_Material_Number__c` | **12 of 91** products synced | ✅ Verified |
| | `Invoice.Tax_Engine_Used__c` | `SAP_FALLBACK_TABLE` — fallback path proven | ✅ Verified |
| | `Invoice.SAP_Payment_Reference__c` | **3 of 4** reconciled from CAMT.053 | ✅ Verified |
| | `Integration_Error__c` (Source=SAP) | **10** logged failures — honest audit trail | ✅ Verified |
| **lexoffice** | `Invoice.Lexoffice_Status__c = 'Published'` | **3 of 4** invoices published | ✅ Verified |
| **DATEV** | `Account.DATEV_Debitor_Number__c` | **2 of 18** accounts allocated SKR04 Debitors | ✅ Verified |
| **WhatsApp** | `Webhook_Event__c` (Source=WhatsApp) | **6** inbound messages, all `Processed` | ✅ Verified |

### Org configuration (Tooling API)

**Remote Site Settings** — the outbound callout allowlist, 5 project-relevant entries:

| Site | Endpoint | Active |
|------|----------|--------|
| `JIRA_Cloud` | `https://maksu16.atlassian.net` | ✅ |
| `Lexoffice_API` | `https://api.lexoffice.io` | ✅ |
| `Notion_API` | `https://api.notion.com` | ✅ |
| `SAP_API_Hub` | `https://sandbox.api.sap.com` | ✅ |
| *(others)* | Vlocity/OmniStudio platform defaults | — |

**Named Credentials**: `DocuSign` → `https://demo.docusign.net` (PrincipalType: NamedUser).
The remaining four (`BillingSystemNC`, `LogisticsSystemNC`, `OrderFulfillmentSystemNC`,
`OrderFulfillmentSystemNCcanned`) are Salesforce DFO sample scaffolding, not TechnoStore
integrations.

**Deployed inbound REST endpoints** (custom, non-namespaced):

| Class | URL mapping | Source system |
|-------|-------------|---------------|
| `DocuSignConnectWebhook` | `/docusign/webhook/*` | DocuSign Connect |
| `JiraStatusWebhook` | `/jira/webhook/*` | JIRA Automation |
| `SapEventWebhook` | `/sap/event/*` | SAP Event Mesh |
| `WhatsAppWebhookRestService` | `/whatsapp/webhook/*` | Twilio |
| `InventoryCheckCallback` | `/inventory/callback/*` | MuleSoft (Slack decision) |
| `DatevExportRest` | `/datev/export/*` | *(outbound file, not inbound)* |

**Platform events** (4 custom, driving async decoupling):

| Event | Published by | Consumed by |
|-------|-------------|-------------|
| `Inventory_Check_Requested__e` | `InventoryCheckService` | MuleSoft → Slack |
| `Inventory_Status_Update__e` | `InventoryCheckCallback` (Site guest) | `InventoryStatusUpdateTrigger` → Order |
| `DocuSign_Status_Update__e` | `DocuSignConnectWebhook` (Site guest) | `DocuSignStatusUpdateTrigger` → Contract |
| `Order_Activated__e` | `OrderTriggerHandler.afterUpdate` | `OrderActivatedTrigger` → `SapSalesOrderService` |
| `Invoice_Payment_Requested__e` | `SendPaymentRemindersAction` | MuleSoft → Stripe Checkout |

---

## Architecture: three integration paths

Not every system is reached the same way. The choice was deliberate per system
(ADR-001 holds the Mule-vs-Apex decision matrix):

### Path A — Apex-direct callout

Salesforce Apex makes the HTTP request itself. Chosen when the call is
request/response, low-volume, and doesn't need retry/DLQ semantics.

**Systems**: DocuSign, JIRA, Notion, SAP (all 5 outbound services), lexoffice

```
Salesforce Apex ──HTTP──▶ External API
```

Verified by `setEndpoint()` calls in:
`DocuSignSendForSignatureService.cls:66`, `JiraTicketService.cls:111`,
`NotionPublishService.cls:235`, `LexofficeInvoiceService.cls:248`,
`SapMaterialStockService.cls:108`, `SapSalesOrderService.cls:86,174`,
`SapTaxCalculationService.cls:168`, `SapMaterialMasterSyncService.cls:74`,
`SapCustomerMasterSyncService.cls:79`.

### Path B — MuleSoft-mediated

Salesforce publishes a platform event; Mule subscribes, calls the external system,
and posts results back to a Salesforce REST endpoint. Chosen when the integration
needs retry, transformation, or fan-out — or when the vendor's API shape doesn't
map cleanly onto a single Apex callout.

**Systems**: Stripe, Sendcloud, Slack

```
Salesforce ──Platform Event──▶ MuleSoft ──HTTP──▶ External API
Salesforce ◀──REST callback── MuleSoft ◀──webhook──┘
```

Identified by absence of Apex: no class in the repo calls Stripe, Sendcloud, or Slack
endpoints, and their credentials live in `mulesoft/dev.yaml` (gitignored) rather than in
a Salesforce Custom Setting. That absence tells you **where** the call is made, not
whether it succeeds — for these three, delivery is observable in the destination system
(the Stripe dashboard, the Sendcloud panel, the Slack channel), and partly in Salesforce
via the results Mule writes back.

### Path C — File-based, no API

No network call at all. Data arrives as a file, or leaves as one.

**Systems**: DATEV (CSV export downstream), SAP Phase 4 (CAMT.053 bank statement upstream)

```
Bank ──CAMT.053 XML──▶ [Mule SFTP / manual upload] ──▶ Apex parser ──▶ Invoice
Invoice ──▶ Apex CSV generator ──▶ ContentVersion ──▶ Steuerberater's DATEV
```

This path exists because the source of truth is neither Salesforce nor the ERP —
it's the bank (CAMT.053) or the tax advisor's own system (DATEV). Neither publishes
a REST API that Salesforce could call.

---

## Per-system detail

### 1. Stripe — payments

**Path**: B (MuleSoft-mediated)
**ADRs**: ADR-013 (idempotency), ADR-015 (externalization), ADR-018 (SF vs SAP invoice)

| Aspect | Detail |
|--------|--------|
| **Outbound trigger** | `force-app-actions/main/default/classes/SendPaymentRemindersAction.cls` — `sendReminders()`, publishes `Invoice_Payment_Requested__e` |
| **Mule side** | Subscribes to the PE, creates a Stripe Checkout Session, writes the payment URL back |
| **Inbound** | Stripe webhook → Mule → Salesforce; marks `Invoice.Stripe_Payment_Status__c = 'Paid'` |
| **Downstream trigger** | `force-app-handlers/main/default/triggers/InvoiceTrigger.trigger` → `InvoiceTriggerHandler.cls` `afterUpdate` — Paid fires lexoffice publish |
| **Controllers** | `force-app-controllers/main/default/classes/InvoicePdfController.cls`, `RevenuePulseController.cls` |
| **LWC** | `force-app/main/default/lwc/paymentJourney/`, `force-app/main/default/lwc/revenuePulse/` |
| **Flows** | `Send_Stripe_Payment_Email`, `Generate_Payment_Link`, `Generate_Payment_Link_Invoice`, `Send_Invoice_Receipt_With_Pdf` |
| **Tests** | `force-app-tests/main/default/classes/SendPaymentRemindersActionTest.cls`, `GetRevenueSummaryActionTest.cls` |
| **Fields** | `Invoice.Stripe_Payment_Status__c`, `Stripe_Payment_URL__c`, `Stripe_Payment_Intent_Id__c` |
| **Credentials** | `mulesoft/dev.yaml` → `stripe.secret.key`, `stripe.webhook.secret` (gitignored) |

**Live evidence**: 3 of 4 invoices carry a Stripe status. One is `Paid` (payment
completed end-to-end), one `Sent` (link delivered, awaiting customer), one
`Not Started`.

---

### 2. DocuSign — e-signature

**Path**: A (Apex-direct, via Named Credential)
**ADRs**: ADR-008 (bidirectional design), ADR-017, ADR-003 (guest-user indirection), ADR-013

| Aspect | Detail |
|--------|--------|
| **Outbound** | `force-app-services/main/default/classes/DocuSignSendForSignatureService.cls` — `send(List<Request>)` (`@InvocableMethod`), endpoint `callout:DocuSign/restapi/v2.1/accounts/{id}/envelopes` |
| **Inbound** | `force-app-handlers/main/default/classes/DocuSignConnectWebhook.cls` — `urlMapping='/docusign/webhook/*'`, methods `handle()`, `healthCheck()` |
| **Guest-user indirection** | Webhook publishes `DocuSign_Status_Update__e`; `DocuSignStatusUpdateTrigger` → `DocuSignStatusUpdateTriggerHandler.cls` performs the Contract write under Automated Process user (ADR-003) |
| **Supporting** | `GenerateContractPdfService.cls`, `ContractPdfController.cls`, `DocumentRecipientTriggerHandler.cls` |
| **Flows** | `Send_Contract_Via_DocuSign`, `Send_Contract_For_Signature`, `Mark_Contract_As_Signed`, `Generate_Branded_Contract_Pdf`, `Auto_Generate_Contract_Pdf_On_Create` |
| **Tests** | `DocuSignSendForSignatureServiceTest.cls`, `DocuSignConnectWebhookTest.cls` |
| **Config** | Named Credential `DocuSign`; Auth Provider `DocuSign`; Site `DocuSign_Webhook` (label since renamed *TechnoStore Webhooks*); permset `DocuSign_Webhook_Access` |

**Live evidence**: Contract 00000310 carries envelope `00322c25-6728-8166-80ec-9491157d0580`
and reached status `Activated` — the full send → sign → webhook → status-update loop
completed.

> **Site naming note**: the Site's *label* was renamed to "TechnoStore Webhooks" when
> WhatsApp was added (Developer Edition blocks creating additional Sites). Its URL
> prefix remains `docusign`, so DocuSign Connect and Twilio both keep working. Side
> effect: `CreatedBy` on all webhook-created records reads
> "TechnoStore Webhooks Site Guest User".

---

### 3. Sendcloud — DACH logistics

**Path**: B (MuleSoft-mediated)
**ADRs**: ADR-001, ADR-013, ADR-015

| Aspect | Detail |
|--------|--------|
| **Outbound** | No Apex class — Mule calls `POST /api/v3/orders` with a bare-array payload, Basic Auth, `integration_id` |
| **Read/display** | `force-app-controllers/main/default/classes/RevenuePulseController.cls`; LWC `revenuePulse`, `paymentJourney` |
| **Idempotency** | `WebhookEventLogger.cls` — `Webhook_Event__c.Source__c` picklist includes `Sendcloud` |
| **Flows** | `Send_Shipping_Notification`, `Send_Combined_Notification`, `Schedule_Delivery_Flow` |
| **Fields** | `Service_Activation__c.Sendcloud_Parcel_Id__c`, `Sendcloud_Carrier__c`, `Tracking_Number__c`; `Invoice.Fulfillment_Type__c`, `Has_Physical__c` |
| **Credentials** | `mulesoft/dev.yaml` → `sendcloud.public.key`, `sendcloud.secret.key`, `sendcloud.integration.id` |

**Live evidence**: 2 of 2 `Service_Activation__c` records carry tracking numbers.
`Sendcloud_Parcel_Id__c` is null on both — v3 Orders API returns an order reference
rather than a v2 parcel id, and the field predates the v2→v3 migration.

> **API version history**: Sendcloud deprecated `POST /api/v2/parcels` for new accounts,
> returning 403 regardless of credentials. The working recipe is v3 Orders with a
> bare-array body and the numeric `integration_id`. This cost several days to diagnose —
> the v2 docs are still the first search result.

**Not Sendcloud**: `LogisticsSystemAdapter.cls`, `DeliveryTrackingService.cls`, and
`DFOApexMockService.cls` reference `callout:LogisticsSystemNC` — these are Salesforce
Dynamic Fulfillment Orders sample scaffolding, unrelated to the Sendcloud integration.

---

### 4. JIRA — Atlassian issue tracking

**Path**: A (Apex-direct) — plus a parallel Mule flow
**ADRs**: ADR-001, ADR-011 (bidirectional JIRA), ADR-013

| Aspect | Detail |
|--------|--------|
| **Outbound** | `force-app-services/main/default/classes/JiraTicketService.cls` — `createTicket(List<Request>)` (`@InvocableMethod`), `createTicketAsync(Id, String)` (`@future(callout=true)`); endpoint `https://{Host__c}/rest/api/2/issue` |
| **Inbound** | `force-app-handlers/main/default/classes/JiraStatusWebhook.cls` — `urlMapping='/jira/webhook/*'` |
| **Callers** | `InventoryApprovalDecisionService.cls` (`decide`), `InventoryCheckService.cls` (`requestCheck`) |
| **Tests** | `JiraTicketServiceTest.cls`, `JiraStatusWebhookTest.cls` |
| **Config** | Custom Setting `Jira_Config__c` (`Host__c`, `Email__c`, `API_Token__c`, `Project_Key__c`); Remote Site `JIRA_Cloud`; permset `Jira_Integration_Access` |
| **Field** | `Order.JIRA_Ticket_Id__c` |
| **Mule** | `mulesoft/inventory-jira-ticket-flow.xml`, `mulesoft/jira-integration-FULL.xml` |

**Live evidence**: Remote Site `JIRA_Cloud` → `https://maksu16.atlassian.net` active.
3 of 9 orders carry JIRA ticket ids.

**Two convergent paths to Order activation** (ADR-011): a warehouse approver either
clicks Approve on the Visualforce page, **or** moves the JIRA ticket to Done — the
webhook fires `Inventory_Status_Update__e` and the trigger flips
`Order.Status = 'Activated'`. Both routes end at the same state.

---

### 5. Slack — payment and warehouse notifications

**Path**: B (MuleSoft-mediated)
**ADRs**: ADR-019, ADR-011, ADR-020 (separation of duties), ADR-003

**Two channels are wired**, each fed by a different upstream trigger. This is the
project's oldest and most reliable integration — `#payments-team` predates the
warehouse flow, and the inventory-check setup guide describes itself as
*"same pattern as the existing payments-team flow"*.

| Channel | Upstream trigger | Mule flow | Payload |
|---------|-----------------|-----------|---------|
| **`#payments-team`** | Stripe Connect webhook (payment succeeded) → Mule HMAC verify → Scatter-Gather | `slack-payments-notify.xml` | Block Kit payment confirmation |
| **`#warehouse`** | Salesforce publishes `Inventory_Check_Requested__e` → Mule subscriber | `slack-warehouse-notify.xml` (repo snippet: `inventory-check-flow-snippet.xml`) | Block Kit stock request + Visualforce deep link |

| Aspect | Detail |
|--------|--------|
| **Outbound** | No Apex — Mule posts to `${slack.payments.webhook.path}` and `${slack.warehouse.webhook.path}` via `Slack_HTTP_Config` |
| **Trigger (warehouse)** | `force-app-actions/main/default/classes/InventoryCheckService.cls` — `requestCheck()` publishes `Inventory_Check_Requested__e` |
| **Trigger (payments)** | Stripe webhook → Mule scatter-gather: Salesforce Invoice update **+** Slack post **+** receipt email, in parallel |
| **Inbound (via Mule)** | `force-app-handlers/main/default/classes/InventoryCheckCallback.cls` — `urlMapping='/inventory/callback/*'` |
| **Guest-user indirection** | Callback publishes `Inventory_Status_Update__e`; `InventoryStatusUpdateTrigger` → `InventoryStatusUpdateTriggerHandler.cls` `handleAfterInsert` writes the Order |
| **Decision surface** | `force-app-controllers/main/default/classes/WarehouseInventoryApprovalController.cls` (Visualforce, ADR-020) |
| **Flows** | `Request_Inventory_Check`, `Mark_Order_In_Stock`, `Mark_Order_Out_Of_Stock` |
| **Config** | `Inventory_Integration_Config__mdt.Default` (`Shared_Secret__c`, `Mule_Endpoint_Url__c`); permsets `Inventory_Webhook_Access`, `Inventory_Field_Access` |
| **Credentials** | `mulesoft/dev.yaml` → `slack.warehouse.webhook.path`, `slack.payments.webhook.path` (gitignored). The channel-scoped webhook URL *is* the credential — no token, no OAuth |
| **Postman** | `postman/TechnoStore.postman_collection.json` § 7 — "Post to #payments-team", "Post to #warehouse" |
| **Mule** | `mulesoft/inventory-check-flow-snippet.xml`, `mulesoft/INVENTORY_CHECK_SETUP.md` |

**Live evidence**: both channels have an active Slack **Incoming Webhook** installed —
`#payments-team` since 29 April 2026 — and messages arrive in both. Verification for
this integration lives **in the Slack workspace**, which is the correct place: Slack is
the destination, so Slack is where delivery is observable.

> **Where the Salesforce-side field stands**: `Order.Inventory_Slack_Message_Ts__c` is
> null on all 9 orders. This field was designed to store Slack's returned message
> timestamp so a later Salesforce action could thread a reply onto the original message.
> The current Mule flow posts fire-and-forget and discards the response, so the field
> never gets populated. **This is an unfinished nice-to-have, not a broken integration** —
> the messages themselves deliver fine. Capturing `ts` from the Slack response in the
> Mule flow is a ~10-minute change if threading is ever needed.

> **Why the Mule flows aren't in the repo**: `slack-payments-notify.xml` and
> `slack-warehouse-notify.xml` live in the Anypoint Studio project, not in this Git
> repo — `docs/SOLUTION_BLUEPRINT.md` § 6 marks both as "not committed". The repo carries
> `inventory-check-flow-snippet.xml` as the representative example. Committing the full
> Mule project is a known follow-up.

> **Other channels in the workspace**: the TechnoStore Slack workspace contains several
> channels beyond these two (`#daily-standup`, `#general`, `#random`, `#leads-…`,
> `#support-…`). Only `#payments-team` and `#warehouse` are targeted by TechnoStore code
> and configuration — verified across `mulesoft/dev.yaml.template`,
> `docs/SOLUTION_BLUEPRINT.md` § 3, and the Postman collection, all of which list exactly
> these two. If `#daily-standup` is receiving automated messages, the sender is most
> likely **Atlassian's native JIRA-for-Slack app** (configured inside Slack/JIRA, not in
> this codebase) rather than a TechnoStore Mule flow. Worth confirming from that
> channel's message sender before describing it as a TechnoStore integration.

---

### 6. Notion — portfolio publishing

**Path**: A (Apex-direct)
**ADR**: ADR-010 (superseded by the flat-heading refactor; supersession note in the ADR)

| Aspect | Detail |
|--------|--------|
| **Outbound** | `force-app-services/main/default/classes/NotionPublishService.cls` — `publish(StarEntry)`, `publishEnterprise(EnterpriseEntry)`; endpoint `https://api.notion.com/v1/pages` |
| **Tests** | `NotionPublishServiceTest.cls` |
| **Config** | Custom Setting `Notion_Config__c` (`Token__c`, `Parent_Page_Id__c`); Remote Site `Notion_API`; permset `Notion_Publisher_Access` |
| **Scripts** | 23 batch scripts: `scripts/notion_publish_batch_*.apex`, `scripts/notion_enterprise_batch_*.apex` |

**Live evidence**: Remote Site `Notion_API` active; `Notion_Config__c` populated.
51 STAR-format portfolio entries live in the Notion workspace (external verification).

**Refactor note**: the original design nested 3 levels of toggles per entry, costing
6 API calls and ~25 minutes to republish all entries. The flat-heading redesign
dropped it to 1 call per entry and ~5 minutes.

---

### 7. SAP S/4HANA — ERP (7 phases)

**Path**: A (Apex-direct) for phases 1/2/3/5/6, C (file-based) for phase 4,
inbound webhook for phase 7
**ADRs**: ADR-022 through ADR-029

| Phase | Showcase | Class | Key method | ADR |
|-------|----------|-------|-----------|-----|
| 1 | ATP inventory check | `SapMaterialStockService.cls` | `checkOrderStock` | ADR-022 |
| 2 | Sales order acknowledgment | `SapSalesOrderService.cls` | `pushOrders`, `publishToSapAsync` | ADR-023 |
| 3 | Tax determination | `SapTaxCalculationService.cls` | `calculateForInvoice` | ADR-024 |
| 4 | CAMT.053 payment reconciliation | `SapPaymentReconciliationService.cls` | `reconcile` | ADR-025 |
| 5 | Material master sync | `SapMaterialMasterSyncService.cls` | `sync` | ADR-026 |
| 6 | Customer master sync | `SapCustomerMasterSyncService.cls` | `sync` | ADR-027 |
| 7 | Event Mesh inbound (CloudEvents) | `SapEventWebhook.cls` + `SapInboundEventDispatcher.cls` | `handle()`, `dispatch(CloudEvent)` | ADR-028 |

All outbound services live under `force-app-services/main/default/classes/`.
Phase 7's webhook lives under `force-app-handlers/main/default/classes/`.

| Aspect | Detail |
|--------|--------|
| **Async decoupling** | `OrderTriggerHandler.cls` publishes `Order_Activated__e`; `OrderActivatedTrigger.trigger` consumes it and calls `SapSalesOrderService.pushOrders` — lets the activation transaction commit before the callout (avoids "uncommitted work pending") |
| **Tax adapter** | `TechnoStoreTaxEngineAdapter.cls` (ADR-009) — native `commercetax` adapter on line items, SAP API on the header |
| **Tests** | One test class per service, all under `force-app-tests/main/default/classes/` |
| **Config** | Custom Setting `SAP_Config__c` (`API_Base_URL__c`, `API_Key__c`); Remote Site `SAP_API_Hub`; permset `SAP_Integration_Access` |
| **Mule** | `mulesoft/sap-integration-FULL.xml` (flow `sap-test-businesspartner-query`, path `/sap/test/bp`), `mulesoft/SAP_INTEGRATION_SETUP.md` |

**Live evidence** — the richest audit trail of any system:

| Signal | Value | What it proves |
|--------|-------|----------------|
| `Webhook_Event__c` (Source=SAP) | 4 rows, all `Processed` | Phase 7 inbound dispatch ran, idempotency recorded |
| `Order.Status_In_SAP__c` | 9 of 9 stamped | Phase 2 attempted on every order |
| `Account.SAP_BP_Number__c` | 10 of 18 | Phase 6 customer master sync ran |
| `Product2.SAP_Material_Number__c` | 12 of 91 | Phase 5 material master sync ran |
| `Product2.SAP_Last_Synced_At__c` | 9 stamped | Phase 5 write-back confirmed |
| `Order.SAP_Available_Quantity__c` | 2 populated | Phase 1 ATP returned quantities |
| `Invoice.Tax_Engine_Used__c` | `SAP_FALLBACK_TABLE` | Phase 3 fallback path exercised — SAP tax module license-gated, country table took over |
| `Invoice.SAP_Payment_Reference__c` | 3 of 4 | Phase 4 CAMT.053 matched and stamped |
| `Invoice.Payment_Method__c` | `Bank_Transfer` on 3 | Phase 4 wrote the DACH payment channel |
| `Integration_Error__c` (Source=SAP) | 10 rows | Failures logged, not swallowed |

**Sandbox honesty** — `Order.Status_In_SAP__c` reads `Push Failed` on 5 orders. This is
correct and expected: the SAP API Hub Sandbox is read-mostly and returns
`405 OPERATION_NOT_SUPPORTED` on writes, with SAP's own message *"the 'Try-it-out'
feature is only supported for GET operations. To test a write operation, please test
the API against your own SAP S/4HANA Cloud system."* The code path, the CSRF token
handshake, and the payload are production-correct; only the endpoint changes.

**Not implemented**: Phase 8 (Invoice posting to SAP FI) — documented in ADR-018 as a
~4-6 week production migration, not attempted here.

---

### 8. lexoffice — German SME cloud accounting

**Path**: A (Apex-direct)
**ADR**: ADR-030

| Aspect | Detail |
|--------|--------|
| **Outbound** | `force-app-services/main/default/classes/LexofficeInvoiceService.cls` — `publish(List<Request>)` (`@InvocableMethod`), `publishFromButton(Id)`, `publishAsync(Set<Id>)` (`@future(callout=true)`) |
| **Trigger** | `force-app-handlers/main/default/triggers/InvoiceTrigger.trigger` → `InvoiceTriggerHandler.cls` `afterUpdate`: `Stripe_Payment_Status__c → 'Paid'` fires `publishAsync` |
| **Idempotency** | Only fires when `Lexoffice_Status__c != 'Published'` |
| **LWC** | `force-app/main/default/lwc/invoiceFinanceActions/` |
| **Tests** | `LexofficeInvoiceServiceTest.cls` |
| **Config** | Protected Custom Setting `Lexoffice_Config__c` (`API_Key__c`, `API_Base_URL__c`); Remote Site `Lexoffice_API` |
| **Fields** | `Invoice.Lexoffice_Invoice_Id__c`, `Lexoffice_Status__c`, `Lexoffice_Published_At__c` |

**Live evidence**: 3 of 4 invoices show `Lexoffice_Status__c = 'Published'`. The
integration is **event-driven, not a button** — payment triggers publication with no
human click.

> **`@future` requirement**: `publishFromButton` performs a DML update then a callout
> in the same transaction, which throws "uncommitted work pending". `publishAsync`
> exists precisely to force the implicit commit before the callout. Use the async
> method for testing.

**Tax handling**: line items use `InvoiceLine.GrossUnitPrice` with `taxType="gross"` and
19% German VAT.

---

### 9. DATEV — Steuerberater CSV export

**Path**: C (file-based, no API)
**ADR**: ADR-031

| Aspect | Detail |
|--------|--------|
| **Service** | `force-app-services/main/default/classes/DatevExportService.cls` — `export(List<Request>)` (`@InvocableMethod`), `exportFromButton(Id)`, `generateCsv(Id)` |
| **REST** | `force-app-handlers/main/default/classes/DatevExportRest.cls` — `urlMapping='/datev/export/*'`, `doGet()`, `doPost()` |
| **LWC** | `force-app/main/default/lwc/invoiceFinanceActions/` — "Export DATEV Buchungsstapel (CSV)" button |
| **Tests** | `DatevExportServiceTest.cls` |
| **Field** | `Account.DATEV_Debitor_Number__c` (SKR04 Debitor, auto-allocated from 10001) |

**Live evidence**: 2 of 18 accounts carry allocated SKR04 Debitor numbers.

**Why file, not API** — this is a business constraint, not a technical shortcut:
opening a DATEV-Konto requires a 16-digit invitation code issued only to existing
customers or Steuerberater, and the DATEVconnect Online API requires partner
registration. The standard path for a company in this position is to generate a
DATEV-konform CSV and hand it to the tax advisor, who imports it into their own DATEV
instance. No DATEV account dependency.

**DACH format details handled**:
- Chart of accounts SKR04, revenue account 4400 (*Erlöse 19% USt*)
- German comma decimal separator (`1449,00` not `1449.00`)
- Belegdatum in DDMM format
- **UTF-8 BOM** (`EF BB BF`) prepended so Excel and DATEV render umlauts correctly —
  built via `EncodingUtil` hex concatenation because Apex `Blob` has no concat method
- `@AuraEnabled` on the Result class (not just `@InvocableVariable`) so the LWC can read it

---

### 10. Twilio WhatsApp — inbound messaging

**Path**: Inbound webhook (public Site)
**ADRs**: ADR-013 (idempotency), ADR-003 (guest user)

| Aspect | Detail |
|--------|--------|
| **Inbound** | `force-app-handlers/main/default/classes/WhatsAppWebhookRestService.cls` — `urlMapping='/whatsapp/webhook/*'`, `handleIncomingMessage()`, `healthCheck()` |
| **Auth** | `?secret=` query param against `Inventory_Integration_Config__mdt.Default.Shared_Secret__c` |
| **Idempotency** | Twilio `MessageSid` as `Webhook_Event__c.External_Id__c` |
| **Behavior** | Regex-extracts an email address from message text → `Lead.Email`; `From` → `Lead.Phone`; `LeadSource='WhatsApp'`; message body → `Lead.Description`; replies with TwiML |
| **Tests** | `WhatsAppWebhookRestServiceTest.cls` |
| **Scripts** | `scripts/test_whatsapp_internals.apex`, `scripts/test_whatsapp_lead_insert.apex` |

**Live evidence**: 6 `Webhook_Event__c` rows with `Source__c = 'WhatsApp'`, all
`Processed`. Message SIDs range from test payloads (`SMtest67890`) to real Twilio SIDs
(`SM9cee40fb…`, `SMf5f04d37…`) — the latter are genuine WhatsApp messages from a real
phone. The Lead records they created were deleted during demo preparation; the webhook
event log is the surviving proof.

> **Body-parse gotcha**: Twilio posts `application/x-www-form-urlencoded`. On a
> Salesforce Site that content lands in `RestRequest.params` and `requestBody` arrives
> empty. The class merges `req.params` with a raw-body parse so it works both through
> the public Site and via authenticated REST.

> **Labeling honesty**: this is a webhook/API integration, **not** "Salesforce Headless
> Identity". Describe it accurately in posts and interviews.

**Production hardening needed**: verified WhatsApp Business number (Meta approval),
`X-Twilio-Signature` HMAC validation, and GDPR consent capture. The Apex is unchanged.

---

### 11. MuleSoft — integration middleware

**Role**: Core platform (not an external system)
**ADRs**: ADR-001 (Mule-vs-Apex decision matrix), ADR-006 (Anypoint Studio setup)

| File | Contents |
|------|----------|
| `mulesoft/inventory-check-flow-snippet.xml` | Flow `inventory-check-flow` — PE subscriber → Slack `#warehouse` |
| `mulesoft/inventory-jira-ticket-flow.xml` | Flow `inventory-jira-ticket-flow` — creates JIRA issue on rejection |
| `mulesoft/jira-integration-FULL.xml` | Complete JIRA flow |
| `mulesoft/sap-integration-FULL.xml` | Flow `sap-test-businesspartner-query`, HTTP path `/sap/test/bp` |
| `mulesoft/dev.yaml.template` | Property template — Salesforce, JIRA, SAP, Stripe, Sendcloud, Slack credentials |
| `mulesoft/jira-properties.yaml.template` | JIRA-only property template |
| `mulesoft/INVENTORY_CHECK_SETUP.md` | Setup runbook |
| `mulesoft/SAP_INTEGRATION_SETUP.md` | Setup runbook |

**Contracts**: `openapi/technostore-mule.yaml` (HTTP listener specs),
`postman/TechnoStore.postman_collection.json`.

**Secret hygiene verified**: `mulesoft/jira-properties.yaml` (the real file, with a live
token) is matched by `.gitignore:92` (`**/jira-properties.yaml`) and confirmed untracked
by git. Only `.template` files are committed.

**Deferred**: `sap-integration-FULL.xml` currently holds only the Business-Partner query
test flow. All five SAP outbound services are Apex-direct today. A production Mule layer
would wrap each SAP call in retry / DLQ / idempotency per ADR-001 and ADR-013. The Apex
contract stays identical; only the URL changes from SAP-direct to Mule-as-proxy.
Estimated 2-3 hours of flow building.

---

## Cross-cutting integration substrate

Three components are shared by every integration. They're the reason the demo has one
observability story instead of nine.

### Idempotency — `WebhookEventLogger`

`force-app-services/main/default/classes/WebhookEventLogger.cls`
Methods: `checkAndRecord(externalId, source, eventType, payload)`, `markProcessed(row, detail)`, `markFailed(row, detail)`
Object: `Webhook_Event__c` with a uniqueness constraint on `External_Id__c`

Every inbound webhook calls `checkAndRecord` first. A replay of the same external id
returns `isDuplicate = true` and the handler short-circuits with 200 rather than
re-processing. This matters because SAP Event Mesh, Stripe, and Twilio all deliver
**at-least-once** — duplicates are normal traffic, not errors.

**Live**: 10 rows across SAP (4) and WhatsApp (6), all `Processed`.
ADR-013.

### Error audit — `IntegrationErrorLogger`

`force-app-services/main/default/classes/IntegrationErrorLogger.cls`
Methods: `log(source, operation, exception, payload, correlationId)`, `logHttpFailure(...)`, `newCorrelationId()`
Object: `Integration_Error__c`

Failures land here rather than in a swallowed catch block, and the Integration Health
dashboard reads from it. A correlation id threads a single logical operation across
multiple log rows.

**Live**: 10 rows, all `Source_System__c = 'SAP'` — the honest record of sandbox write
rejections.

> **Known gap**: `Integration_Error__c.Source_System__c` is a restricted picklist that
> does not yet include `lexoffice`, so lexoffice failures can't be logged there. Small
> fix; noted here rather than hidden.

### Trigger framework — `TriggerHandler`

`force-app-handlers/main/default/classes/TriggerHandler.cls` — Kevin O'Hara's framework.
One trigger per sObject delegating to a handler class, with framework-level bypass
(`TriggerHandler.bypass('OrderTriggerHandler')`). ADR-005.

Subclasses: `OrderTriggerHandler`, `InvoiceTriggerHandler`, `DocuSignStatusUpdateTriggerHandler`,
`InventoryStatusUpdateTriggerHandler`, `DocumentRecipientTriggerHandler`.

### Guest-user indirection pattern — ADR-003

Public webhooks run as the Site Guest User, which should not hold write access to
business objects. The pattern: the webhook validates and publishes a **platform event**;
a trigger on that event performs the business write under the Automated Process user.

Applied by: `DocuSignConnectWebhook` (→ `DocuSign_Status_Update__e`),
`InventoryCheckCallback` (→ `Inventory_Status_Update__e`).

**Deliberate deviation**: `SapEventWebhook` dispatches **inline** with `without sharing`
rather than via a platform event. Reason: this Developer Edition org has hit the
200-sObject cap and platform events count against it — creating `SAP_Inbound_Event__e`
returned "reached maximum number of custom objects". ADR-028 documents this trade-off
and the 15-minute refactor to restore the pattern in a production org.

---

## Honest caveats

These belong in any interview conversation about this project. Volunteering them is
what separates a demo from a claim.

1. **Developer Edition, not production.** No production traffic has ever run through
   this system. Say "demo verified" or "local end-to-end test", never "in production".

2. **SAP sandbox is read-mostly.** Phases 2 and 3 return `405 OPERATION_NOT_SUPPORTED`
   on writes — SAP's own message says to use a licensed S/4HANA Cloud tenant. The code
   path is production-correct; only the base URL changes. `Order.Status_In_SAP__c =
   'Push Failed'` on 5 orders is this limitation showing honestly rather than being
   hidden.

3. **SAP Event Mesh is simulated.** Event Mesh is a BTP-only service not available in
   the trial. Phase 7 CloudEvents are injected by Postman or anonymous Apex against the
   real webhook. The receiver, dispatcher, idempotency, and routing are
   production-ready; the publisher is not connected.

4. **Stripe runs in test mode.** No real card has been charged.

5. **DATEV has no API connection.** The CSV is generated and DATEV-konform, but nothing
   is transmitted to DATEV. This is the standard path for a company without a
   DATEV-Konto, not a workaround.

6. **Slack works; its proof lives in Slack.** Both `#payments-team` and `#warehouse`
   have active Incoming Webhooks and receive messages. `Order.Inventory_Slack_Message_Ts__c`
   is unpopulated because the Mule flow discards Slack's response — that field was for
   future message threading, and its emptiness says nothing about delivery. The Mule
   flow files themselves are in the Anypoint project rather than this repo.

7. **Sendcloud parcel ids are absent.** The v3 Orders API returns an order reference
   rather than a v2 parcel id; `Sendcloud_Parcel_Id__c` predates that migration.

8. **Phase 8 (SAP FI invoice posting) is not built.** ADR-018 scopes it at 4-6 weeks.

9. **Mule wraps only two integrations today.** `sap-integration-FULL.xml` holds one test
   flow. The Mule-vs-Apex matrix in ADR-001 describes the target state, not the current
   one.

10. **Copado is not in use.** `docs/copado-integration-plan.md` is a migration path for
    production scaling, not experience. Do not claim Copado hands-on.

---

## Related documentation

| Document | Purpose |
|----------|---------|
| `docs/adr/` | 31 Architecture Decision Records (contiguous ADR-001 … ADR-031) |
| `docs/SOLUTION_BLUEPRINT.md` | arc42-format architect briefing (626 lines) |
| `docs/architecture/` | 5 Mermaid diagrams — Context, Container, Q2C Sequence, Data Model, CI/CD |
| `openapi/technostore-webhooks.yaml` | OpenAPI 3.0.3 spec for the Salesforce Site endpoints |
| `openapi/technostore-mule.yaml` | OpenAPI 3.0.3 spec for the Mule HTTP listeners |
| `postman/TechnoStore-SAP-Demo.postman_collection.json` | 7-phase SAP walkthrough, recruiter-reproducible |
| `postman/TechnoStore.postman_collection.json` | 17 requests across JIRA / Notion / DocuSign / Stripe / Sendcloud / Slack / SF |
| `CLAUDE.md` | Project guide, credential rotation procedure, architectural patterns |

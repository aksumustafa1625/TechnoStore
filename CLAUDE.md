# TechnoStore — Claude Code Project Guide

B2B electronics Quote-to-Cash demo on Salesforce Industries CPQ + Revenue Cloud + CLM, orchestrated with MuleSoft across 7 external systems. DACH-market specifics: 19% VAT, DHL preference, DE/AT/CH address handling.

## Repository layout

6-package SFDX:
- `force-app/` — root metadata (objects, flows, layouts, sites, approval processes)
- `force-app-controllers/` — VF controllers, LWC controllers
- `force-app-services/` — service classes (Stripe, DocuSign, Sendcloud, JIRA, Slack, Notion, SAP)
- `force-app-handlers/` — Kevin O'Hara TriggerHandler subclasses + REST webhooks
- `force-app-actions/` — invocable Apex (Flow-callable services)
- `force-app-tests/` — Apex test classes
- `mulesoft/` — Anypoint Studio integration project + property snippets
- `interview-prep/` — DACH market interview Q&A pack (228 questions, 7 clusters)

## Common commands

```powershell
# Deploy a single class
sf project deploy start --source-dir force-app-services/main/default/classes/JiraTicketService.cls

# Deploy with test classes
sf project deploy start --source-dir force-app-services --test-level RunLocalTests

# Run an anonymous Apex script
sf apex run --file scripts/test_asset_on_order_activation.apex

# Check deploy status by job id
sf project deploy report --job-id <id>
```

## Credential rotation

Secrets live in **two layers**:

| Layer | Where | How to update |
|-------|-------|---------------|
| Salesforce | Org-level Custom Settings (`Jira_Config__c`, `Email_Config__c`, `SAP_Config__c`, `Notion_Config__c`) | Setup → Custom Settings → Manage → Edit org defaults |
| MuleSoft | `mulesoft/*.yaml` property files (NOT committed — see `.gitignore`) | Edit local file → restart Mule app in Anypoint Studio |

**Rotation procedure** (when an API token expires or is compromised):

1. Generate new token in the external system (Atlassian, DocuSign, etc.)
2. Update **Salesforce** Custom Setting → org default → API_Token field
3. Update **Mule** local property file (`mulesoft/<service>-properties.yaml`) — never paste tokens in chat or PR descriptions
4. Test the integration end-to-end (anonymous Apex `Execute Anonymous` is fastest)
5. Revoke old token in the external system
6. Update the relevant memory file with the rotation date

**Files that may contain real secrets (all gitignored)**:
- `mulesoft/jira-properties.yaml`
- `mulesoft/dev.yaml`
- `org_info.json`, `.tmp/`

Always pair-check `.gitignore` before adding a new credential file. Templates (`*.template`) are safe to commit — they have placeholders only.

## Key architectural patterns

- **Apex triggers**: Kevin O'Hara TriggerHandler base — one trigger per sObject delegating to a Handler class with framework-level bypass support (`TriggerHandler.bypass('OrderTriggerHandler')`)
- **Webhooks**: Public via Salesforce Sites + Guest User + Platform Event indirection (ADR-003). Apex REST `@RestResource` classes never use `without sharing` on user-facing logic
- **Async after DML**: Approval.process() does DML — subsequent callouts must use `@future(callout=true)` or Queueable, otherwise "uncommitted work pending" error
- **Two-stage PDF generation**: pre-payment branded invoice (orange) + payment link email → post-payment receipt (green) + branded notification email
- **Asset creation**: Pattern 1 (transactional, on Order Activation) — appropriate for one-time hardware

## What NOT to do

- Don't commit `.yaml` files in `mulesoft/` (except `.template`)
- Don't paste secrets in chat — instruct the user to update the Custom Setting / property file directly
- Don't use `without sharing` on Apex unless guarding a public webhook endpoint
- Don't add a synchronous callout immediately after `Approval.process()` or any DML
- Don't claim production traffic in interview narrative — say "demo verified" or "local end-to-end test"

## Active checkpoint — SAP Integration Sprint

**Status as of 2026-05-18 ~14:30**: ADR catalogue is contiguous 001-021, no gaps. Webhook idempotency + Integration_Error__c + Integration Health dashboard are live in the org and pushed to origin/main. Multi-tier discount approval + branded email response are live.

**Reviewer's 28-item enterprise-realism critique**: 4 high-ROI items implemented in code, 6 mid-priority items documented as ADRs (016-021), 5 SAP items deferred to the SAP sprint (this section), 3 reviewer-overstatement items rejected with prepared defenses.

**SAP-related artifacts already in the repo** (from earlier sessions, no end-to-end demo flow yet):
- `force-app/main/default/objects/SAP_Config__c/` — Custom Setting (API_Base_URL__c, API_Key__c). Populated in org.
- `force-app/main/default/permissionsets/SAP_Integration_Access.permissionset-meta.xml`
- `force-app/main/default/remoteSiteSettings/SAP_API_Hub.remoteSite-meta.xml` — allows callouts to `sandbox.api.sap.com`.
- `mulesoft/sap-integration-FULL.xml` — 134-line file with one working flow (`sap-test-businesspartner-query`). Has `Accept-Encoding: identity` fix on line 38-39 for the SAP API Hub gzip quirk.

**Nothing else exists yet**: no Apex SAP service classes, no SAP custom fields on Order, no `Order_Activated__e` platform event, no ATP check wiring, no Material Master sync, no payment reconciliation.

**Tonight's plan** (2 of 5 SAP showcases, ~3-3.5 hours):

| Phase | Showcase | SAP Endpoint | Files to add | ADR |
|-------|----------|--------------|--------------|-----|
| 1 (1-1.5h) | ATP Check at inventory request | `API_MATERIAL_STOCK_SRV` GET | `SapMaterialStockService.cls`, `Order.SAP_Available_Quantity__c`, `Product2.SAP_Material_Number__c`, new Mule flow `sap-material-stock-query`, update `InventoryCheckService` | ADR-022 |
| 2 (1-1.5h) | Sales Order Acknowledgment | `API_SALES_ORDER_SRV` POST | `Order_Activated__e` platform event, `Order.SAP_Sales_Order_Number__c`, `Order.Status_In_SAP__c`, update `OrderTriggerHandler.afterUpdate`, new Mule flow `sap-sales-order-create` | ADR-023 |
| 3 (30 min) | ADR-022 + ADR-023 + commit + push | — | — | — |

Hybrid pattern for Phase 1 — "SAP-first, JIRA-fallback": SAP MM provides the real stock query; if SAP says insufficient, existing JIRA-out-of-stock approval flow takes over. JIRA stays as the replenishment task tracker (per ADR-019 reviewer-overstatement defense).

**Deferred to later sub-sprints** (Sprint 68 remainder): Tax determination via SAP, CAMT.053 payment reconciliation, Material Master nightly sync. Estimated ~5-7 hours total across two evenings.

**Pre-flight checks before resuming the sprint** (~10 min):
1. Setup → Custom Settings → SAP_Config → Org Defaults — verify API_Base_URL__c + API_Key__c populated; regenerate at developer.sap.com if expired.
2. Local `mulesoft/dev.yaml` — verify `sap.host` + `sap.api.key` present.
3. Open Anypoint Studio, load `technostore-integration` Mule app, click Run. Mule boots on port 8082.
4. POST `http://localhost:8082/sap/test/bp` with no body → expect 200 + 5 BP records in JSON.
5. If 401/403, rotate SAP key. If gzip errors, verify line 38-39 of `sap-integration-FULL.xml` still has `Accept-Encoding: identity`.

**Resumption pointer**: full detail in `[memory] sap_integration_sprint_checkpoint.md`. Open that file first when resuming — it has the exact file-creation list and end-of-night verification checklist.

## Memory

User has persistent memory at `C:\Users\DELL\.claude\projects\c--Users-DELL-Documents-Projects-TechnoStore\memory\`. Key files indexed in `MEMORY.md`. Update memory after significant decisions; don't duplicate code-derivable facts.

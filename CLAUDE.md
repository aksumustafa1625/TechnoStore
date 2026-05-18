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

## SAP Integration Sprint — COMPLETE (2026-05-18 ~20:45)

All 6 SAP showcases shipped in a single Saturday session — 5 from the reviewer's enterprise-realism critique plus the Customer Master Sync sibling from the broader 8-phase vision. ADR catalogue is now contiguous 001-027, no gaps. Webhook idempotency + Integration_Error__c + Integration Health dashboard are live. Multi-tier discount approval + branded email response + tier-aware UX are live.

### What's in the org

| Phase | Showcase | SAP Endpoint | Service | New Fields | ADR | Commit |
|-------|----------|--------------|---------|------------|-----|--------|
| 1 | ATP Check at inventory request | `API_MATERIAL_STOCK_SRV` GET | `SapMaterialStockService` | `Product2.SAP_Material_Number__c`, `Order.SAP_Available_Quantity__c`, `Order.SAP_Inventory_Checked_At__c` | ADR-022 | `dff1e4e` |
| 2 | Sales Order Acknowledgment | `API_SALES_ORDER_SRV` POST | `SapSalesOrderService` (async via `Order_Activated__e` platform event) | `Order.SAP_Sales_Order_Number__c`, `Order.Status_In_SAP__c` | ADR-023 | `f3ac852` |
| 3 | Tax Determination | `API_DETERMINE_TAX_SRV` (license-gated in sandbox) | `SapTaxCalculationService` (try SAP → country fallback table) | `Invoice.SAP_Tax_Amount__c`, `Invoice.SAP_Tax_Rate__c`, `Invoice.SAP_Tax_Calculated_At__c`, `Invoice.Tax_Engine_Used__c` | ADR-024 | `650f9b8` |
| 4 | Payment Reconciliation | CAMT.053 XML parser (ISO 20022) | `SapPaymentReconciliationService` | `Invoice.Payment_Method__c`, `Invoice.SAP_Payment_Reference__c`, `Invoice.SAP_Payment_Posted_At__c` | ADR-025 | `288a95a` |
| 5 | Material Master Sync | `API_PRODUCT_SRV` GET | `SapMaterialMasterSyncService` (upsert by SAP_Material_Number__c) | `Product2.SAP_Last_Synced_At__c`, `Product2.SAP_Product_Description__c` | ADR-026 | `71fdd0d` |
| 6 | Customer Master Sync | `API_BUSINESS_PARTNER` GET | `SapCustomerMasterSyncService` (upsert by SAP_BP_Number__c) | `Account.SAP_BP_Number__c`, `Account.SAP_Customer_Category__c`, `Account.SAP_Customer_Group__c`, `Account.SAP_Last_Synced_At__c` | ADR-027 | `4af5584` |

### Hybrid + transparency patterns shared across all 5

- **SAP-first / SF-fallback** — Phase 1 (SAP MM → warehouse approval), Phase 3 (SAP tax → country table). Same shape. When SAP available, SAP authoritative; when sandbox license-gates or returns nothing, transparent fallback with the engine path captured in audit fields.
- **Platform event indirection** — Phase 2 (Order_Activated__e). Lets the outbound SAP push run in a fresh async context after the activation transaction commits. Mirrors ADR-003's inbound-webhook pattern for outbound use.
- **Same SAP credentials everywhere** — `SAP_Config__c` org-default Custom Setting holds API_Base_URL__c + API_Key__c; every service reads from there. Mule (when Mule joins) reads from `dev.yaml` (gitignored). Token rotation per ADR-???: credential rotation procedure.

### Demo storyline (one-line per phase)

- Phase 1: *"Sales rep clicks Request Inventory Check; SAP MM responds with ATP qty; sufficient stock auto-activates, insufficient falls back to warehouse approval (Slack + VF + JIRA Done webhook from ADR-011)."*
- Phase 2: *"Order activation publishes a platform event; Mule (or Apex @future) picks it up and POSTs to SAP SD; SAP returns the SO number; we write it back to the SF Order."*
- Phase 3: *"Invoice tax runs in parallel: native commercetax adapter on line items, SAP API on the header; Tax_Engine_Used field shows which path produced each reading."*
- Phase 4: *"Finance uploads or Mule downloads the daily CAMT.053; the service parses the XML, matches credit transactions to open Invoices by reference or amount, writes the bank-transaction reference back."*
- Phase 5: *"Nightly Mule flow pulls SAP material master, upserts SF Product2 by SAP_Material_Number__c so the ATP integration has the join key it needs."*

### Production gap statement (recruiter cue)

> *"This demo is intentionally Salesforce-centered — the SAP integration code path is fully working end-to-end against the SAP API Hub Sandbox, but sandbox is read-mostly so writes don't persist and the tax module is license-gated. Production S/4HANA with full licensing exercises the same code paths with real data; the audit fields (Status_In_SAP, Tax_Engine_Used, SAP_Payment_Reference) make the engine-vs-fallback distinction explicit on every record. No mocking; transparent fallbacks."*

### Mule integration (deferred)

The mulesoft/sap-integration-FULL.xml file still has only the one BP-query test flow. All 5 SAP services are Apex-direct callouts today. Production-target Mule layer would wrap each SAP call in retry / DLQ / idempotency per ADR-001's Mule-vs-Apex matrix and ADR-013's idempotency pattern. The Apex contract for each service stays the same; only the URL changes from SAP-direct to Mule-as-proxy. Estimated 2-3 hours of Mule flow building when needed.

### Resumption pointer

Full sprint detail in `[memory] sap_integration_sprint_checkpoint.md`. ADRs 022-026 in `docs/adr/` carry the per-phase rationale + future-state notes.

## Memory

User has persistent memory at `C:\Users\DELL\.claude\projects\c--Users-DELL-Documents-Projects-TechnoStore\memory\`. Key files indexed in `MEMORY.md`. Update memory after significant decisions; don't duplicate code-derivable facts.

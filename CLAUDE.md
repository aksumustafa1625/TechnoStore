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

## Memory

User has persistent memory at `C:\Users\DELL\.claude\projects\c--Users-DELL-Documents-Projects-TechnoStore\memory\`. Key files indexed in `MEMORY.md`. Update memory after significant decisions; don't duplicate code-derivable facts.

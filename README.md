# TechnoStore — Salesforce Revenue Cloud Demo (DACH Market)

> A production-grade Salesforce DX portfolio project that models a B2B electronics retailer serving the DACH market (Germany / Austria / Switzerland). Full **Quote-to-Cash lifecycle** built on **Revenue Lifecycle Management (RLM)** + **Contract Lifecycle Management (CLM)** + **Industries CPQ**, integrated end-to-end with **Stripe**, **Sendcloud / DHL**, **Slack (×2 channels)**, **DocuSign**, **JIRA**, and **Notion** via **MuleSoft Anypoint Studio** orchestration. Apex follows the **Kevin O'Hara `sfdc-trigger-framework`** pattern across a **six-package SFDX layout**.

[![Trigger framework](https://img.shields.io/badge/trigger--framework-Kevin%20O%27Hara-blue)](https://github.com/kevinohara80/sfdc-trigger-framework)
[![API version](https://img.shields.io/badge/Apex%20API-66.0-orange)]()
[![RLM](https://img.shields.io/badge/Revenue%20Lifecycle%20Mgmt-active-brightgreen)]()
[![CLM](https://img.shields.io/badge/Contract%20Lifecycle%20Mgmt-active-brightgreen)]()
[![Integrations](https://img.shields.io/badge/external%20systems-7-blueviolet)]()
[![MuleSoft](https://img.shields.io/badge/MuleSoft-Anypoint%20Studio-00A0DF)]()
[![Notion portfolio](https://img.shields.io/badge/Notion%20portfolio-50%20STAR%20entries-black)]()
[![SFDX packages](https://img.shields.io/badge/sfdx%20packages-6-success)]()

---

## Why this project

The German Salesforce market is hiring aggressively in **enterprise B2B Revenue Cloud + integration architecture roles** (SAP Industries, Salesforce Industries practice, Deutsche Telekom T-Systems, Allianz Technology, Mercedes-Benz.io, BMW Group IT). The DACH job spec consistently asks for the same skill mix: **RLM / CLM / Industries CPQ on the Salesforce side, plus real integration experience (MuleSoft, payment + logistics + e-signature)** on the orchestration side. This project demonstrates exactly that mix, built with industry-standard patterns rather than the inline "logic-in-the-trigger" style typical of tutorial work.

It is **not a feature inventory** — it is a single coherent **Quote-to-Cash demo narrative** flowing through 7 external systems in real time, recorded as a 12-minute Physical Order recording and documented as a **50-entry STAR-format Notion portfolio**.

---

## Business scenario

TechnoStore GmbH (fictional) is a B2B supplier of workstations, peripherals, cables, and software licenses to DACH enterprise IT buyers. The catalog is **account-context-aware** — a 50-employee mid-market customer in Köln sees the Entry-tier workstation only, while a 1200-employee enterprise in Frankfurt sees four tiers including Mission-Critical Xeon-class boxes.

| Demo account | City | Industry | Employees | Visible tiers |
|---|---|---|---|---|
| Hamburg DataWorks | Hamburg | Technology | 200 | Entry + Standard + Pro + Mission-Critical |
| München Industrial GmbH | Munich | Manufacturing | 350 | Entry + Standard + Pro |
| Frankfurt FinTech Hub AG | Frankfurt | Financial Services | 1200 | Entry + Standard + Pro + Mission-Critical |
| Köln Retail Cloud SE | Cologne | Retail | 50 | Entry tier only |

**End-to-end flow** (12 minutes from rep click to delivery):

```
Browse Catalog (account-filtered)
   → Bundle Configure (RAM / SSD / GPU)
      → Quote (19% VAT formula)
         → Order activation
            ├─→ JIRA ticket (Apex direct)
            ├─→ Slack #warehouse (Platform Event → Mule)
            ├─→ DocuSign envelope (Apex + Named Credential)
            ├─→ Stripe PaymentIntent (Mule outbound)
            └─→ Orange INVOICE email
                  → Customer pays on Stripe-hosted page
                     → Stripe webhook (HMAC-verified)
                        ├─→ Order.Status = Paid
                        ├─→ Green RECEIPT email
                        ├─→ Slack #payments-team
                        └─→ Mule Choice Router
                              ├─→ Physical: Sendcloud v3 → DHL → shipping email
                              └─→ Digital: License key + welcome email
                                 → Customer signs DocuSign
                                    → Webhook → Contract.Status = Signed
                                       → Asset created via Autolaunched subflow
```

---

## 🌟 Portfolio — Notion Documentation

The full architectural decision-making is documented as **50 STAR-format entries** in a public Notion page, generated programmatically via `NotionPublishService.publishEnterprise()`:

> **Notion portfolio:** [TechnoStore Interview Prep](https://www.notion.so/) (50 entries across 6 project phases)

Each entry is a nested-toggle structure: 4 main toggles (Situation / Task / Action / Result) with 13 sub-toggles covering Context / Problem / Goal / Constraints / Success Criteria / Approach / Implementation / Code / Screenshots / Outcome / Lessons Learned / References / Future Work — each with production-grade code snippets.

The publishing pipeline itself is part of the demo (entry 45): an Apex service that orchestrates 6 Notion API calls per entry (POST page + PATCH main toggles + 4 PATCH sub-toggles) to assemble the 3-level nested toggle structure that exceeds Notion's single-request 2-level nesting limit.

---

## 🚀 Copado Integration Plan (production scaling)

TechnoStore currently uses **GitHub Actions + SFDX** for CI/CD. For production scaling beyond a single Developer Edition org, the migration path to **Copado** (the enterprise Salesforce DevOps platform standard in DACH consultancy + enterprise teams) is documented:

> **[docs/copado-integration-plan.md](docs/copado-integration-plan.md)**

The plan covers: 4-org pipeline design (Dev → SIT → UAT → Prod), User Story lifecycle, GitHub Actions → Copado feature mapping, declarative pipeline YAML target, cost analysis, and when migration becomes justified. Includes honest framing — TechnoStore is not currently on Copado; this is the planned future state captured so the architecture conversation has a defensible answer.

---

## 🏛️ Solution Blueprint (arc42)

For the **single-document architect briefing** in [arc42](https://docs.arc42.org) format covering all 12 standard sections (Introduction & Goals → Architecture Constraints → System Scope → Solution Strategy → Building Blocks → Runtime → Deployment → Cross-cutting Concepts → Architecture Decisions → Quality Requirements → Risks & Tech Debt → Glossary), see:

> **[docs/SOLUTION_BLUEPRINT.md](docs/SOLUTION_BLUEPRINT.md)**

The Blueprint synthesizes everything in this repo — README, ADRs, Mermaid diagrams, OpenAPI specs, Notion portfolio — into one document you can read top-to-bottom in 15 minutes. Each section links to the deeper artifact for drill-down. Recruiter-friendly executive summary format that DACH enterprise architecture documentation standards expect.

---

## 🔐 Security Model

For the accurate, per-webhook authentication reality, secret-storage table, and the HMAC hardening roadmap (issue TS-SEC-002), see **[SECURITY.md](SECURITY.md)**. Short version: MuleSoft-layer Stripe webhook uses true HMAC-SHA256; the six Apex Site webhooks (DocuSign, JIRA, SAP, WhatsApp, Inventory callback, DocuSign Connect) use shared-secret equality plus external-id idempotency — cryptographic HMAC migration is planned, not shipped.

---

## 🔌 API Documentation

TechnoStore exposes inbound webhook APIs (Salesforce Public Site + MuleSoft HTTP listeners) and consumes outbound APIs from seven external systems. Both surfaces are formally documented:

| Artifact | Format | Purpose |
|----------|--------|---------|
| [`openapi/technostore-webhooks.yaml`](openapi/technostore-webhooks.yaml) | OpenAPI 3.0.3 | Salesforce Public Site webhook receivers (DocuSign Connect) |
| [`openapi/technostore-mule.yaml`](openapi/technostore-mule.yaml) | OpenAPI 3.0.3 | MuleSoft Anypoint HTTP listeners (Stripe, Sendcloud, Fulfillment router) |
| [`postman/TechnoStore.postman_collection.json`](postman/TechnoStore.postman_collection.json) | Postman v2.1 | 17 ready-to-run requests across 8 folders (JIRA / Notion / DocuSign / Stripe / Sendcloud / Slack / SF) |
| [`postman/TechnoStore.postman_environment.json`](postman/TechnoStore.postman_environment.json) | Postman environment | Placeholder credentials — populate locally, never commit real values |

**Quick start:**

```bash
# Render OpenAPI specs in a browser (no install needed)
npx @redocly/cli preview-docs openapi/technostore-webhooks.yaml
npx @redocly/cli preview-docs openapi/technostore-mule.yaml

# Run the Postman collection headless via Newman
npm install -g newman
newman run postman/TechnoStore.postman_collection.json \
  --environment postman/TechnoStore.postman_environment.json
```

See [`openapi/README.md`](openapi/README.md) + [`postman/README.md`](postman/README.md) for full setup instructions, variable descriptions, and chained workflow examples.

---

## 📜 Architecture Decision Records (ADRs)

Ten ADRs in [`docs/adr/`](docs/adr/) capturing the significant architectural decisions made during TechnoStore's development. Each follows the Michael Nygard format (Status / Context / Decision / Consequences / Alternatives Considered / References) and is **immutable once Accepted** — superseded by new ADRs rather than edited in place.

| ADR | Decision | Status |
|---|---|---|
| [001](docs/adr/ADR-001-mule-vs-apex-decision-matrix.md) | Mule vs Apex per integration use case | Accepted |
| [002](docs/adr/ADR-002-custom-metadata-over-attribute-based-adjustment.md) | Custom Metadata Type over native AttributeBasedAdjustment | Accepted (workaround) |
| [003](docs/adr/ADR-003-site-guest-user-platform-event-indirection.md) | Salesforce Site + Guest User + Platform Event indirection for inbound webhooks | Accepted |
| [004](docs/adr/ADR-004-six-package-sfdx-layout.md) | Six-package SFDX layout for separation of concerns | Accepted |
| [005](docs/adr/ADR-005-kevin-ohara-trigger-handler-adoption.md) | Kevin O'Hara TriggerHandler framework adoption | Accepted |
| [006](docs/adr/ADR-006-anypoint-studio-over-code-builder.md) | MuleSoft Anypoint Studio over Code Builder | Accepted (revisit Q4 2026) |
| [007](docs/adr/ADR-007-org-wide-email-address.md) | Org-Wide Email Address for DACH B2B deliverability | Accepted |
| [008](docs/adr/ADR-008-flying-saucer-vf-pdf.md) | Flying Saucer VF over LWC for branded PDFs | Accepted |
| [009](docs/adr/ADR-009-quote-tax-formula-invoice-tax-adapter.md) | Quote tax via formula fields, Invoice tax via commercetax adapter | Accepted |
| [010](docs/adr/ADR-010-notion-api-multi-call-orchestration.md) | Notion API multi-call orchestration for 3-level nested toggles | Accepted |

See [`docs/adr/README.md`](docs/adr/README.md) for the ADR template, lifecycle conventions, and rationale.

---

## 📐 Architecture diagrams

Five system architecture diagrams documenting TechnoStore's design at increasing levels of detail. All rendered natively in GitHub via **Mermaid** — no external tool required to view, no broken images, version-controlled with the rest of the project.

| # | Diagram | Question it answers | What you see |
|---|---------|---------------------|--------------|
| 01 | [Context](docs/architecture/01-context.md) | "Who talks to TechnoStore and what does it integrate with?" | 5 actors + 1 central system + 7 external services + 1 orchestration layer |
| 02 | [Container](docs/architecture/02-container.md) | "What are the major technical pieces inside?" | Salesforce subsystems (Lightning + Apex 5-package + Data + Industries) + MuleSoft (HTTP listeners + flows + connectors) |
| 03 | [Q2C Sequence](docs/architecture/03-sequence-q2c.md) | "How does a single Order traverse the full lifecycle?" | Time-ordered message exchange across all 7 systems, with measured latencies |
| 04 | [Data Model](docs/architecture/04-data-model.md) | "What is the schema?" | Core sObject ERD + integration support objects + per-integration custom field map |
| 05 | [CI/CD Pipeline](docs/architecture/05-cicd.md) | "How does code reach production?" | Developer → Husky → GitHub Actions (lint + scratch-org tests) → manual promotion to sandbox + prod |

These are the same diagrams a senior architect would draw on a whiteboard during an interview. Each links to the next level of detail at the bottom of the file.

---

## System architecture

```
                              ┌─────────────────────────┐
                              │   TechnoStore Sales App │
                              │   (Salesforce LEX)      │
                              └────────────┬────────────┘
                                           │
                ┌──────────────────────────┼───────────────────────────────┐
                │                          │                               │
        ┌───────▼───────┐         ┌────────▼────────┐            ┌─────────▼────────┐
        │  Browse       │         │   Quote-to-     │            │   Contract       │
        │  Catalog +    │         │   Order +       │            │   Lifecycle      │
        │  Product      │         │   AttributePri- │            │   (CLM)          │
        │  Qualification│         │   cingHandler   │            │                  │
        │  (RLM)        │         │   (@future)     │            │                  │
        └───────────────┘         └────────┬────────┘            └─────────┬────────┘
                                           │                               │
                              OrderTriggerHandler.afterUpdate()   ContractTriggerHandler
                                  (Kevin O'Hara framework)        (auto-PDF on insert)
                                           │
                  ┌────────────┬───────────┼───────────┬────────────────┐
                  │            │           │           │                │
            ┌─────▼─────┐ ┌────▼────┐ ┌────▼────┐ ┌────▼────┐ ┌────────▼────────┐
            │  JIRA     │ │  Slack  │ │ DocuSign│ │  Mule   │ │  Branded email  │
            │  (Apex    │ │ (Plat-  │ │ (Apex + │ │ (outbnd │ │  (Apex InvocMth │
            │  callout) │ │  form   │ │  Named  │ │  to     │ │  + VF PDF Flying│
            │           │ │  Event) │ │  Cred)  │ │  Stripe)│ │  Saucer)        │
            └───────────┘ └────┬────┘ └────┬────┘ └────┬────┘ └─────────────────┘
                               │           │           │
                          ┌────▼───┐   ┌───▼────┐  ┌───▼────────────────┐
                          │ Slack  │   │ DocuSign│  │  Stripe Hosted     │
                          │ #ware- │   │ envelope│  │  Payment Page      │
                          │ house  │   │ email   │  │  (customer pays)   │
                          └────────┘   └───┬────┘  └───────┬────────────┘
                                           │               │
                                  Customer signs   Stripe webhook
                                           │               │
                                   ┌───────▼───────┐  ┌────▼──────────────┐
                                   │ SF Site /     │  │ Mule HMAC verify  │
                                   │ docusign_     │  │ + Scatter-Gather  │
                                   │ webhook +     │  │ fan-out:          │
                                   │ Guest User +  │  │ ┌───────────────┐ │
                                   │ Platform      │  │ │ SF Order=Paid │ │
                                   │ Event         │  │ ├───────────────┤ │
                                   │ indirection   │  │ │ Slack #pay-   │ │
                                   └───────┬───────┘  │ │ ments-team    │ │
                                           │          │ ├───────────────┤ │
                                  Contract.Status=    │ │ Green RECEIPT │ │
                                  Signed →            │ │ branded email │ │
                                  Activate flow       │ ├───────────────┤ │
                                  → Asset created     │ │ Mule Choice   │ │
                                  via Autolaunched    │ │ Router:       │ │
                                  subflow             │ │ Physical or   │ │
                                                      │ │ Digital path  │ │
                                                      │ └───────┬───────┘ │
                                                      └─────────┼─────────┘
                                                                │
                                                  ┌─────────────┴──────────────┐
                                                  │                            │
                                          ┌───────▼────────┐         ┌─────────▼─────────┐
                                          │  Sendcloud v3  │         │  License key gen  │
                                          │  /orders POST  │         │  + welcome email  │
                                          │  → DHL pickup  │         │                   │
                                          └────────────────┘         └───────────────────┘
```

The integration choice per system follows an explicit **Mule vs Apex decision matrix** documented in entry 46 of the Notion portfolio:

| Integration | Tool | Rationale |
|---|---|---|
| Stripe PaymentIntent + Webhook | Mule | Outbound form-encoded + inbound HMAC + Scatter-Gather fan-out |
| Sendcloud v3 Orders | Mule | Complex DataWeave (bare-array + street splitter + ISO country mapping) |
| Slack #payments-team + #warehouse | Mule | Branches of larger flows, block-kit construction |
| DocuSign Outbound | Apex | Bound to Contract record context + ContentVersion |
| DocuSign Inbound Webhook | Apex | SF Site + Guest User + Platform Event indirection |
| JIRA Ticket + Agile Sprint | Apex | One-shot trigger callouts (Mule Code Builder failed — see entry 26) |
| Notion Publish | Apex | Batch portfolio generation, reuses NotionPublishService |

**Principle:** Mule when integration IS the product (fan-out, webhooks, complex transforms). Apex when integration SERVES CRM logic (trigger callouts, record-bound operations, one-shot administrative scripts).

---

## What's in the project

### Custom objects + custom settings

| Object | Type | Purpose |
|---|---|---|
| `Notion_Config__c` | Protected Hierarchy Custom Setting | Stores Notion integration token + parent page id (gitignored setup script) |
| `Jira_Config__c` | Protected Hierarchy Custom Setting | Stores JIRA Cloud API token + base URL + project key |
| `ESignatureConfig` records | Standard sObject managed via Setup → Electronic Signature Configuration | DocuSign vendor account id + Named Credential mapping (see SECURITY.md for the exact records and rotation procedure) |
| `Inventory_Check_Requested__e` | Platform Event | Fires on Order activation → Mule subscriber → Slack #warehouse |
| `DocuSign_Signed__e` | Platform Event | Published by Guest User in webhook → trigger subscriber updates Contract.Status |
| `Techno_Attribute_Price_Rule__mdt` | Custom Metadata Type | Bundle attribute pricing (RAM/SSD/GPU upcharges) — workaround for broken native engine |

### Standard object customizations

| Object | Custom fields |
|---|---|
| `Order` | `Jira_Ticket__c`, `Stripe_Payment_Intent_Id__c`, `Inventory_Status__c`, `Inventory_Approved_By__c`, `Inventory_Approved_At__c`, `Product_Type__c`, `License_Key__c`, `DocuSign_Envelope_Id__c` |
| `Contract` | `DocuSign_Envelope_Id__c`, custom flow lifecycle buttons (Submit / Sign / Approve / Activate) |
| `Quote` | `Total_Tax__c` (rollup), `Total_With_VAT__c` (formula) |
| `QuoteLineItem` | `Tax_Rate__c`, `Tax_Amount__c`, `Configured_RAM__c`, `Configured_SSD__c`, `Configured_GPU__c`, `Configured_Price_Adjustment__c` |

### Apex (organized in 5 SFDX package directories)

**`force-app-services/`** — external API callout services
- `NotionPublishService.cls` — 50-entry portfolio publisher with nested-toggle multi-call orchestration
- `DocuSignSendForSignatureService.cls` — envelope creation with Anchor Tab signing via Named Credential
- `JiraTicketService.cls` — `@future(callout=true)` JIRA Cloud `/rest/api/3/issue` POST
- `AttachAndEmailInvoicePreview.cls` + `EmailWithBrandedPdf.cls` — orange INVOICE + green RECEIPT branded PDF email
- `GenerateContractPdfService.cls` + `GenerateOrderInvoiceService.cls` — Flying Saucer VF PDF rendering
- `TechnoStoreTaxEngineAdapter.cls` — commerce tax adapter for Invoice tax calculation
- `DeliveryTrackingService.cls` + `LogisticsSystemAdapter.cls` — Sendcloud integration layer

**`force-app-handlers/`** — Kevin O'Hara TriggerHandler base + per-sObject handlers
- `TriggerHandler.cls` — Kevin O'Hara framework (MIT, vendored verbatim)
- `OrderItemTriggerHandler.cls` + `QuoteLineItemTriggerHandler.cls` — pricing recompute fan-out
- `DocuSignConnectWebhook.cls` — REST endpoint receiving DocuSign Connect events
- `DocuSignStatusUpdateTriggerHandler.cls` — Platform Event subscriber updating Contract.Status
- `InventoryStatusUpdateTriggerHandler.cls` + `InventoryCheckCallback.cls` — warehouse approval flow
- `DocumentRecipientTriggerHandler.cls` — CLM signer-role auto-population

**`force-app-controllers/`** — Visualforce controllers + REST resources
- `ContractPdfController.cls` + `InvoicePdfController.cls` — branded PDF render controllers
- `CreateContractController.cls` + `UpdateContractController.cls` — Contract lifecycle controllers
- `WarehouseInventoryApprovalController.cls` — custom VF approval surface (separation of duties)
- `RevenuePulseController.cls` — analytics dashboard controller

**`force-app-actions/`** — `@InvocableMethod` classes called from Flow
- `BundleDecompositionAction.cls` — bundle parent → child component expansion
- `GetRevenueSummaryAction.cls` — revenue rollup invocable
- `InventoryApprovalDecisionService.cls` + `InventoryCheckService.cls` + `InventoryDecisionService.cls` — warehouse decision flow actions
- `SendPaymentRemindersAction.cls` — scheduled payment reminder dispatch

**`force-app/`** — sObjects + fields + layouts + flows + permission sets + Static Resources

**`force-app-tests/`** — test classes (separate package for CI test-only deploys)

### UI

- **TechnoStore Sales App** — branded Lightning App with custom orange/blue theme + TS logo
- **Custom VF pages:** `TechnoStoreInvoicePdf.page` (orange branded), `TechnoStoreReceiptPdf.page` (green branded), `TechnoStoreContractPdf.page`, `WarehouseInventoryApproval.page`
- **Reusable VF components:** `<c:TechnoStoreHeader/>` (logo + company info), `<c:TechnoStoreSignatureBlock/>`
- **4 custom CLM lifecycle screen flows:** Submit For Approval / Send For Signature / Approve / Activate (replacing broken native CLM buttons)
- **Custom Lightning App + Tab + List Views** for the 4 DACH demo accounts

### Permissions

- `Notion_Publisher_Access` — Notion integration credentials FLS
- `Warehouse_Inventory_Approval` — warehouse user access to approval VF page
- Field-level security rules ensuring Sales reps see Inventory_Status as read-only

### MuleSoft project

- `mulesoft/` — Anypoint Studio 7.x project with flows for:
  - `stripe-create-paymentintent.xml` (form-encoded outbound)
  - `stripe-webhook-receive.xml` (HMAC verification + Scatter-Gather fan-out)
  - `sendcloud-create-order-v3.xml` (bare-array payload + dynamic customer info)
  - `slack-payments-notify.xml` + `slack-warehouse-notify.xml` (Block Kit messages)
  - `post-payment-fulfillment-router.xml` (Choice router: Physical vs Digital vs Mixed)

### Scripts (`scripts/`)

- `setup_demo_opps_quotes.apex` — 4 DACH Opportunities + 4 Quotes + ~12 QuoteLineItems
- `setup_jira_config.apex` (gitignored) — populates JIRA credentials
- `setup_notion_config.apex` (gitignored) — populates Notion integration token
- `test_notion_publish.apex` — smoke test of Notion publishing pipeline
- `notion_enterprise_batch_1.apex` through `_19.apex` — 50-entry Notion portfolio generators
- Storage management + POS cleanup utilities for Dev Edition

---

## SFDX package structure

```
TechnoStore/
├── sfdx-project.json                 # 6 packageDirectories declared
├── force-app/                        # sObjects + UI + metadata
│   └── main/default/
│       ├── objects/                    Custom Settings + Platform Events + Custom Metadata
│       ├── fields/                     Custom fields on standard objects
│       ├── layouts/                    Page layouts (Order, Contract, Quote, etc.)
│       ├── flows/                      Screen flows + Autolaunched subflows
│       ├── pages/                      Visualforce pages
│       ├── components/                 Reusable VF components
│       ├── permissionsets/             Per-feature permission sets
│       ├── namedCredentials/           DocuSign + others
│       ├── eSignatureConfigs/          CLM Signer Role configuration
│       ├── approvalProcesses/          Contract.Submit_For_Manager_Approval
│       ├── quickActions/               Custom CLM lifecycle buttons
│       ├── staticresources/            TechnoStore_Logo + brand assets
│       ├── remoteSiteSettings/         External API allowlist
│       └── sites/                      DocuSign webhook public endpoint
├── force-app-controllers/            # VF + REST endpoints (~6 classes)
├── force-app-services/               # External API callouts (~14 classes)
├── force-app-handlers/               # TriggerHandler + per-sObject (~8 classes)
├── force-app-actions/                # @InvocableMethod for Flow (~6 classes)
├── force-app-tests/                  # Test classes (CI test-only deploys)
│
├── mulesoft/                         # Anypoint Studio 7.x project
│   └── src/main/mule/flows/
│
├── scripts/                          # Apex anonymous setup + batch scripts
├── manifest/                         # package.xml + destructiveChanges.xml
├── config/
│   └── project-scratch-def.json        Scratch org with Industries CPQ + RLM + CLM
├── .github/workflows/ci.yml          # PMD lint + scratch-org deploy + tests
├── pmd-ruleset.xml                   # Apex code-quality ruleset
├── CONTRIBUTING.md                   # Standing rules + setup
├── LICENSE                           # MIT + third-party attributions
└── README.md                         # This file
```

---

## Setup

### Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli) (`sf` v2.x)
- A Salesforce org with **Industries CPQ + RLM + CLM trial features enabled** (Developer Edition with the Industries variant — sign up at developer.salesforce.com/signup → Industries Developer)
- Node.js 20+ for Prettier / Husky / Jest tooling
- (Optional, for CI) A DevHub for scratch-org tests

### Step 1 — Authorize the target org

```bash
sf org login web --alias TechnoStoreDev --set-default
```

### Step 2 — Activate Industries CPQ + RLM + CLM

In the Salesforce org: **Setup → Setup Assistant → Industries Activation** (one-time wizard). Verify by querying:

```bash
sf data query --query "SELECT Id, Name FROM PricingProcedure LIMIT 5"
sf data query --query "SELECT Id, Name FROM ProductQualificationProcedure LIMIT 5"
```

### Step 3 — Deploy all 6 package directories

```bash
sf project deploy start \
  --source-dir force-app \
  --source-dir force-app-controllers \
  --source-dir force-app-services \
  --source-dir force-app-handlers \
  --source-dir force-app-actions \
  --source-dir force-app-tests \
  --test-level RunLocalTests
```

### Step 4 — Assign permission sets

```bash
sf org assign permset --name Notion_Publisher_Access
```

(Plus any other permission sets specific to features you intend to demo.)

### Step 5 — Populate credentials (gitignored setup scripts)

Create your own copies of these scripts with real tokens (templates not in repo by design):

```bash
# scripts/setup_jira_config.apex          - JIRA API token + base URL + project key
# scripts/setup_notion_config.apex        - Notion integration token + parent page id
# scripts/setup_docusign_config.apex      - DocuSign account id + HMAC secret

sf apex run --file scripts/setup_jira_config.apex
sf apex run --file scripts/setup_notion_config.apex
```

### Step 6 — Seed demo data

```bash
sf apex run --file scripts/setup_demo_opps_quotes.apex
```

Creates 4 DACH accounts (Hamburg / Munich / Frankfurt / Cologne) + 4 Opportunities + 4 Quotes with configured workstation bundles.

### Step 7 — Generate Notion portfolio (optional)

```bash
# Smoke test (publishes one entry to verify connectivity)
sf apex run --file scripts/test_notion_publish.apex

# Full 50-entry portfolio across 19 batch scripts
for i in {1..19}; do
  sf apex run --file scripts/notion_enterprise_batch_${i}.apex
done
```

### Step 8 — Open the org and explore

```bash
sf org open
```

Navigate: **App Launcher → TechnoStore Sales → Browse Catalog** with Hamburg DataWorks account context selected. You should see 4 workstation tiers filtered by Product Qualification.

### Validation deploy (recommended before merging changes)

```bash
sf project deploy validate \
  --source-dir force-app \
  --source-dir force-app-controllers \
  --source-dir force-app-services \
  --source-dir force-app-handlers \
  --source-dir force-app-actions \
  --test-level RunLocalTests
```

The `validate` flag wraps the deployment and tests in a transaction that is rolled back on completion — your org is unchanged regardless of the result. If validation succeeds, the same deploy can be promoted via `sf project deploy quick --job-id <validateJobId>` without re-running tests.

---

## Testing

Run the Apex test suite locally with code coverage:

```bash
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --synchronous
```

Service classes that perform HTTP callouts use `HttpCalloutMock` implementations — no live external system calls in tests. Trigger handler tests go through DML so triggers actually fire end-to-end.

---

## Design decisions

A few non-obvious choices, called out so reviewers don't have to guess:

- **Kevin O'Hara `TriggerHandler` framework is non-negotiable.** Every Apex trigger extends it. Trigger files are 3 lines (instantiate handler + `.run()`). The framework ships recursion control + bypass API + max-loop protection for free, and the Handler/Helper layer keeps business logic unit-testable without DML scaffolding.

- **Six-package SFDX layout for separation of concerns.** `force-app/` (metadata + sObjects), `force-app-controllers/` (UI + REST), `force-app-services/` (external API callouts), `force-app-handlers/` (TriggerHandler + per-sObject), `force-app-actions/` (Flow `@InvocableMethod`), `force-app-tests/` (test classes). New code goes in the directory matching its architectural role — clear ownership signal.

- **Mule vs Apex decision matrix is documented explicitly** (entry 46 of the Notion portfolio + this README's Architecture section). Every integration choice is justifiable rather than preference-based: Mule for fan-out / webhooks / complex transforms, Apex for trigger-fired / record-bound / one-shot operations.

- **Custom Metadata Type + `@future` trigger for bundle attribute pricing.** The native RLM Pricing Procedure registered 0 PricingProcedureStep records despite valid metadata (Builder UI rendering bug, ~6 hours investigated, entry 16). Workaround: `Techno_Attribute_Price_Rule__mdt` + `AttributePricingHandler.recalcAttributePricing()` `@future` method, with 1:1 schema parity to `AttributeBasedAdjustment` so eventual migration back to native is config-only.

- **Salesforce Site + Guest User + Platform Event indirection for inbound webhooks.** Guest User cannot directly write standard fields like `Contract.Status` (FLS restriction), but can publish Platform Events. Trigger subscribers run in system context with full FLS, performing the actual DML. This pattern is reused for DocuSign (entry 28), Stripe webhook, and Sendcloud delivery notifications.

- **Org-Wide Email Address for all customer-facing outbound** (entry 48). Default Salesforce From-header uses the running user's email (consumer Gmail), which trips German corporate B2B spam filters. `TechnoStore <noreply@technostore.example>` lands in primary inbox at Microsoft 365 / Google Workspace tenants.

- **Branded PDFs use Flying Saucer (renderAs="PDF") with reusable VF components.** Orange INVOICE PDF pre-payment + green RECEIPT PDF post-payment. Flying Saucer cannot render emoji glyphs (caught early when lightning-bolt unicode produced empty PDF) — swapped to PNG logo via Static Resource.

- **Quote-stage VAT display via formula fields, not Apex.** The configured `commercetax.TaxEngineAdapter` only fires at Invoice creation. For Quote-stage price transparency (German B2B "show me the gross total" expectation), 4 formula fields (`Tax_Rate__c`, `Tax_Amount__c`, `Total_Tax__c` rollup, `Total_With_VAT__c`) compute 19% VAT instantly on save with zero CPU cost. Invoice still uses the full adapter for legally compliant tax.

- **Multi-call orchestration for Notion publishing.** Notion API supports max 2 levels of nesting per single POST/PATCH. For 3-level nested toggles (Page → Main toggle → Sub toggle → Content), `NotionPublishService.publishEnterprise()` makes 6 API calls per entry: 1 POST page + 1 PATCH 4 main toggles + 4 PATCH per main toggle with sub-toggles + content. 50 entries × 6 calls = 300 API calls across 19 batch scripts.

- **MuleSoft Anypoint Studio chosen over Code Builder.** Code Builder failed catastrophically for the JIRA integration path (8+ hours of Maven + JAR + CloudHub 2.0 errors). Pivot to Anypoint Studio 7.16 + CloudHub 1.0 took 3 hours and delivered all 6 working Mule flows reliably (entry 26). Maturity beats novelty for demo reliability.

- **Storage management on Dev Edition is a real concern** (entry 42). Dev Edition data storage is 5 MB. The project includes audit + cleanup scripts (`scripts/storage_*.apex`) that identify orphaned Product2 / AttributeBasedAdjustment / ContentVersion records and delete them in dependency order (junctions before parents).

---

## Roadmap

Planned next phases (ranked by DACH-recruiter impact):

### 🥇 Tier 1 — DACH-specific killer features

- **SAP S/4HANA integration** (sprint 68 in JIRA — tickets TS-2 through TS-9, 17 SP across 2 weeks). SAP API Hub sandbox + OData adapter + IDoc mapping + bidirectional BusinessPartner / Sales Order replication via MuleSoft. DACH = SAP — this is the single highest-impact addition.
- **GDPR / DSGVO compliance workflow** — Right-to-be-Forgotten custom Apex tool + DSAR (Data Subject Access Request) VF page + consent management on Account/Contact + audit log via Platform Event.
- **Multi-country VAT localization** — `Tax_Rate__mdt` keyed by ISO country code (DE 19% / AT 20% / CH 7.7%), with `Tax_Rate__c` formula resolving via `Account.BillingCountry` lookup. IBAN + BIC + Steuernummer custom fields.

### 🥈 Tier 2 — Modern tech signal

- **Claude / GenAI integration** — `ClaudeAIService.cls` Apex callout to Anthropic API for Quote sentiment analysis, RAG over Salesforce data, AI-assisted sales copilot. Demonstrates the candidate is current with the 2026 AI wave.
- **Custom LWC multi-tab bundle configurator** — Dell-style multi-classification configurator (RAM + SSD + GPU + Service tabs on one screen), replacing the native single-classification limit (entry 7). 1-day LWC build with live price recalc.
- **Salesforce Experience Cloud customer portal** — self-service Order history + Sendcloud tracking + DocuSign contract viewing + Case + Live Chat.

### 🥉 Tier 3 — Enterprise maturity

- **DATEV integration** — DACH-standard accounting CSV export (`USt-Voranmeldung` tax reporting format).
- **Klarna / Sofort payment** — DACH-popular Stripe alternative (60%+ of German B2C payments).
- **CRM Analytics dashboards** — Q2C velocity, sales forecasting per DACH country, configurator abandonment funnel.

The full ranked analysis with rationale per option is in `memory/notion_portfolio_complete.md`.

---

## Continuous integration

GitHub Actions runs PMD static analysis on every push and pull request to `main`. A scratch-org deploy + test job runs when the `SFDX_AUTH_URL` repository secret is set (see [.github/workflows/ci.yml](.github/workflows/ci.yml)).

The scratch-org config (`config/project-scratch-def.json`) requests Industries CPQ + RLM + CLM features. Without these, the deploy fails before any test runs.

To enable scratch-org CI:

1. Authorize a DevHub locally: `sf org login web --set-default-dev-hub`
2. Generate an SFDX auth URL: `sf org display --target-org <DevHub> --verbose --json` and copy the `sfdxAuthUrl` value.
3. Add it as a repository secret named `SFDX_AUTH_URL`.

---

## Memory + AI-assisted development

This project is developed in partnership with **Claude Code** (Anthropic). The `memory/` directory (gitignored at the user level but conceptually part of the workflow) stores 25+ structured memory files capturing:

- Project context + architectural decisions
- Recurring debugging patterns (CLM two-error pattern, Sendcloud v3 bare-array format, Type=NULL gotcha)
- Standing rules + feedback for AI-assisted iteration
- Cross-session continuity (each new session picks up state via CLAUDE.md + MEMORY.md index)

Entry 5 of the Notion portfolio (`05. CLAUDE.md + Memory System`) documents this pattern as itself a portfolio artifact.

---

## License

**Proprietary — All Rights Reserved.** © 2026 Mustafa Aksu. Published for portfolio review and
evaluation only. No permission is granted to use, copy, modify, or redistribute any part of the
code without prior written consent — see [`LICENSE`](LICENSE) for full terms. (Exception:
`TriggerHandler.cls` is third-party MIT code by Kevin O'Hara and remains under its original MIT license.)

---

## Credits

- **Trigger framework:** [`kevinohara80/sfdc-trigger-framework`](https://github.com/kevinohara80/sfdc-trigger-framework) (MIT licensed). `TriggerHandler.cls` is a verbatim copy with only the API version updated.
- **AI pair-programmer:** Claude Code (Anthropic). Multi-session development workflow with persistent memory.
- **Third-party APIs:** Stripe, Sendcloud, DHL (via Sendcloud), DocuSign, Slack (Salesforce), Atlassian JIRA, Notion, MuleSoft Anypoint Platform. All used under their standard developer / sandbox terms of service. No production credentials are committed.
- Built and documented as a Salesforce portfolio project for the **German / DACH job market**, focused on **enterprise Revenue Cloud + integration architecture** roles.

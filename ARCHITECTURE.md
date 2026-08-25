# TechnoStore — Apex Source Layout

This Salesforce DX project follows an **enterprise-style multi-package directory layout** to separate Apex source by responsibility. The split is driven by the standard `MVC + Service Layer` pattern adapted for Salesforce.

```
TechnoStore/
├── force-app/                          ← default package (standard SF + community classes)
│   └── main/default/
│       ├── classes/                    ← SF auto-generated (Communities, Login, ChangePassword, etc.)
│       ├── flows/                      ← All record-triggered + screen flows
│       ├── lwc/                        ← Lightning Web Components
│       ├── pages/                      ← Visualforce pages (PDF generation)
│       ├── objects/                    ← Custom + standard object metadata
│       ├── triggers/                   ← Apex triggers
│       ├── permissionsets/             ← FLS, object permissions
│       └── ... (flexipages, dashboards, reports, etc.)
│
├── force-app-controllers/              ← LWC + VF backends
│   └── main/default/classes/
│       ├── RevenuePulseController.cls
│       └── InvoicePdfController.cls
│
├── force-app-services/                 ← Reusable business logic / external integrations
│   └── main/default/classes/
│       ├── EmailWithBrandedPdf.cls           (Service for branded notification email + RECEIPT PDF)
│       ├── AttachAndEmailInvoicePdf.cls      (Service for legacy receipt mail)
│       ├── AttachAndEmailInvoicePreview.cls  (Service for pre-payment INVOICE PDF + payment-link mail)
│       └── DocuSignSendForSignatureService.cls (Service for DocuSign envelope creation)
│
├── force-app-handlers/                 ← Boundary layer (webhooks, REST resources, trigger handlers)
│   └── main/default/classes/
│       └── DocuSignConnectWebhook.cls
│
├── force-app-actions/                  ← Agentforce / Einstein Copilot invocable actions
│   └── main/default/classes/
│       ├── GetRevenueSummaryAction.cls
│       └── SendPaymentRemindersAction.cls
│
└── force-app-tests/                     ← Apex tests: 38 *Test.cls + TestDataFactory, ~426 @isTest methods (counted 2026-08-19)
    └── main/default/classes/
        ├── SapEventWebhookTest.cls, WhatsAppWebhookRestServiceTest.cls, DocuSignConnectWebhookTest.cls, ...
        └── (27 of the 66 non-test classes still have no dedicated companion test — see CONTRIBUTING.md → Testing)
```

## Why this layout

1. **Discoverability** — A new developer (or recruiter) can immediately see "we have N controllers, M services, P actions" without grepping the entire `classes/` directory.
2. **Architectural enforcement** — Code reviewers can spot violations like "this Service is doing UI work, why is it calling `ApexPages.currentPage()`?"
3. **Refactoring leverage** — Moving a class to a different layer is a `git mv` away, and the package directory is part of the change.
4. **Test discipline** — Tests live in the single `force-app-tests/` package (Salesforce's flat class namespace makes per-layer test packages pointless); the `<ClassName>Test` naming keeps them visually grouped with their layer.

## Layer rules

| Layer | Can call | Cannot call | Rationale |
|---|---|---|---|
| **Controller** | Service | another Controller, Handler | UI orchestrates, doesn't reach across UI seams |
| **Service** | another Service, external HTTP, SObject DML | Controller, Handler | Service is the domain core |
| **Handler** | Service, Platform Event publish | Controller | Inbound boundary — translates external events |
| **Action** | Service | Controller, Handler | Agent-facing — narrow contract |

## Naming conventions

| Suffix | Example | Layer |
|---|---|---|
| `Controller` | `InvoicePdfController` | controllers |
| `Service` | `EmailWithBrandedPdf` *(non-suffix exception — historical)* | services |
| `Webhook` / `Handler` / `Listener` | `DocuSignConnectWebhook` | handlers |
| `Action` | `SendPaymentRemindersAction` | actions |

> **Note:** Some Service classes don't end with `Service` for historical reasons (e.g. `EmailWithBrandedPdf`). New Services should always use the `Service` suffix.

## sfdx-project.json package directories

```json
{
  "packageDirectories": [
    { "path": "force-app", "default": true },
    { "path": "force-app-controllers" },
    { "path": "force-app-services" },
    { "path": "force-app-handlers" },
    { "path": "force-app-actions" },
    { "path": "force-app-tests" }
  ]
}
```

All directories are deployed/retrieved together via standard `sf project deploy start` and `sf project retrieve start` commands.

## Future structural additions

- `force-app-utilities/` — Static helper classes (formatters, validators, string utilities)
- `force-app-domain/` — sObject wrapper classes following Apex Common (fflib) Domain pattern
- `force-app-tests/` — Apex unit tests mirroring the layer structure (Apex requires tests in same package — could also use namespace prefix per layer)
- `force-app-triggers-handlers/` — Trigger handler classes extending Kevin O'Hara's `TriggerHandler` base

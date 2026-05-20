# ADR-030: lexoffice Invoice Integration (DACH SME Cloud Accounting)

## Status

Accepted — implemented 2026-05-20. `LexofficeInvoiceService` deployed; publishes a posted/paid standard **Invoice** (Industries Billing) to lexoffice via the public REST API (contact + invoice POST), records appear in real-time in the lexoffice web UI. Sibling of ADR-031 (DATEV CSV export); together they form the dual-segment DACH finance integration. Operates on the same standard Invoice that already carries the Stripe payment flow (Stripe_Payment_URL__c, Payment Journey LWC), SAP tax and SAP payment fields — so lexoffice publishing is a natural next step in that record's lifecycle. (An earlier draft targeted the custom Demo_Invoice__c; pivoted to standard Invoice for cohesion with the existing Stripe/SAP flow, and the Demo_Invoice__c tracking fields were removed.)

## Context

TechnoStore's Quote-to-Cash flow ended at Salesforce-side invoicing (Demo_Invoice__c, branded PDF, Stripe payment). For a DACH-market B2B SaaS demo, the finance loop must close into German accounting — that's where deals are actually booked and where a Steuerberater or finance team lives.

The DACH accounting-software market splits into two segments:

1. **SME / cloud-native** — small and mid businesses run cloud accounting directly. Market leader: **lexoffice** (Lexware Office), 200,000+ German SMEs. Real-time REST API, records visible immediately in the web UI.
2. **Steuerberater / enterprise** — larger firms hand bookkeeping to a tax advisor who uses **DATEV** (40,000+ Steuerberater). File-based (CSV import into Kanzlei-Rechnungswesen), no real-time API for most flows.

A complete demo should show **both**. This ADR covers the lexoffice (SME, real-time) path; ADR-031 covers DATEV (Steuerberater, file).

The decisive requirement for lexoffice over a DATEV-only approach: the user explicitly wanted **automatic, visible record creation in the target system's UI** — matching the JIRA / Sendcloud / Stripe pattern already in this portfolio, where a Salesforce action produces a record you can immediately see in the external tool. DATEV CSV can't do that (manual import); lexoffice API can.

## Decision

`LexofficeInvoiceService` (`force-app-services`) publishes a standard `Invoice` to lexoffice in two callouts:

1. **POST /v1/contacts** — create a lexoffice customer from the Invoice's `BillingAccount` (company name + billing address, country code mapped DE/AT/CH).
2. **POST /v1/invoices?finalize=true** — create the invoice with line items pulled from `InvoiceLine` child records (Product2 name, Quantity, GrossUnitPrice); unit prices treated as **gross** (incl. 19% DE VAT) with `taxConditions.taxType = "gross"` so lexoffice back-computes net + VAT and the total matches the Salesforce-side figure. If no InvoiceLines exist, a single summary line is built from TotalAmountWithTax.

On success it writes `Lexoffice_Invoice_Id__c`, `Lexoffice_Status__c = Published`, `Lexoffice_Published_At__c` (custom fields on the Invoice object) back to the invoice.

### Auth & config

- `Lexoffice_Config__c` Hierarchy Custom Setting (Protected): `API_Base_URL__c` (https://api.lexoffice.io), `API_Key__c` (UUID, Bearer token). Same storage pattern as `SAP_Config__c` / `Jira_Config__c`.
- `Lexoffice_API` Remote Site Setting for https://api.lexoffice.io.
- API key populated via gitignored `scripts/setup_lexoffice_config.apex` (matches `setup_*_config.apex` gitignore rule); never committed, never pasted in chat.

### Entry points

- `@future(callout=true) publishAsync(Set<Id>)` — **primary, event-driven**. Called by `InvoiceTriggerHandler.afterUpdate` when `Stripe_Payment_Status__c` transitions to 'Paid' (the Stripe webhook → Mule flow sets this). The @future defers the callout to a fresh transaction after the trigger DML commits. Idempotent: only fires when `Lexoffice_Status__c != 'Published'`.
- `@AuraEnabled publishFromButton(Id)` — manual fallback for an LWC / Lightning action button.
- `@InvocableMethod publish(List<Request>)` — for Flow.

The trigger path is the real production model: payment posting auto-propagates to accounting with no human click. Mirrors OrderTriggerHandler publishing Order_Activated__e on Status → Activated. Verified end-to-end: setting DOC-000000001 Stripe_Payment_Status__c='Paid' produced lexoffice invoice eb6daa9b and Lexoffice_Status__c='Published'.

### Error handling

Try-catch wraps both callouts. HTTP non-2xx → `IntegrationErrorLogger.logHttpFailure(...)` with the request body and correlation id, then a typed `LexofficeException`. The invoice gets `Lexoffice_Status__c = Publish Failed` (best-effort, secondary DML errors swallowed). Consistent with JiraTicketService / Sap* services.

## Consequences

### Positive

- **Automatic, visible record creation** — the demo's key requirement. Click publish in Salesforce → invoice appears in lexoffice web UI in seconds. Same "wow" as JIRA/Stripe.
- **Real DACH SME relevance** — lexoffice is the actual tool German SMEs use. Recruiter recognises it.
- **Gross-amount handling** matches what the customer saw; no rounding drift between Salesforce and lexoffice.
- **Consistent conventions** — mirrors existing integration services exactly (Custom Setting, Remote Site, IntegrationErrorLogger, @future), so it reads as part of the same codebase, not a bolt-on.

### Negative

- **lexoffice trial is 30 days** — like the SAP trial, the demo credential expires; the integration code is permanent, only the key rotates.
- **Two callouts per publish** (contact then invoice) — slightly more latency and two failure points. Acceptable for invoice volumes; production could cache/reuse contacts by a stored lexoffice contact id on the Account.
- **No line-item tax breakdown from SF** — we treat OrderItem.UnitPrice as gross @ 19%. If TechnoStore later sells mixed-VAT baskets (e.g., 7% reduced rate items), the line items need per-item tax rates. Documented as a future extension.

### Neutral

- lexoffice contact is created fresh each publish (no dedupe). For the demo this is fine; production would store the lexoffice contact id on the Account and reuse it.

## Production migration

Demo → production is config + minor hardening, no architectural change:
1. Swap trial API key for production lexoffice key in `Lexoffice_Config__c`.
2. Add contact dedupe: store `Account.Lexoffice_Contact_Id__c`, reuse if present.
3. Add per-line VAT rate if mixed-rate baskets appear.

(The InvoiceTrigger → @future auto-publish on Paid is already wired — it is the primary path, not a future item.)

## References

- `force-app-services/main/default/classes/LexofficeInvoiceService.cls`
- `force-app/main/default/objects/Lexoffice_Config__c/`
- `force-app/main/default/remoteSiteSettings/Lexoffice_API.remoteSite-meta.xml`
- `scripts/setup_lexoffice_config.apex` (gitignored), `scripts/test_lexoffice_publish.apex`
- lexoffice API docs: <https://developer.lexoffice.io/>
- ADR-031 — DATEV CSV export (Steuerberater segment, the file-based counterpart)

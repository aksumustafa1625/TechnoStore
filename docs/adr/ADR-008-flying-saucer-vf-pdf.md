# ADR-008: Flying Saucer Visualforce over LWC + jsPDF for Branded PDFs

## Status

**Accepted**

## Date

2026-04-22

## Author

Mustafa Aksu

## Context

TechnoStore generates **three categories of branded PDFs** auto-attached to Salesforce records:

1. **Orange branded INVOICE PDF** — fires on Order activation (pre-payment), attached to Order as ContentVersion, embedded in customer email with Stripe Pay Now button URL
2. **Green branded RECEIPT PDF** — fires on Stripe webhook payment confirmation, attached to Order, embedded in customer email
3. **Branded Contract PDF** — fires on Contract record insert (`ContractTriggerHandler.afterInsert()`), attached to Contract as ContentVersion

The PDFs must:

- Render TechnoStore branding (logo, orange `#FF6B00` or green `#28A745` accent, footer)
- Merge Salesforce field values (`Order.OrderNumber`, `Account.Name`, `TotalAmount`, dates, signature block placeholder)
- Be generated **server-side** so the file is attached to the record as `ContentVersion` (cannot rely on client-side rendering — the user closes the browser, the file persists)
- Be portable across email clients, archival systems, and customer document management — must be standard PDF, not HTML preview

Salesforce offers four practical paths for server-side PDF generation:

- **Visualforce `renderAs="PDF"`** with the built-in Flying Saucer renderer (Apex `PageReference.getContentAsPDF()`)
- **Lightning Web Component + `jsPDF` client-side**, with the PDF blob shipped back to Apex via `@AuraEnabled` method for storage
- **Salesforce CLM `DocumentTemplate`** with `UsageType=Contract_Lifecycle_Management` — native CLM rendering engine
- **External PDF service** (DocRaptor, PDF.co, Aspose) called via HTTP callout

Each path has trade-offs in fidelity, server-side execution, governor cost, and platform dependencies.

## Decision

**Use Visualforce `renderAs="PDF"` with Flying Saucer** for all three branded PDF surfaces. Keep the native CLM `StandardContractTemplate` available as a **second option** for Contracts that need Word-format output for legal team editing (rather than locked PDF).

Implementation:

- `force-app/main/default/pages/TechnoStoreInvoicePdf.page` — orange branded INVOICE
- `force-app/main/default/pages/TechnoStoreReceiptPdf.page` — green branded RECEIPT
- `force-app/main/default/pages/TechnoStoreContractPdf.page` — branded Contract
- `force-app/main/default/components/TechnoStoreHeader.component` — reusable VF component (logo + company info + colored divider)
- `force-app/main/default/components/TechnoStoreSignatureBlock.component` — reusable signature block VF component
- `force-app-controllers/main/default/classes/ContractPdfController.cls`, `InvoicePdfController.cls` — VF controllers that load the parent record from URL parameter via SOQL

The render pipeline:

```apex
PageReference pdfPage = Page.TechnoStoreInvoicePdf;
pdfPage.getParameters().put('id', order.Id);
pdfPage.getParameters().put('payUrl', stripePaymentUrl);
Blob pdfBlob = pdfPage.getContentAsPDF();  // Flying Saucer renders server-side
ContentVersion cv = new ContentVersion(
    Title = 'TechnoStore Invoice ' + order.OrderNumber,
    PathOnClient = 'invoice_' + order.OrderNumber + '.pdf',
    VersionData = pdfBlob,
    FirstPublishLocationId = order.Id  // auto-creates ContentDocumentLink
);
insert cv;
```

The dual-system parallel for Contracts is **intentional**: custom VF auto-fires on insert (no human action required), CLM `StandardContractTemplate` is available via the standard "Generate Document" button for cases when the legal team needs an editable Word document. Both coexist; consumer chooses.

## Consequences

### Positive

- **Zero external dependencies** — Flying Saucer ships with Salesforce. No managed package, no third-party HTTP service, no Lightning Locker compatibility worries.
- **Server-side execution** — `getContentAsPDF()` runs in Apex transaction context. The Blob is immediately storable as `ContentVersion`. User browser state is irrelevant.
- **Governor-friendly** — consumes 1 CPU unit per `getContentAsPDF()` call. For typical batch sizes (100 Contracts × 1 sec render) we are well under the 60-second total CPU budget.
- **Reusable VF components** — `<c:TechnoStoreHeader/>` and `<c:TechnoStoreSignatureBlock/>` are written once, used across three PDF pages. Adding a fourth branded PDF (e.g., Quote PDF in a future demo iteration) takes ~5 minutes by composing the existing components.
- **Familiar to senior Salesforce engineers** — Visualforce + Flying Saucer has been the Salesforce-recommended portable PDF path since 2010. Recruiters and code reviewers recognize the pattern.
- **CLM coexistence** — keeping `StandardContractTemplate` available for the manual Generate Document path is no-cost (one DocumentTemplate record) and gives the legal team an editable-Word option when needed.

### Negative / Trade-offs

- **Visualforce is the legacy UI framework** — Salesforce's strategic direction is LWC. Engineers from LWC-only backgrounds find VF visually dated and the `apex:` tag syntax less ergonomic than LWC's component model.
- **Flying Saucer rendering limits** — no emoji glyphs (caught early when lightning-bolt unicode `⚡` produced an empty PDF — see [Notion entry 4](../../README.md)), limited CSS3 support (no flexbox, no grid; tables required for layout), no JavaScript execution at render time.
- **Absolute URL requirement for Static Resources** — `<apex:image url="{!$Resource.TechnoStore_Logo}">` works only when resolved server-side; relative URLs fail silently.
- **No native React/LWC component reuse** — the LWC components built for the Lightning UI cannot be embedded in a VF `renderAs="PDF"` page. PDF rendering and UI rendering are separate codebases.

## Alternatives Considered

### Alternative A — LWC + jsPDF (client-side rendering)

Rejected because:
- **Cannot run server-side** — jsPDF runs in the user's browser. Salesforce trigger-driven PDF generation (Contract insert → auto-attach PDF) is impossible because there is no browser context.
- **Round-trip required** — to persist the PDF, the browser would have to ship the Blob back to Apex via `@AuraEnabled` method, ~50 lines of plumbing per PDF.
- **Inconsistent rendering** — client-side rendering varies by browser (Chrome vs Firefox vs Safari produce different PDFs). Server-side Flying Saucer is consistent across all users.
- **jsPDF is GPL-LGPL licensed** — not compatible with our MIT license without careful boundary management.

### Alternative B — Salesforce CLM `StandardContractTemplate` (native)

Considered for Contracts. Adopted as a **secondary** option (manual Generate Document button), not the primary because:
- **Manual trigger** — requires sales rep to click "Generate Document" on the Contract layout. Our requirement is auto-generation on insert.
- **Word output format** — CLM template produces Word `.docx`, not PDF. Some downstream consumers (Mobile app preview, email attachment compatibility) work better with PDF.
- **Template authoring requires Office Open XML knowledge** — the `.docx` template file is XML internally; merge tokens follow specific syntax. Less approachable for non-document-experts than VF.
- Kept as parallel system for cases where editable-Word output is needed (legal team review workflow).

### Alternative C — External PDF service (DocRaptor, PDF.co, Aspose)

Rejected because:
- **External dependency** — Apex callout per PDF + service uptime risk + API rate limit + monthly subscription cost.
- **Data residency concerns** — Salesforce records flow through US-hosted PDF service. DACH GDPR/DSGVO compliance requires careful Data Processing Agreement review.
- **Network latency** — round-trip to external service adds ~1-3 seconds per PDF. For bulk Contract insert (100 records), this becomes meaningful.
- **No fundamental capability the native path lacks** — Flying Saucer renders all required content. External service is paying for someone else's renderer.

### Alternative D — Pre-built PDF templates uploaded as Static Resources + field merge via Apex

Considered. Rejected because:
- Apex cannot natively merge into a pre-built PDF binary — would require an external library (iTextSharp via Heroku, etc.) introducing the same external-service trade-offs as Alternative C.
- VF + Flying Saucer is essentially "templated HTML → PDF" which is the same model but using HTML/CSS as the template language. Authoring is easier.

## Implementation gotchas (preserved from project history)

These cost development hours and are worth documenting so future engineers do not repeat:

1. **No emoji glyphs in Flying Saucer** — lightning-bolt unicode `⚡` produced silently-empty PDFs during initial logo design. **Always test `renderAs="PDF"` with the actual logo asset** before relying on it. Swap emoji to PNG via Static Resource.
2. **Inline CSS only** — Flying Saucer fetches external CSS unreliably. Keep all styling inline on `style` attributes or `<style>` block at the top of the page.
3. **Table-based layout** — no flexbox / no grid support. Use `<table>` for column layouts, `<tr>` + `<td>` for cells.
4. **`apex:image` over `<img>`** — `<img src="...">` with a relative path may fail; `<apex:image url="{!$Resource.X}">` is the safe form.
5. **`applyHtmlTag="false"`** on the `<apex:page>` declaration — prevents Salesforce from wrapping output in `<html>`/`<body>` which Flying Saucer sometimes mishandles.

## References

- **Memory**: `dual_contract_pdf_systems.md`, `technostore_branded_pdf_email_system.md`
- **Notion portfolio entries**: 4 (TechnoStore Branding), 6 (Branded Contract PDF Auto-Generation), 21 (Branded Contract PDF — VF + Flying Saucer Render Engine), 32 (Branded Invoice + Receipt PDF System)
- **Code**: `force-app/main/default/pages/TechnoStoreInvoicePdf.page`, `TechnoStoreReceiptPdf.page`, `TechnoStoreContractPdf.page`
- **Components**: `TechnoStoreHeader.component`, `TechnoStoreSignatureBlock.component`
- **Controllers**: `force-app-controllers/main/default/classes/InvoicePdfController.cls`, `ContractPdfController.cls`
- **Related ADRs**: ADR-007 (Org-Wide Email Address — the PDFs are attached to those emails), ADR-005 (TriggerHandler — ContractTrigger fires `getContentAsPDF()` via the trigger handler)
- **Salesforce docs**: [Render a Visualforce Page as a PDF](https://developer.salesforce.com/docs/atlas.en-us.pages.meta/pages/pages_output_pdf_render.htm)

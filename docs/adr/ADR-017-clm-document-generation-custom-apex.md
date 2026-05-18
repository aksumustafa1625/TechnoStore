# ADR-017: CLM Document Generation — Custom VF + Flying Saucer Over DocuSign CLM

## Status

Accepted — interim. Active since 2026-04 when the first branded Contract PDF rendered. Will be revisited if TechnoStore's deal volume justifies the DocuSign CLM seat-license investment.

## Context

TechnoStore Contracts need a generated, branded PDF that goes to the customer for signature. The Contract object has all the relational metadata (Account, line items via the Source Order, dates, signature blocks) but Salesforce out-of-the-box only renders a basic Contract record — no logo, no styled tables, no clause library, no negotiated-redline tracking.

Three product categories compete for the "generate the PDF" responsibility:

1. **DocuSign CLM** — best-in-class Contract Lifecycle Management. Clause library, version-controlled redlines, obligation tracking, post-signature search, AI-assisted review. Per-seat license, typically billed by negotiator headcount. Tight Salesforce integration via the DocuSign CLM for Salesforce package.
2. **Conga Composer / Conga CLM** — long-running Salesforce DocGen specialist. Word/PDF templates with extensive merge-field syntax. Less CLM workflow than DocuSign CLM but more flexible templating. Per-user license.
3. **Custom Apex + Flying Saucer (XHTML → PDF)** — own the template, own the rendering, no license. PDF quality is Flying Saucer's CSS-supported subset. Effort: a Visualforce page or controller-rendered HTML, Apex sends it through Flying Saucer, attaches the resulting PDF to the Contract.

Constraints shaping the call:

- **Demo budget**: zero. No DocuSign CLM seats, no Conga subscription.
- **Demo timeline**: weeks, not months. License procurement alone for DocuSign CLM is typically 2-6 weeks in enterprise. The demo can't wait.
- **Demo scope**: one-page Master Service Agreement (MSA) template. No multi-document hierarchies, no negotiated redlines, no clause library.
- **Recruiter inspection**: the PDF needs to look professional. Customer sees this; the recruiter watches the demo.
- **Production migration path**: the choice now should not lock the architecture. If TechnoStore grows into a 50-rep sales org with redline-heavy enterprise deals, the migration to DocuSign CLM should be straightforward.

## Decision

Custom Apex `GenerateContractPdfService` renders a Visualforce-style HTML template through Flying Saucer (the XHTML-renderer Apex library — see ADR-008 for the broader Flying Saucer adoption). The generated PDF is attached to the Contract as a ContentVersion. The trigger is the `Auto_Generate_Contract_Pdf_On_Create` record-triggered flow on Contract create / key-field-update; an explicit "Generate Branded Contract PDF" quick action also exists for ad-hoc regeneration.

Template includes:

- TechStore logo (top-left, blue header band)
- Contract metadata table (Contract number, Account, dates, Owner)
- Line items resolved from the Source Order (Product, Qty, Unit Price, Total)
- Standard MSA boilerplate clauses (payment terms, warranty, governing law)
- Signature block with three signatories: Customer, Sales Rep, Legal
- Footer with audit metadata (generation timestamp, doc version)

Result is `TechnoStore_MSA_<contract-number>.pdf`, typically 1.5-3 pages.

## Consequences

### Positive

- **Zero license cost** — the entire path uses native Salesforce features (VF, Apex, Flying Saucer in `force-app-services`).
- **Full template control** — we own the HTML/CSS, can update brand, layout, clause text without vendor-imposed limits or merge-field syntax constraints.
- **Demo-ready in minutes** — the flow auto-generates on Contract create, no human-in-the-loop click needed for the PDF.
- **DocuSign envelope path is independent** — `DocuSignSendForSignatureService` picks up whichever PDF is attached to the Contract (custom or otherwise), so the signature flow doesn't change when we migrate to a different DocGen vendor later.

### Negative

- **No clause library** — every Contract uses the same template body. Multi-template scenarios (DPA, NDA, MSA, SOW) would each need a separate VF page + Apex method. DocuSign CLM gives this for free.
- **No redline tracking** — if the customer wants to negotiate a clause, the redline happens outside the system. The signed PDF is the final state; there's no audit trail of what was negotiated. DocuSign CLM and Conga CLM both track this.
- **Flying Saucer CSS subset** — anything beyond basic table / typography styling won't render. Modern HTML5/CSS3 features (flexbox, grid) aren't supported. The template is 2010-era HTML.
- **Manual template maintenance** — adding a new field to the Contract layout requires updating the VF page, redeploying. Operational ownership stays with engineering, not Legal.
- **Two parallel Contract PDF systems coexist today** — see memory `dual_contract_pdf_systems.md`. Custom VF (this ADR) auto-fires on Create. Native CLM `StandardContractTemplate` exists in parallel and is invoked via the Generate Document UI. We deliberately kept both for demo reasons (showcasing two patterns). Production would pick one and retire the other.

### Future state — when DocuSign CLM is justified

Triggers for migration:

- Sales rep count crosses ~20 active negotiators (license cost amortises across volume).
- Customer base requires multi-template (DPA-required EU deals, SOW-required project sales).
- Legal team requests redline tracking and clause governance.

Migration path:

1. Procure DocuSign CLM for Salesforce package.
2. Build templates in DocuSign CLM template designer (uses Salesforce merge fields — minimal rework).
3. Replace `Auto_Generate_Contract_Pdf_On_Create` flow target with DocuSign CLM's "Generate Document" action.
4. `DocuSignSendForSignatureService` keeps working unchanged — it consumes whatever PDF is attached.
5. Retire `GenerateContractPdfService` and the VF page after one full sales cycle of validation.

Effort: 2-3 weeks including stakeholder template approval. Not a developer-only task; Legal and Sales Ops need to sign off on each template.

## Alternatives Considered

1. **Native Salesforce Industries CLM** — Salesforce's own CLM offering layered on top of Contract. Less mature than DocuSign CLM, more Salesforce-native. Considered but skipped because the recruiter audience (DACH B2B) is more likely to know DocuSign CLM by name and recognise its workflow.
2. **Conga Composer** — robust, popular, but per-user license adds up. For a one-page MSA the cost-vs-flexibility tradeoff doesn't justify Conga over the custom path.
3. **PDF generation via PDFKit / WkHtmlToPdf external service** — would require a Heroku or external server, Mule callout, async file fetch. Adds operational complexity for no template-quality gain over Flying Saucer.
4. **Word-template via Microsoft Graph API** — generate .docx, send via DocuSign. Tighter Microsoft integration but adds Office 365 dependency. Skipped because the recruiter audience expects PDF as the contract deliverable.

## Related Decisions

- ADR-008 (Flying Saucer adoption for VF PDF) — the underlying library decision; this ADR is its first major application.
- ADR-015 (Production Externalization Strategy) — Contract management row points to "DocuSign CLM if budget permits" as the target.
- Future ADR-???: DocuSign CLM Migration Plan when the move happens.

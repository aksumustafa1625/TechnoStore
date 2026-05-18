# ADR-018: Salesforce Invoice as Billing Intent, SAP FI as Accounting System of Record

## Status

Accepted — directional / forward-looking. Demo currently treats the Salesforce Invoice as the full-lifecycle record because there is no SAP. The production target architecture is documented here so the SAP Sprint (sprint 68 per memory `notion_portfolio_complete.md`) ships against a clear plan.

## Context

TechnoStore today uses a Salesforce **Invoice** record (`Invoice` sObject from Revenue Cloud Billing) as the source of truth for "money the customer owes." It carries the line items, the tax line, the PDF (branded pre-payment orange + post-payment green — see ADR-008), the email correspondence, the Stripe payment metadata, and a Status field that moves from Draft → Sent → Paid.

That works for the demo. It does not work in a real DACH enterprise for three reasons:

1. **German tax law (§14 UStG) is specific about invoice issuance.** A compliant invoice has to be issued by the system that posts the receivable to the general ledger. In a SAP-running shop that's SAP FI (Finance / Accounts Receivable). The invoice PDF that the customer receives, the legal record, and the GL posting are one atomic act in SAP. Generating the invoice in Salesforce and then "informing" SAP of the receivable would split the act across two systems and create audit ambiguity.
2. **DACH e-invoicing compliance** (ZUGFeRD hybrid PDF, XRechnung XML) imposes format requirements that change yearly. Maintaining a compliant generator in Apex / Flying Saucer is doable but means tracking spec updates as an engineering responsibility. SAP / Oracle / NetSuite track this for you as part of the license; native Salesforce Billing doesn't yet (as of 2026).
3. **Multi-system reconciliation** — when Finance has to close the books and reconcile receivables against bank statements (CAMT.053 / .054 files), the master record needs to be in the same system as the bank reconciliation. SAP does this natively. Salesforce Billing has reconciliation modules but is the smaller player in DACH Mittelstand.

The architectural question: where does the invoice live, and what role does the OTHER system play?

## Decision

In production with SAP integrated:

- **Salesforce Invoice** = **billing intent** / pro-forma. The Invoice record is created at Order activation (or at the appropriate billing event per Billing Schedule), holds the line items and dates, and is **sent to SAP via Mule** for posting. Salesforce Invoice Status becomes a mirror of the SAP posting state ("Posted in SAP", "Cancelled in SAP", "Paid in SAP").
- **SAP FI Billing Document** = **legal invoice**. The PDF the customer receives originates from SAP. The GL posting is atomic with the PDF generation. The invoice number on the customer's PDF is the SAP document number, not a Salesforce auto-number.
- **Mule pushes the billing instruction** SF → SAP via the SAP Billing API (Sales Document Billing Block release + Billing Due List run, depending on the customer's billing model — periodic vs. trigger-based).
- **Mule subscribes to SAP "invoice posted" events** (via SAP Event Mesh or polling the Billing Document API) and updates Salesforce Invoice with the SAP doc number + status.
- **Stripe payment captures still route through Mule's existing stripe-webhook-flow**, but the "mark Invoice Paid" step adjusts to "update Salesforce Invoice + push payment-received to SAP via SD payment-receipt API."
- **Customer correspondence** (the PDF email) is sent from SAP in production (via SAP's output-determination configuration) or from Salesforce as a mirror (Mule subscribes to SAP "billing-document-output" events and triggers an SF email send). The latter keeps the customer-touchpoint inside the CRM where reps see correspondence history.

In demo (today, no SAP):

- Salesforce Invoice is the only invoice that exists. Branded PDF generated locally, sent locally, paid via Stripe locally. The architecture above is documented for production; the demo just collapses SAP responsibilities into the Salesforce side.

## Consequences

### Positive

- **Compliance ownership lands in the right system.** SAP is the certified-for-German-tax-law system; the invoice PDF and GL posting are atomic there.
- **Bank reconciliation stays in one system.** Finance reconciles in SAP against CAMT.053 statements; they don't have to cross-reference Salesforce Invoice Status against SAP receivables.
- **Salesforce keeps the customer-facing surface** — the rep sees the Invoice in the Order related list, the customer sees PDFs in their email, the Stripe checkout link still works. The split doesn't change UX.
- **Mule is the seam** — adding/removing SAP integration doesn't touch the Invoice sObject schema in Salesforce, only the Mule flows. Salesforce Invoice keeps the same fields whether SAP is wired or not.
- **Stripe stays valid** for card payments (modern DACH B2B does use card for small orders). The bank-transfer / SEPA path adds, doesn't replace (see ADR-???: SEPA reconciliation when written).

### Negative

- **Latency between Salesforce Invoice create and SAP doc number return** — typically a few seconds via synchronous Billing API call, but in async-batch mode could be hours. The Salesforce Invoice has to be tolerant of a "SAP doc number pending" interim state.
- **Two invoice numbers** — Salesforce Auto-Number (`DOC-00000123`) and SAP Document Number (`90000456`). Customer email shows SAP number; internal Salesforce reps see both. Mappable via a custom field `SAP_Document_Number__c` on Invoice.
- **Refund / cancellation flow** has to round-trip through SAP — Salesforce can't unilaterally cancel an Invoice that's been posted to SAP GL. The cancel button in Salesforce becomes a "Request cancellation via SAP" action.
- **Outage handling** — if Mule or SAP is down, Salesforce Invoice creation queues up and customer-facing PDFs don't go out until SAP is healthy. Mitigation is the existing Dead-Letter Queue pattern (ADR-013) plus a "deferred invoice" status on Salesforce Invoice during outage windows.

### Future state — full migration sequence

1. **Mule billing flow built** — SF Invoice create event → SAP Billing API → return SAP doc number → SF update. Tested in SAP sandbox.
2. **Production cutover** — flip the Salesforce Invoice PDF generation off (or downgrade to a watermark "Pro-Forma Only — see SAP invoice for legal copy"). Customer emails switch to sending SAP-originated PDFs.
3. **Backfill** — historical Salesforce-only Invoices stay as-is; they're closed-book records and don't need SAP cross-reference. New invoices forward only.
4. **Reconciliation flow built** — Mule batch job reads SAP CAMT.053 statements, updates Salesforce Invoice payment status. Closes the loop with the receivables ledger.

Effort estimate: 4-6 weeks for the Mule + SAP development; 2-4 weeks for SAP-side config in the customer's SAP shop (depends on their team). Total project ~8-10 weeks.

## Alternatives Considered

1. **Keep Salesforce as the invoice system of record, push read-only summary to SAP.** Rejected: violates the "GL posting and invoice issuance must be atomic" rule. SAP would be a read-only mirror; reconciliation still has to happen in Salesforce, which doesn't have the bank-statement processing capability that mid-market companies need.
2. **Use Salesforce Revenue Cloud Billing exclusively, skip SAP.** Possible for greenfield companies without an existing SAP investment. DACH Mittelstand TechnoStore customers all already run SAP — the SAP integration isn't optional, it's an entry requirement for the deal.
3. **Third-party invoicing (Stripe Invoicing, Quickbooks, lexoffice).** Stripe Invoicing handles card-payment-focused workflows well but lacks SAP integration and ZUGFeRD support out of the box. Lexoffice is popular in German SMB but doesn't scale to mid-market.
4. **Salesforce Invoice + SAP Billing as parallel, customer chooses which is "legal."** Considered but rejected — customer education burden too high; legal team would resist "two invoices for the same sale."

## Related Decisions

- ADR-007 (Org-Wide Email Address for customer correspondence) — independent of where the PDF originates; the OWEA stays the From: address in either path.
- ADR-008 (Flying Saucer for VF PDF) — the demo's branded PDF generator. In production this becomes the pro-forma generator only; legal PDF comes from SAP.
- ADR-013 (Webhook idempotency + Integration_Error__c) — the audit substrate for the Mule SAP integration; failures during SAP billing-create get logged here.
- ADR-015 (Production Externalization Strategy) — the Invoice + Payment Reconciliation rows of the externalisation table point to this ADR.
- Future ADR-???: SEPA / Bank Transfer Reconciliation — the receivables-side pair of this ADR.

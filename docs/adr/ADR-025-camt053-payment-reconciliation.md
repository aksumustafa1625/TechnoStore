# ADR-025: CAMT.053 Payment Reconciliation — Bank-Statement-Driven Invoice Closure

## Status

Accepted — implemented 2026-05-18 in SAP Sprint Phase 4. SapPaymentReconciliationService + three new Invoice fields (Payment_Method__c, SAP_Payment_Reference__c, SAP_Payment_Posted_At__c) deployed; end-to-end verified with synthetic CAMT.053 XML matching by EndToEndId and by amount.

## Context

Demo Invoice payment flow today: Stripe Checkout link in the customer email, customer pays by card, Stripe webhook fires through Mule, SF Invoice is marked Paid. Works perfectly for the recording — fast, card-based, online. ADR-007's branded receipt flow follows.

In DACH B2B production, this is the minority path. Card payment is reserved for small / online / self-service deals. The dominant payment methods for mid-market B2B:

- **SEPA Direct Debit** — customer authorises a mandate; supplier pulls payment from the customer's bank monthly. Common for recurring invoices.
- **Bank Transfer** — customer initiates the transfer themselves on receipt of the invoice. Standard for Net 30 / Net 60 / Net 90 terms. Reference field carries the invoice number; bank's payment file (CAMT.053) confirms the credit.
- **Wire** — international, ad-hoc, less common but used for large deals.

For SEPA and Bank Transfer the loop closes via a **CAMT.053 bank statement** — an ISO 20022 XML file the bank publishes daily listing every transaction on the corporate account. SAP FI loads this file, matches each credit transaction to an open invoice by amount + customer reference, and posts the payment to accounts receivable. The matched invoice transitions to Paid in SAP.

For Salesforce to mirror this, SF needs to:

- Know which Invoices were paid via the bank channel (vs. Stripe — see Payment_Method__c).
- Capture the bank transaction reference for audit (which CAMT entry closed which Invoice).
- Reflect the value-date of the credit (when the money actually hit the account, not when SAP processed the file).

The integration question: where does the CAMT.053 parsing happen, and what's the SF-side write target?

## Decision

`SapPaymentReconciliationService.reconcile(camtXml)` is the SF-side parser. It accepts the raw CAMT.053 XML, parses credit entries, matches each to an open Invoice by a three-rule cascade, and writes the SAP-side audit fields.

### Match cascade (in precedence order)

1. **EndToEndId match.** If the CAMT entry's `TxDtls/Refs/EndToEndId` contains a Salesforce Invoice `DocumentNumber` substring, that's the match. Banks aware of the customer's invoice numbering (e.g., when the customer's accounting system populates the bank transfer reference field from the invoice line) produce these. Primary path in production.
2. **RemittanceInformation match.** If `TxDtls/RmtInf/Ustrd` (unstructured remittance info — narrative payment description) contains a DocumentNumber substring, that's the match. Fallback for customers who type the invoice number into the bank transfer's free-text field.
3. **Exact amount match.** If neither reference matches, look for an open Invoice on any Account with `TotalAmount` within ±0.50 EUR of the CAMT amount. Last-resort fuzzy match; trusts the bank file's amount as authoritative.

If none of the three rules match, the transaction is logged and skipped. Operations team reviews unmatched transactions manually in a future "Reconciliation Queue" UI (not built yet).

### Modes of invocation

- **Production (target):** Mule scheduled flow downloads the CAMT.053 from the bank's SFTP every morning, hands the XML to this Apex service via Composite REST. Most automated; runs unattended.
- **Production (interim):** Finance user uploads the CAMT.053 file via a Lightning component or Files attachment; an event-triggered flow extracts the body and calls the service.
- **Demo:** Anonymous Apex builds a synthetic CAMT.053 string (see `scripts/test_sap_payment_reconciliation.apex`) and calls the service. Demonstrates the matching logic without a real bank file.

### Writeback target — and the RLM Invoice.Status caveat

The service writes:

- `Payment_Method__c = 'Bank_Transfer'` (could be SEPA in a future iteration that examines the CAMT debtor scheme)
- `SAP_Payment_Reference__c = EndToEndId` from the CAMT entry
- `SAP_Payment_Posted_At__c = ValueDate` from the CAMT entry

**The service does NOT update Invoice.Status to 'Paid'.** Industries Billing in RLM calculates Status from related Payment Transaction records — Status is not directly writeable on the Invoice (deploy attempts return `Field is not writeable: Invoice.Status`). Production marks an Invoice paid by inserting a Payment Transaction via the Industries Billing API; Status calculates automatically. The demo writes the SAP audit fields so the trail is visible; the Status calculation is documented as the production-migration step.

This is an important nuance that surfaced during testing: a casual reading of "mark the Invoice paid" would write `Status = 'Paid'` — which compiles but throws at runtime. The audit-fields-only approach is the safe demo path.

## Consequences

### Positive

- **DACH-realistic payment story.** Stripe stays for card / self-service; CAMT-driven SEPA and Bank Transfer cover the production payment volume.
- **Audit trail per Invoice.** SAP_Payment_Reference + SAP_Payment_Posted_At + Payment_Method together prove "this Invoice was reconciled from this bank transaction on this date." Replayable, auditable.
- **Three-rule cascade is robust.** Real CAMT files have inconsistent reference populations; the cascade handles bank-aware references (Rule 1), customer-typed references (Rule 2), and reference-less payments (Rule 3 amount match).
- **Sandbox-independent.** Unlike ADR-022 (ATP) and ADR-023 (SO Ack) which depend on SAP API Hub responses, this service operates on a file — feed it any CAMT.053 XML and it parses + matches. Demo works without SAP being reachable at all.
- **Surfaces the RLM Industries Billing nuance.** "Status not writeable; insert Payment Transaction" is the kind of platform-specific knowledge that distinguishes a senior Salesforce dev from someone who's only worked with simple custom objects. Captured in the ADR for recruiter reading.

### Negative

- **No automatic CAMT delivery in the demo.** Production downloads the CAMT from a bank SFTP via Mule; demo requires manual Apex invocation with a synthetic XML. Recording requires either narration ("in production, Mule pulls this nightly") or a manual demo trigger.
- **Status doesn't flip in the demo.** Visual demo impact is muted — Invoice.Status stays "Posted" or whatever it was; only the SAP_Payment_* fields populate. Recruiter has to inspect the Invoice detail page rather than seeing a green "Paid" pill.
- **Amount-tolerance match (Rule 3) can match wrong invoices.** If two open Invoices on different Accounts happen to have the same EUR amount, the service picks the first by query order. Real-world risk is low (amounts rarely collide) but not zero; mitigation is documenting Rule 3 as a fallback rather than primary.
- **No exception queue for unmatched transactions.** Lines that pass none of the three rules are silently skipped (logged via System.debug). Production needs an UnmatchedPayment__c queue object or similar. Out of scope for this ADR.
- **No FX handling.** CAMT entries carry currency (Ccy="EUR"). Cross-currency invoices need conversion. Demo assumes single-currency.

### Future state

- **Insert Payment Transaction to flip Invoice.Status.** Production migration adds a step after the audit write: insert a record into the RLM Industries Billing Payment sObject linked to the Invoice with the matched amount. RLM auto-calculates Status='Paid' from this. Adds DML; needs a separate trigger or queueable to avoid bulkification limits.
- **Mule scheduled flow.** Production Mule downloads the CAMT.053 from the bank SFTP at 06:00 daily, calls Composite REST to hand the XML to this service. ADR-???: SAP Bank Statement Mule Flow.
- **Unmatched payment queue.** Custom object UnmatchedPayment__c with the original CAMT line + amount + date. Operations team manually triages and reassigns. Builds out a small workflow on top.
- **Reverse direction — overpayment / underpayment handling.** If the CAMT credit doesn't match the Invoice total exactly (customer paid wrong amount, partial payment, included a credit note), the service today picks Rule 3 amount-match within tolerance. Production needs explicit partial-payment + overpayment logic — likely a "split Invoice" or "create Credit Note" workflow.

## Alternatives Considered

1. **Use Stripe as the universal payment method.** Rejected for DACH B2B reality — most enterprise customers refuse to pay by card for Net-30 invoices. Stripe stays for self-service / smaller deals.
2. **Build a custom payment portal where customers click "Paid by bank transfer".** Considered but rejected — self-reporting is fraud-prone. Bank-statement-driven reconciliation is the audit standard.
3. **Parse CAMT in Mule instead of Apex.** Mule has built-in XML connectors and would handle the parse + transform cleanly. Considered but rejected because the matching logic (3-rule cascade against SF Invoices) needs SOQL access; bouncing the data through Apex anyway. Production may still move the parse to Mule and pass clean structured data to a simpler Apex matcher.
4. **Use SAP FI to drive the SF write directly.** SAP could publish a "payment posted" event via SAP Event Mesh that SF subscribes to. Architecturally cleaner — SAP is doing the reconciliation, SF mirrors. Out of scope for current SAP sandbox (Event Mesh not in trial); future ADR.

## Related Decisions

- ADR-013 (Webhook idempotency + Integration_Error__c) — parsing failures and unmatched-transaction logs flow into the same audit substrate.
- ADR-015 (Production Externalization Strategy) — the Payment Reconciliation row points to this ADR.
- ADR-018 (Salesforce Invoice vs SAP Invoice) — the broader directional choice (SF Invoice = billing intent, SAP FI = system of record) that this ADR is one tactical implementation of.
- ADR-022 (SAP MM ATP Integration) + ADR-023 (SAP SD Sales Order Acknowledgment) + ADR-024 (SAP Tax Determination) — the other SAP sprint phases. Together, all five close the demo-to-DACH-production gap on the showcased portion.
- Future ADR-???: Industries Billing Payment Transaction Insert — the missing piece for true Invoice.Status=Paid in production.

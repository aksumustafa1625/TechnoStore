# ADR-015: Production Externalization Strategy — What Lives in Salesforce vs. Outside It

## Status

Accepted — meta-architectural decision documenting the demo-vs-production boundary. Written 2026-05-18 as a forward-facing roadmap rather than a behavior change.

## Context

TechnoStore is a portfolio demo built to land a senior Salesforce / MuleSoft developer role in the DACH market. The implementation choices reflect that goal: every business process — pricing, tax calculation, inventory tracking, invoice generation, payment recording, asset lifecycle — is centralised in Salesforce so the demo can be told as one cohesive walkthrough on one screen. A reviewer with enterprise architecture experience will (correctly) point out that real DACH enterprises don't run Quote-to-Cash this way. The official-record systems live elsewhere.

The risk in an interview is that without an explicit position on this question, the reviewer reads the design as either:

1. **Naïve** — "this person doesn't know Salesforce isn't the system of record for finance" (junior signal), or
2. **Over-engineered for production** — "this person would build the whole stack inside Salesforce in a real engagement" (architectural concern signal).

Both readings hurt. The honest answer is "Salesforce-centered showcase, externalised in production — and here's exactly what moves where, why, and what stays." Documenting it formally as an ADR makes the position defensible and removes the ambiguity.

A second motivation: when SAP integration work begins (planned sprint, see memory `notion_portfolio_complete.md` Sprint 68), several of the demo's Salesforce-side responsibilities will migrate to SAP. Having the production target architecture documented up front means SAP-side work can be staged against a clear roadmap rather than negotiated component-by-component.

## Decision

Salesforce is the **commercial orchestration layer**. It owns the customer-facing surface (CRM, CPQ Quote Builder, Order capture, Contract Lifecycle, Approval workflows, customer notifications, deal-desk audit) and the events/triggers that coordinate downstream work. It is NOT the system of record for accounting, inventory, or tax.

For each responsibility currently in Salesforce, the target production owner:

| Concern | Demo (TechnoStore today) | Production target | Why it moves |
|---|---|---|---|
| Customer + Quote master | Salesforce | Salesforce | Salesforce IS the customer system; keep it. |
| Pricing — list + base prices | Native CPQ + custom Apex workaround (RLM Builder bug, see ADR-002) | Native CPQ Pricing Procedure once Builder bug resolved, OR external pricing service / SAP SD condition records | Pricing changes are business-led, not developer-led; native engine or SAP gives admin/finance control |
| Pricing — attribute-based adjustments (RAM/monitor/keyboard upgrades) | Custom `AttributeBasedAdjustment__c` + async @future trigger | Same data layer, fed into native Pricing Procedure (Builder-fixed) — admin-managed | Same data, different engine. Migration is config-only — see ADR-002 |
| Tax calculation — Quote stage | 4 formula fields displaying 19% VAT (estimated) | Same — quote shows estimated tax | Quote-stage tax is informational; full engine is wasteful here. See ADR-009. |
| Tax calculation — Invoice stage | `commercetax.TaxEngineAdapter` adapter chain inside Salesforce | External tax engine — Avalara / Vertex / SAP Tax / Oracle Tax — called via REST from Mule | DACH e-invoicing compliance (ZUGFeRD, XRechnung), multi-country VAT, exemptions all need a tax-engine vendor product; not viable to maintain in Apex. |
| Inventory / ATP check | VF approval page + JIRA replenishment ticket | SAP MM ATP API (real stock data) + JIRA still used for replenishment task tracking (Atlassian JSM has explicit warehouse use case, see ADR-011) | SAP is the stock master in a DACH manufacturing/distribution org; demo's manual VF check is the human approval surface, real data comes from SAP. |
| Order acknowledgment | Salesforce Order = system of record | Salesforce Order = commercial intent; SAP SD Sales Order = system of record. Mule pushes the SF Order to SAP via OData on activation. | Operations (picking, packing, shipping) is run from SAP. SF Order must replicate to SAP for fulfillment. |
| Contract management | Native Contract + custom Visualforce PDF + custom DocuSign integration | DocuSign CLM if budget permits, otherwise Native Contract enriched with redline / clause-library / Salesforce Industries CLM. PDF generation moves to DocuSign CLM template or Conga DocGen. | Demo's Flying Saucer Apex PDF (ADR-008) is sufficient for one-page MSAs; real contracts need negotiated redlining + obligations tracking. |
| Approval governance | Multi-tier discount approval (ADR-014) | Same, but routed through user role hierarchy (`User.ManagerId`) or external deal-desk tool (DealHub, Conga Approvals) for matrices > 10 tiers | The pattern stays; only the approver-routing scales. |
| Invoice generation | Salesforce Invoice with branded VF PDF + email | SAP FI/SD Billing Document is the legal invoice (DACH §14 UStG compliance). Salesforce Invoice becomes a billing intent / pro-forma; the official PDF comes from SAP. | German tax law requires the seller to issue a compliant invoice from the system that posts to GL. SAP does that posting; SF doesn't. |
| Payment capture | Stripe Checkout + Mule webhook → SF Invoice.Status=Paid | Stripe still valid for card payments; SEPA Direct Debit / Bank Transfer / Invoice / Net 30-60-90 terms more common in DACH B2B. CAMT.053 file processing via Mule for bank reconciliation. | DACH B2B rarely pays by card; SEPA / bank transfer + Net-30 dominates. |
| Payment reconciliation | Stripe webhook flips Invoice.Status=Paid | SAP bank reconciliation against CAMT.053 / CAMT.054 statements is the source of truth. SF Invoice mirrors the SAP payment posting. | Reconciliation is a finance task with audit requirements; lives in ERP. |
| Asset / Installed Base | Created at Order activation (Pattern 1 — ADR-012) | Same trigger point, but Asset becomes a SF lookup back to SAP equipment master. The Asset record is a SF-side commercial entitlement view; the physical-equipment record lives in SAP PM / EAM. | Service / warranty / parts management is run from SAP. SF Asset is the commercial mirror. |
| Audit / Integration Health | `Webhook_Event__c` + `Integration_Error__c` (ADR-013) | Same SF objects + Splunk / Datadog / New Relic external aggregation for cross-system observability | The SF objects stay as the SF-side audit; the centralised observability pipeline correlates them with Mule and external system logs. |
| Notification layer | Slack + email | Same | Already correctly externalised. |

The single sentence that captures all of this, and which goes in the recruiter-facing interview answer:

> *"This demo is intentionally built as a Salesforce-centered Quote-to-Cash showcase. In a real DACH enterprise, I would externalise pricing, tax, inventory, invoicing, and payment reconciliation to ERP / WMS / tax / finance systems, while Salesforce would remain the commercial orchestration layer."*

## Consequences

### Positive

- The interview answer is short, concrete, and signals architectural maturity: "I know what's demo, what's production, and which pieces move first."
- The SAP sprint roadmap is implicit in the table: Inventory ATP, Order acknowledgment, Tax determination, Payment reconciliation are the four migrations that flip the demo to a production-aware architecture. ADR-011's "Path 3 — Mule warehouse callback" deferred-state note refers to the Inventory ATP migration specifically.
- Reviewer concerns ("why is everything in Salesforce?") get a structured answer rather than a defensive one.
- Future ADRs that describe SAP integrations (e.g. "ADR-???: SAP MM ATP Integration") can reference this ADR as the framing context — they're implementing the externalisation strategy, not deviating from it.

### Negative

- The ADR is read as a list of unfinished work. A skeptical reviewer might ask "why didn't you do this in the demo?" The honest answer: scope. A demo with ten external systems wired in is a six-month build, not a portfolio project. The ADR makes the "didn't do yet" explicit, which is better than implicit.
- The table reads as "Salesforce is just the CRM, not the engine" — which understates Salesforce's role. Mitigation: lead with "commercial orchestration layer" in conversation and use the table as backup, not opening.
- Some entries in the table (e.g. "DocuSign CLM if budget permits") are budget-dependent rather than purely architectural. Production architects will read this and want a budget number. There isn't one — TechnoStore is a portfolio, not a real engagement.

### Future state — order of migrations

When real production work begins, the suggested sequence (from highest customer-pain to lowest):

1. **Tax engine** (Avalara / Vertex / SAP Tax) — high compliance risk, lowest engineering effort. Replace `commercetax.TaxEngineAdapter` chain with Mule call to tax-engine REST.
2. **SAP Order acknowledgment** — Mule pushes SF Order to SAP SD on activation; SAP returns the SO number that gets written back to SF for traceability.
3. **SAP MM ATP / Inventory check** — replaces the VF approval-page stock check with a real SAP query; the VF page remains as the human approval surface for exception cases.
4. **Payment reconciliation** — Mule batch flow reads CAMT.053 bank statements from SAP, marks SF Invoices Paid. Stripe stays for card; SEPA / Net-30 invoices flow through the bank reconciliation path.
5. **Invoice generation** — full migration to SAP FI/SD billing; SF Invoice becomes an intent record. This is the biggest change and lands last because it touches accounting and audit.

## Alternatives Considered

1. **Don't write this ADR — answer in the moment.** Rejected: a structured answer captured in writing is more defensible and reusable. Interview answers benefit from rehearsal; reviewers benefit from a single source of truth.
2. **Build a partial externalisation in the demo** (e.g. wire just Avalara for tax). Considered but skipped — adds dependencies, slows demo recording, and the ADR captures the intent without the scope cost.
3. **Hide the demo-vs-production gap and hope no one asks.** Rejected: every senior DACH interview asks this question in some form. The "Salesforce-centered showcase" answer needs to be the prepared answer, not an improvised one.

## Related Decisions

- ADR-001 (Mule vs Apex matrix) — frames which integration code lives where; the externalisations in this ADR mostly flow through Mule per ADR-001's defaults.
- ADR-002 (Pricing Apex workaround) — explains why pricing is currently in Apex, with the same "config-only migration to native engine" path as the production target.
- ADR-009 (Quote tax formula / Invoice tax adapter) — explains why Quote tax stays as formula and Invoice tax moves to a real engine.
- ADR-013 (Webhook idempotency + Integration_Error__c) — the audit substrate that survives externalisation; the SF-side log doesn't go away when Tax moves to Avalara, it just gets correlated with Avalara's response logs via the Correlation_Id field.
- Future ADRs (numbered after SAP sprint kicks off) — one per major externalisation migration.

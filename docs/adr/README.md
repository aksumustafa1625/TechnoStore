# Architecture Decision Records

This directory contains **Architecture Decision Records (ADRs)** — concise, immutable records of significant architectural decisions made during TechnoStore's development.

## What is an ADR?

An ADR is a short markdown document that captures a single architectural decision: the **context** that motivated it, the **decision** itself, the **consequences**, and the **alternatives considered**. ADRs are version-controlled alongside the code so the rationale for past decisions remains discoverable as the team and codebase grow.

This project follows the [Michael Nygard ADR format](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/templates/decision-record-template-by-michael-nygard/index.md) with light extensions (**Alternatives Considered** + **References**).

## Why ADRs?

In a project with 50+ Apex classes, 7 external integrations, and a 6-package SFDX layout, it is impossible to remember why every decision was made six months from now. ADRs solve four problems:

1. **Onboarding** — a new engineer joining the project reads ADRs in order and learns the architecture's *reasoning*, not just its *shape*.
2. **Audit** — when a security review or compliance audit asks "why this approach?", the ADR has the answer with date + author + alternatives.
3. **Memory** — the Notion portfolio is interview-prep STAR format (long, narrative). ADRs are decision-record format (short, structured). Both have their place.
4. **DACH enterprise expectation** — German architecture documentation standards (e.g., arc42) explicitly include ADRs as a first-class artifact.

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](ADR-001-mule-vs-apex-decision-matrix.md) | Mule vs Apex per integration use case | Accepted | 2026-05-11 |
| [002](ADR-002-custom-metadata-over-attribute-based-adjustment.md) | Custom Metadata Type over native AttributeBasedAdjustment | Accepted (workaround) | 2026-05-04 |
| [003](ADR-003-site-guest-user-platform-event-indirection.md) | Salesforce Site + Guest User + Platform Event indirection for inbound webhooks | Accepted | 2026-05-06 |
| [004](ADR-004-six-package-sfdx-layout.md) | Six-package SFDX layout for separation of concerns | Accepted | 2026-04-30 |
| [005](ADR-005-kevin-ohara-trigger-handler-adoption.md) | Kevin O'Hara TriggerHandler framework adoption | Accepted | 2026-04-30 |
| [006](ADR-006-anypoint-studio-over-code-builder.md) | MuleSoft Anypoint Studio over Code Builder | Accepted (revisit Q4 2026) | 2026-05-01 |
| [007](ADR-007-org-wide-email-address.md) | Org-Wide Email Address for DACH B2B deliverability | Accepted | 2026-05-02 |
| [008](ADR-008-flying-saucer-vf-pdf.md) | Flying Saucer VF over LWC for branded PDFs | Accepted | 2026-04-22 |
| [009](ADR-009-quote-tax-formula-invoice-tax-adapter.md) | Quote tax via formula fields, Invoice tax via commercetax adapter | Accepted | 2026-05-03 |
| [010](ADR-010-notion-api-multi-call-orchestration.md) | Notion API multi-call orchestration for 3-level nested toggles | **Superseded** (2026-05-14 — refactored to single-POST flat-heading structure; see ADR's Supersession Note) | 2026-05-11 |
| [011](ADR-011-inventory-approval-convergent-paths.md) | Inventory Approval — Two Convergent Activation Paths | Accepted |  |
| [012](ADR-012-order-first-activation-pattern-1.md) | Order-First Activation (Pattern 1 — Transactional) | Accepted |  |
| [013](ADR-013-webhook-idempotency-and-error-logging.md) | Webhook Idempotency + Centralised Integration Error Logging | lifecycle (`Received` → `Processed` / `Failed`) doesn't transition under the Guest User. Visible incompleteness on the audit dashboard. Future fix: have `InventoryStatusUpdateTriggerHandler` (or a new platform event consumer) flip the status when the downstream work completes — that trigger runs as Automated Process and has full CRUD. |  |
| [014](ADR-014-multi-tier-discount-approval-matrix.md) | Multi-Tier Discount Approval Matrix | Accepted |  |
| [015](ADR-015-production-externalization-strategy.md) | Production Externalization Strategy — What Lives in Salesforce vs. Outside It | Accepted |  |
| [016](ADR-016-pricing-apex-workaround.md) | Bundle Attribute Pricing — Apex Workaround for RLM Pricing Procedure Builder | Accepted |  |
| [017](ADR-017-clm-document-generation-custom-apex.md) | CLM Document Generation — Custom VF + Flying Saucer Over DocuSign CLM | Accepted |  |
| [018](ADR-018-salesforce-invoice-vs-sap-invoice.md) | Salesforce Invoice as Billing Intent, SAP FI as Accounting System of Record | Accepted |  |
| [019](ADR-019-slack-notification-vs-decision-surface.md) | Slack as Notification Surface, Not Decision Surface | Accepted |  |
| [020](ADR-020-visualforce-vs-lwc-warehouse-approval.md) | Visualforce for Warehouse Approval Page (Demo) — LWC for Production | Accepted |  |
| [021](ADR-021-customer-master-billto-source.md) | Customer Master / BillTo Source — Demo Backfill vs Production SAP BP Sync | Accepted |  |
| [022](ADR-022-sap-mm-atp-integration.md) | SAP MM ATP Integration — SAP-First, JIRA-Fallback Hybrid for Inventory Check | Accepted |  |
| [023](ADR-023-sap-sd-sales-order-acknowledgment.md) | SAP SD Sales Order Acknowledgment — Platform Event Decoupling on Order Activation | Accepted |  |
| [024](ADR-024-sap-tax-determination-parallel-adapter.md) | SAP Tax Determination — Parallel Adapter to the Native commercetax Chain | Accepted |  |
| [025](ADR-025-camt053-payment-reconciliation.md) | CAMT.053 Payment Reconciliation — Bank-Statement-Driven Invoice Closure | doesn't flip in the demo.** Visual demo impact is muted — Invoice.Status stays "Posted" or whatever it was; only the SAP_Payment_* fields populate. Recruiter has to inspect the Invoice detail page rather than seeing a green "Paid" pill. |  |
| [026](ADR-026-sap-material-master-sync.md) | SAP Material Master Sync — Nightly Product2 Reconciliation | Accepted |  |
| [027](ADR-027-sap-customer-master-sync.md) | SAP Customer Master Sync — Nightly Account Reconciliation from SAP Business Partner | Accepted |  |
| [028](ADR-028-sap-event-mesh-inbound-webhook.md) | SAP Event Mesh Inbound Webhook + CloudEvents Dispatcher | Accepted |  |
| [029](ADR-029-sap-trial-limitation-and-production-migration.md) | SAP Trial Tenant Limitation and Production Migration Path | Accepted |  |
| [030](ADR-030-lexoffice-invoice-integration.md) | lexoffice Invoice Integration (DACH SME Cloud Accounting) | Accepted |  |
| [031](ADR-031-datev-csv-export.md) | DATEV Buchungsstapel CSV Export (Steuerberater Segment) | Accepted |  |
| [032](ADR-032-rlm-bundle-pricing-research-first-diagnostic.md) | RLM bundle pricing research-first diagnostic before more org changes | Accepted | 2026-06-29 |
| [033](ADR-033-rlm-bundle-pricing-forensic-debug-log.md) | RLM bundle pricing forensic debug log and lessons learned | Accepted | 2026-06-30 |

## When to write a new ADR

Add a new ADR when the decision:

- Affects multiple subsystems
- Rejects a viable alternative (so the rejection rationale is preserved)
- Has non-obvious trade-offs that future engineers will question
- Should outlive any single feature branch or sprint
- Locks in a constraint that future features will need to respect

Skip ADRs for:

- Routine code-style choices (use Prettier + PMD ruleset instead)
- Implementation details that are easily reversible
- Decisions that only affect a single class

## ADR lifecycle

- **Proposed** — draft, under discussion
- **Accepted** — committed to `main`, in effect
- **Deprecated** — no longer applies but kept for history
- **Superseded by ADR-NNN** — replaced by a newer decision

Once **Accepted**, an ADR is **immutable**. If circumstances change, supersede it with a new ADR rather than editing the old one — the chain preserves architectural history.

## ADR template

When writing a new ADR, copy this skeleton:

```markdown
# ADR-NNN: <Short decision title>

## Status

Accepted (or Proposed / Deprecated / Superseded by ADR-XXX)

## Date

YYYY-MM-DD

## Author

Mustafa Aksu

## Context

What forces are at play? What problem are we solving? What constraints
apply? 3-6 sentences.

## Decision

What did we decide? Short and declarative. 1-3 sentences.

## Consequences

### Positive
- ...

### Negative / Trade-offs
- ...

## Alternatives Considered

### Alternative A — <name>
Why it was rejected.

### Alternative B — <name>
Why it was rejected.

## References

- Memory: `<topic>.md`
- Notion portfolio entry: <NN>
- Related ADRs: ADR-<NNN>
- External: <URL>
```

## Related documentation

- [Architecture diagrams](../architecture/) — 5 Mermaid views (Context / Container / Sequence / Data / CI-CD)
- [README.md](../../README.md) — Project overview with Mule vs Apex matrix table
- [CONTRIBUTING.md](../../CONTRIBUTING.md) — Standing rules including ADR conventions
- Notion portfolio — 51 STAR-format entries on architectural decisions, debugging stories, and integration recipes (entry 51 documents the Notion structure refactor itself — see ADR-010 supersession)

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

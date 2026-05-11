# ADR-001: Mule vs Apex per Integration Use Case

## Status

**Accepted**

## Date

2026-05-11

## Author

Mustafa Aksu

## Context

TechnoStore integrates with seven external systems: Stripe (payments), Sendcloud + DHL (logistics), Slack (×2 channels for finance + warehouse ops), DocuSign (e-signature), Atlassian JIRA (ticket tracking), Notion (portfolio documentation), and MuleSoft Anypoint Platform (orchestration). For each integration, the project faces a binary architecture choice: **orchestrate via MuleSoft Anypoint Studio**, or **call directly from Apex via HTTP callout**.

A naive "use Mule for everything" approach inflates complexity and deploy overhead without commensurate benefit — orchestrating a one-shot JIRA ticket creation through Mule requires ~3 hours of setup (HTTP listener config + DataWeave transform + connector config + CloudHub deploy + SF Connector polling) versus ~30 minutes for direct Apex callout (`@future` method + Custom Setting for credentials + JSON serialization).

A naive "use Apex for everything" approach hits real platform limits on inbound webhooks (Salesforce Sites + Guest User indirection has FLS quirks documented in ADR-003) and fan-out scenarios (5+ parallel HTTP callouts from a single trigger context risk hitting governor limits: 100 callouts per execution, 60-second total CPU time, 6 MB heap).

The decision must be made repeatedly — once per integration today, and once per future integration. An explicit, defensible decision matrix avoids ad-hoc preference-based choices.

## Decision

Adopt an explicit **Mule vs Apex per use case** decision matrix with two general principles:

- **Use MuleSoft Anypoint Studio when integration IS the product**:
  - Multi-system fan-out (one input event → multiple parallel outputs)
  - Webhook receivers needing signature verification + timestamp freshness + retry policy
  - Choice router branching by payload field (Physical vs Digital vs Mixed Orders)
  - Complex DataWeave transforms across schema boundaries

- **Use Apex direct callout when integration SERVES CRM logic**:
  - Single-system one-shot operations from trigger context
  - Record-bound operations that need Salesforce context (FLS, sharing, ContentVersion access)
  - Trigger-fired callouts where transaction boundary matters
  - Administrative batch scripts (`@future`, Queueable, Schedulable)

Applied to TechnoStore's seven integrations:

| Integration | Tool | Rationale |
|-------------|------|-----------|
| Stripe PaymentIntent + Webhook | Mule | Outbound form-encoded payload + inbound HMAC-verified webhook + Scatter-Gather fan-out (SF Order update + Slack notification + receipt email) |
| Sendcloud v3 Orders | Mule | Complex DataWeave transform (bare-array payload schema + street splitter + ISO country mapping) over fetched SF Order + Account + Contact extended SOQL |
| Slack #payments-team | Mule | Branch of Stripe webhook fan-out; Block Kit JSON construction is cleaner in DataWeave than Apex `JSON.serialize` |
| Slack #warehouse | Mule | Platform Event subscriber (`/event/Inventory_Check_Requested__e`) routed to Slack incoming webhook |
| DocuSign Outbound (Send for Signature) | Apex | Bound to Contract record context; needs Contract.Id + ContentVersion VersionData + BillToContact data; persists envelopeId back on Contract |
| DocuSign Inbound Webhook | Apex (Site + Guest User + Platform Event indirection — see ADR-003) | Public webhook target must be Salesforce Site URL anyway; Mule adds a hop without value |
| JIRA Ticket Create + Agile Sprint | Apex | One-shot trigger callouts from `OrderTriggerHandler.afterUpdate()`; Mule path failed (see ADR-006) |
| Notion Publish | Apex | Batch portfolio generation; reuses `NotionPublishService` and credentials Custom Setting |

The decision matrix is enforced by being **the first question every new integration must answer**, documented in `CONTRIBUTING.md` and surfaced as the lead architecture table in `README.md`.

## Consequences

### Positive

- **Defensible per-integration choices** — every routing decision has a documented rationale, not preference.
- **Performance discipline** — Mule's Scatter-Gather is genuinely the right tool for parallel fan-out (max-of-durations, not sum-of); Apex `@future` is genuinely the right tool for single-system trigger callouts.
- **Reduced cognitive load** — engineers don't re-debate the choice every time a new integration is proposed; they consult the matrix and pick.
- **Recruiter-visible architectural maturity** — the matrix in `README.md` signals "this engineer thinks about cost/benefit per integration", not "this engineer learned one tool and uses it everywhere".

### Negative / Trade-offs

- **Two technology stacks to maintain** — Mule flows live in `mulesoft/` with their own CI/CD (CloudHub 1.0) and credential management (`mule-app.properties` gitignored). Apex lives in `force-app-services/` with SFDX deploy + Custom Settings for credentials. Engineers must know both.
- **Cross-language correlation patterns required** — Stripe `metadata.order_id` field passes Salesforce Order Id through Stripe's storage so the inbound webhook can correlate back; similar pattern for Sendcloud `external_order_id` + DocuSign envelopeId. Each external system needs its own correlation key.
- **Migration path not always cheap** — switching an integration from Apex to Mule (or vice versa) requires rewriting the integration. Decision should be deliberate.

## Alternatives Considered

### Alternative A — Mule for everything

Rejected because:
- One-shot JIRA ticket creation took 8+ hours of failed setup in MuleSoft Code Builder vs 2 hours direct Apex callout (see ADR-006).
- CloudHub deployment overhead per integration is significant; deploying a 50-line transform as a separate Mule app feels wasteful.
- Salesforce-bound logic (DocuSign Send tied to Contract context, branded PDF email tied to Order activation) is awkward in Mule because Mule has no native Salesforce record context — it must query SF, transform, then update SF.

### Alternative B — Apex for everything

Rejected because:
- Inbound webhook signature verification (HMAC-SHA256 + timestamp freshness) is verbose in Apex; DataWeave `Crypto::HMACBinary` is one line.
- Parallel fan-out from trigger context risks hitting 100-callout governor limit (Stripe webhook fans out to 4+ downstream actions).
- Stripe form-encoded payload construction is awkward in Apex (must hand-build URL-encoded strings); DataWeave `output application/x-www-form-urlencoded` is one declaration.
- Mule's retry policy + Dead Letter Queue + observability via Anypoint Monitoring are production-grade features that would have to be hand-rolled in Apex.

### Alternative C — Per-developer preference

Rejected because:
- Inconsistent architecture across integrations makes onboarding new engineers harder.
- "I prefer Mule because I learned it last week" is not a defensible answer in an architecture review.

## References

- **Memory**: `notion_portfolio_complete.md`, `mulesoft_integration_setup.md`
- **Notion portfolio entry**: 46 — "Architectural Decisions — Mule vs Apex per Use Case"
- **Related ADRs**: ADR-003 (Site + Guest + Platform Event for webhooks), ADR-006 (Anypoint Studio over Code Builder)
- **README**: Top-level table in `README.md` reproduces the matrix
- **CONTRIBUTING.md**: Standing rule requires consulting the matrix before any new integration

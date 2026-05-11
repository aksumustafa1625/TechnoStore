# ADR-006: MuleSoft Anypoint Studio over Code Builder

## Status

**Accepted** — revisit in Q4 2026 after Code Builder + CloudHub 2.0 have 12+ months of additional GA hardening

## Date

2026-05-01

## Author

Mustafa Aksu

## Context

MuleSoft offers two development environments for building integration flows:

- **Anypoint Studio** — the mature Eclipse-based IDE shipped since 2014, with a visual flow designer, established CI/CD path via CloudHub 1.0, and ~10 years of production usage across enterprise customers.
- **Code Builder** — the new VS Code extension that went GA in 2024, marketed as the modern replacement for Studio. Features cloud-native deployment via Anypoint Exchange, better git integration, and tighter alignment with the developer-IDE ecosystem.

The initial TechnoStore integration plan targeted **Code Builder** for the "newer = better" assumption — Anypoint Exchange + CloudHub 2.0 + VS Code alignment all sounded like a cleaner modern stack than Eclipse-based Studio + CloudHub 1.0.

Reality intervened. The Code Builder integration path failed repeatedly over **8+ hours of investigation** for the JIRA ticket integration (which the project later moved to direct Apex callout — see ADR-001 + Notion entry 39). Failure modes encountered:

- **Maven build errors** — missing transitive dependencies that didn't surface until the build step, with stack traces pointing at Mule SDK internals
- **JAR packaging errors** — manifest format issues from Code Builder's project scaffolding template
- **CloudHub 2.0 deployment errors** — `502 Bad Gateway` from the Anypoint management plane when promoting a build to the runtime
- **Anypoint Exchange OAuth errors** — intermittent token rejection during artifact upload

Each Code Builder release between Q4 2024 and Q2 2026 appeared to introduce new breakage. Stack Overflow + Anypoint Community had reports of similar issues but no consistent resolution. The integration was now blocking demo prep with 4 weeks remaining in the schedule.

A pivot decision was required: continue debugging Code Builder (risk: more time lost, potentially never working) or pivot to Anypoint Studio (cost: re-create project artifacts, lose 8 hours of Code Builder setup time but gain reliable deployment).

## Decision

**Pivot to Anypoint Studio 7.16 with CloudHub 1.0 as the runtime target.** Code Builder remains documented as a "not-ready-yet" option for future re-evaluation.

Anypoint Studio rebuild details:

- Eclipse-based IDE installation (Windows)
- Embedded Maven (no separate Maven installation required)
- Anypoint Platform credentials registered through Studio Preferences
- 6 core Mule flows rebuilt in ~3 hours total:
  - `stripe-create-paymentintent.xml` (form-encoded outbound)
  - `stripe-webhook-receive.xml` (HMAC verification + Scatter-Gather fan-out)
  - `sendcloud-create-order-v3.xml` (bare-array payload + dynamic customer info)
  - `slack-payments-notify.xml` + `slack-warehouse-notify.xml` (Block Kit messages)
  - `post-payment-fulfillment-router.xml` (Choice router: Physical vs Digital vs Mixed)
- Local deployment via Mule Standalone 4.4.x runtime for development testing
- CloudHub 1.0 deployment via Anypoint Runtime Manager for shared/demo access

Net time cost: 8 hours Code Builder + 3 hours Anypoint Studio rebuild + 1 hour verification = **12 hours total**. If Code Builder had worked first try: ~4 hours. **Net loss: 8 hours** — accepted as the cost of demo reliability.

## Consequences

### Positive

- **Reliable deployments** — Anypoint Studio + CloudHub 1.0 has ~5 years of production maturity. Build/package/deploy works on every run.
- **Predictable behavior** — Eclipse IDE is slower to start (~30 sec) than Code Builder (~5 sec) but never silently breaks. The boring tool wins for demo recording.
- **Larger community knowledge base** — Stack Overflow + Anypoint Community + MuleSoft Trailhead have ~10 years of accumulated answers for Studio. Code Builder's knowledge base is ~18 months old.
- **Visual flow designer** — drag-and-drop flow construction matches what Salesforce architects expect to see when reviewing a MuleSoft project. Code Builder's text-first XML editing requires more familiarity.
- **CloudHub 1.0 is the proven runtime target** — paid customers run production workloads on it. Code Builder's CloudHub 2.0 is newer and was the specific failure point in our investigation.

### Negative / Trade-offs

- **Modernity signal lost** — "I use Anypoint Studio + CloudHub 1.0" is the safe-boring answer; "I use Code Builder + CloudHub 2.0" would have been the cutting-edge answer. Recruiter perception of stack currency matters slightly.
- **Eclipse heritage** — Anypoint Studio shows its age in places (slower than VS Code, occasional UI quirks). Engineers from VS Code-only backgrounds find it visually dated.
- **Migration burden when re-evaluating** — moving the existing TechnoStore Mule project from Studio to Code Builder in Q4 2026 requires re-import + re-test. Code Builder claims "imports Studio projects" but our 8-hour failure was during this exact import path.
- **CloudHub 1.0 is on Salesforce's deprecation trajectory** — not deprecated as of 2026-Q2, but new features (auto-scaling, fine-grained observability) ship to CloudHub 2.0 first. The 1.0 runtime is feature-frozen.

## Alternatives Considered

### Alternative A — Continue debugging Code Builder

Rejected because:
- 8 hours already invested with no clear root cause and no community-blessed workaround.
- Demo prep schedule had 4 weeks remaining. Each additional Code Builder day was displacing Stripe + Sendcloud + Slack + DocuSign integration work which collectively delivered more demo value.
- Sunk-cost fallacy avoided — the right call was to cut losses and pivot.

### Alternative B — Self-hosted Mule runtime (Mule Standalone) for production

Considered. Rejected because:
- Self-hosted Mule requires managing the JVM, OS patches, monitoring, scaling — infrastructure complexity unrelated to the demo's value proposition.
- The demo runs a local Mule Standalone for development testing (no AWS bill); CloudHub 1.0 is reserved for shared/recorded demos.

### Alternative C — Use Apex for everything, drop MuleSoft entirely

Rejected because:
- MuleSoft is a core piece of the DACH integration-architect job spec (T-Systems, Deutsche Bank, Accenture all ask for it). Dropping it weakens the portfolio's positioning.
- The integrations where MuleSoft adds genuine value (Stripe webhook signature verification, Sendcloud DataWeave transforms, Slack Block Kit construction) would require ~2x more Apex code if hand-rolled.

### Alternative D — Wait for Code Builder GA stability before starting Mule work

Rejected because:
- Code Builder went GA in 2024 — it was already "GA". The failures were post-GA, suggesting the GA milestone was premature.
- Waiting indefinitely delays the demo.

## Future re-evaluation criteria

Revisit this decision in **Q4 2026** (12 months after this ADR). Trigger conditions for re-pivoting to Code Builder:

- Two consecutive Code Builder releases ship without breaking changes
- CloudHub 2.0 has 12+ months of additional production usage at scale
- Anypoint Community has consensus solutions for the deploy/Maven/JAR failures we encountered
- A working Code Builder example project deploys to CloudHub 2.0 first-try on a clean Windows + macOS + Linux installation

If all four criteria are met: migrate TechnoStore Mule project from Studio to Code Builder + CloudHub 2.0. Migration effort estimated at ~1-2 days (Studio projects import into Code Builder, but the deploy path is what failed).

## References

- **Memory**: `mulesoft_integration_setup.md`
- **Notion portfolio entry**: 26 — "MuleSoft Anypoint Studio vs Code Builder — 8 Hour Failure + Pivot Decision"
- **Code**: `mulesoft/` (Anypoint Studio project)
- **Related ADRs**: ADR-001 (Mule vs Apex matrix — Mule is where MuleSoft is the right answer)
- **Decision rationale meta-pattern**: "When a new tool/runtime has <2 years of production maturity, default to the older option unless the new one offers something the old one cannot do at all."

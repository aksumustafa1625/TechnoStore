# Contributing to TechnoStore

TechnoStore is primarily a portfolio project targeting DACH-market Salesforce architect / lead developer roles, but it follows the same conventions a mid-size Salesforce team would. If you're cloning to learn from the codebase, or extending it, the rules below keep the repo consistent.

## Setup

You need:
- [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli) (`sf` v2.x)
- A Salesforce org with Industries CPQ + RLM + CLM features (Developer Edition with the Industries trial variant — see entry 1 of the Notion portfolio)
- Node.js 20+ for Prettier / Husky / Jest tooling

```bash
git clone https://github.com/aksumustafa1625/TechnoStore.git
cd TechnoStore
sf org login web --alias TechnoStoreDev --set-default
sf project deploy start --source-dir force-app --source-dir force-app-controllers --source-dir force-app-services --source-dir force-app-handlers --source-dir force-app-actions
sf org assign permset --name Notion_Publisher_Access
```

For demo data:

```bash
sf apex run --file scripts/setup_demo_opps_quotes.apex
```

For Notion portfolio publishing (requires `scripts/setup_notion_config.apex` populated with your Notion integration token — gitignored):

```bash
sf apex run --file scripts/setup_notion_config.apex
sf apex run --file scripts/test_notion_publish.apex
```

## Standing rules

These rules every change in this repo must follow. They live in `memory/` as `feedback_*.md` notes (project memory for AI-assisted development), but the short version is below.

### Apex architecture

- **Trigger framework:** Every Apex trigger extends Kevin O'Hara's `TriggerHandler` (`force-app-handlers/main/default/classes/TriggerHandler.cls`). Trigger files are 3 lines; logic lives in a Handler/Helper pair.
- **Five-package SFDX layout** for separation of concerns:
  - `force-app/` — metadata (sObjects, fields, layouts, flows, permission sets, Static Resources)
  - `force-app-controllers/` — Visualforce controllers + `@RestResource` classes (UI + REST endpoints)
  - `force-app-services/` — external API callout services (Stripe, Sendcloud, DocuSign, JIRA, Notion)
  - `force-app-handlers/` — `TriggerHandler` base + per-sObject trigger handlers + Platform Event subscribers
  - `force-app-actions/` — `@InvocableMethod` classes called from Flow
  - `force-app-tests/` — test classes (separate package for CI test-only deploys)
- **Selector pattern (FFLib-style):** All SOQL goes through `<SObject>Selector` classes. Helpers and Handlers never write inline SOQL.
- **Service layer for external systems:** Stripe / Sendcloud / Slack / DocuSign / JIRA / Notion callouts each have a dedicated `<System>Service.cls` under `force-app-services/`.
- **Custom Settings for credentials:** `Notion_Config__c`, `Jira_Config__c`, `DocuSign_Config__c` are Protected Hierarchy Custom Settings. The matching `scripts/setup_<system>_config.apex` scripts (which populate real tokens) are gitignored.

### Mule vs Apex decision matrix

When adding a new integration, consult the matrix in `memory/notion_portfolio_complete.md` (mirrored in entry 46 of the Notion portfolio):

- **Mule when integration IS the product** — multi-system fan-out, webhook receivers needing signature verification + retry, Choice router branching.
- **Apex when integration SERVES CRM logic** — single-system one-shot callouts, record-bound operations, trigger-fired callouts.

The first instinct check: if the integration has a fan-out (one input → multiple outputs), it's Mule. If it's a single record-bound callout from a trigger, it's Apex.

### Documentation

Every custom class and trigger we author starts with an ApexDoc header:

```apex
/**
 * @description  What this class does and why.
 * @group        TechnoStore <Subsystem>
 * @author       Mustafa Aksu
 * @date         YYYY-MM-DD
 */
```

Every public method gets `@description`, `@param`, and `@return` blocks. Every private method gets at least a one-line `// what this does` comment above it.

Vendored third-party files (currently `TriggerHandler.cls`) are NOT touched — the README and LICENSE credit the upstream author.

### Testing

- Every class ships with a dedicated `<ClassName>Test.cls` under `force-app-tests/`.
- Helper / Selector / utility classes get **unit tests** that exercise the static methods directly without DML.
- Trigger / Handler classes get **integration tests** that go through DML so the trigger actually fires.
- Service classes that make HTTP callouts use `HttpCalloutMock` implementations — no live external system calls in tests.
- Assertions include a descriptive message: `System.assertEquals(expected, actual, 'why')`.

### Commits

- **Atomic** — one logical change per commit.
- **Plain English summary line** under 72 characters — match the existing project commit style (see `git log --oneline`).
- **Multi-line message body** explains the *why* and any non-obvious tradeoffs.
- **Co-authored-by** trailer for AI-assisted commits.

### Code style

- Apex API version: 66.0 (per `sfdx-project.json`).
- `with sharing` on every class that does DML or SOQL.
- `WITH USER_MODE` on SOQL when running in user context (Selector-level FLS).
- Line endings are LF (enforced via `.gitattributes`).

### Secrets management

The following files contain real credentials and are gitignored:

- `scripts/setup_jira_config.apex` — JIRA API token
- `scripts/setup_notion_config.apex` — Notion integration token
- `mulesoft/**/mule-app.properties` — Stripe / Sendcloud / Slack webhook secrets
- `**/jira-properties.yaml` — JIRA-Mule integration credentials

When adding a new integration that needs secrets, follow the same pattern:
1. Create a Protected Hierarchy Custom Setting (e.g., `New_System_Config__c`)
2. Create `scripts/setup_new_system_config.apex` to populate it
3. Add the script path to `.gitignore`
4. Document the setup process in the relevant Notion portfolio entry

## Continuous integration

GitHub Actions runs PMD static analysis on every push and pull request to `main`. A scratch-org deploy + test job runs when the `SFDX_AUTH_URL` repository secret is set (see [.github/workflows/ci.yml](.github/workflows/ci.yml) for the authoring details).

To enable scratch-org CI:

1. Authorize a DevHub locally: `sf org login web --set-default-dev-hub`
2. Generate an SFDX auth URL: `sf org display --target-org <DevHub> --verbose --json` and copy the `sfdxAuthUrl` value.
3. Add it as a repository secret named `SFDX_AUTH_URL` under Settings → Secrets and variables → Actions.

Note: the scratch org definition (`config/project-scratch-def.json`) requests Industries CPQ + RLM + CLM features. Without these, the deploy fails before any test runs.

## Validation deploy

Before merging anything to `main`, validate the change against the org without actually committing it:

```bash
sf project deploy validate --source-dir force-app --test-level RunLocalTests
```

The `validate` flag runs the deployment and tests inside a transaction that is rolled back at the end, so the org is unchanged regardless of the result.

## Pull request checklist

Even on solo work, these should be true at merge time:

- [ ] All tests pass (`sf apex run test --test-level RunLocalTests`)
- [ ] Coverage stays at 85%+ on every custom class (100% target on new code)
- [ ] PMD lint produces no new violations
- [ ] Any new class has its `*Test.cls` companion in `force-app-tests/`
- [ ] Any new SOQL is in a Selector class, not inline
- [ ] Any new external integration follows the Mule vs Apex decision matrix
- [ ] ApexDoc headers are in place on new classes/methods
- [ ] Custom Setting credentials script (if any) is in `.gitignore`
- [ ] Memory file (`memory/<topic>.md`) updated if the architectural decision is non-obvious
- [ ] README updated if the public surface changed

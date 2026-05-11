# ADR-004: Six-Package SFDX Layout for Separation of Concerns

## Status

**Accepted**

## Date

2026-04-30

## Author

Mustafa Aksu

## Context

The default Salesforce DX project structure places all Apex classes in a single directory: `force-app/main/default/classes/`. For small projects (≤20 classes) this is fine. TechnoStore grew rapidly:

- ~14 Apex service classes (Stripe, Sendcloud, DocuSign, JIRA, Notion, branded PDFs, tax adapter)
- ~8 trigger handlers + Platform Event subscribers
- ~6 Visualforce controllers + REST resources
- ~6 `@InvocableMethod` classes for Flow
- Plus test classes for each of the above

A single `force-app/main/default/classes/` directory with 40+ files mixes responsibilities. Three problems emerge:

1. **Circular dependency risk** — a Controller class casually imports a Service class which casually imports another Controller. Without a directory boundary, the dependency direction is invisible until a compilation error surfaces it.
2. **Targeted deploy difficulty** — `sf project deploy start --source-dir force-app/main/default/classes/` deploys all classes regardless of which actually changed; impossible to deploy "just the new Notion service" for a quick hotfix.
3. **Test coverage queries get noisy** — test classes mixed with production classes makes `SELECT ApexCodeCoverage` queries return rows that include vendored code (Kevin O'Hara `TriggerHandler.cls`) and test helpers, requiring per-file filtering.
4. **Onboarding friction** — a new engineer asking "where do I add a new external API callout?" gets the answer "look in the 40-file classes/ directory" rather than "look in force-app-services/".

Salesforce DX supports multiple `packageDirectories` in `sfdx-project.json`. This pattern is familiar to engineers from multi-module Maven, multi-project Gradle, and Spring Boot multi-module layouts.

## Decision

Restructure the SFDX project into **six `packageDirectories`** following the canonical four-layer Apex architecture extended with two project-specific layers:

| Directory | Purpose |
|-----------|---------|
| `force-app/` (default) | sObjects, fields, layouts, flows, permission sets, page layouts, Site definitions, eSignatureConfigs, approvalProcesses, quickActions, named credentials, static resources |
| `force-app-controllers/` | Visualforce controllers + `@RestResource` classes — the request/response cycle owners |
| `force-app-services/` | External API callout services — Stripe, Sendcloud, DocuSign, JIRA, Notion, tax adapter, branded PDF generation |
| `force-app-handlers/` | TriggerHandler base + per-sObject trigger handlers + Platform Event subscribers |
| `force-app-actions/` | `@InvocableMethod` classes exposed to Lightning Flow |
| `force-app-tests/` | All test classes (CI test-only deploys possible) |

`sfdx-project.json` declares all six with the first marked `default: true`. The default flag determines where `sf project retrieve` writes by default; explicit `--source-dir` flags control deploys.

Standing rules in `CONTRIBUTING.md`:

- New code goes in the directory matching its **architectural role**, not its **feature**.
- A Service may call a Selector, never the inverse.
- A Handler may call a Service, never the inverse.
- A Controller may call a Service or Action, never a Handler directly.
- Tests live in `force-app-tests/` regardless of which production package they test.

## Consequences

### Positive

- **Clear architectural ownership** — "where should this new Apex class go?" has a deterministic answer.
- **Targeted deploys** — `sf project deploy start --source-dir force-app-services/NotionPublishService.cls` deploys just one class for a hotfix.
- **CI tests can deploy `force-app-tests/` independently** if test-only changes need to ship without touching production code.
- **Coverage queries cleaner** — `WHERE ApexClass.NamespacePrefix = NULL AND ApexClass.Name NOT LIKE '%Test'` over the `force-app-services/` directory specifically returns just production service classes.
- **Visible signal to recruiters + reviewers** — `sfdx-project.json` opened during a code review immediately shows architectural maturity. The directory tree alone tells the story.
- **Familiar pattern** — engineers from Spring Boot multi-module / Maven multi-project / Gradle composite-build backgrounds recognize this layout instantly.

### Negative / Trade-offs

- **More `--source-dir` flags in CLI commands** — full deploys now require six `--source-dir` arguments. Mitigated by a wrapper script (`scripts/deploy_all.sh`) and CI handling this once.
- **Slight overhead in `sf project retrieve`** — retrieving a single new class via Salesforce Setup → Object Manager edits requires choosing the correct package directory; the CLI defaults to `force-app/` and re-mapping is manual.
- **MDAPI consumers** that expect a single source tree may need adapter conversion (rare in modern DX-only workflows).
- **Cross-package references work but are discouraged** — a Helper in `force-app-services/` calling a class in `force-app-controllers/` is legal Apex but architecturally backwards. Discipline required.

## Alternatives Considered

### Alternative A — Single `force-app/` with subfolders by feature

Rejected because:
- Subfolders inside `force-app/main/default/classes/` are flattened by SFDX — Salesforce metadata API doesn't honor the folder hierarchy. The visual structure is illusory; SFDX deploys + retrieves treat it as flat.
- Cannot target a subfolder with `--source-dir`.

### Alternative B — Three packages (force-app, force-app-tests, force-app-mulesoft-bridge)

Considered as a minimal split. Rejected because:
- Doesn't separate Controllers from Services from Handlers — the high-value architectural distinction.
- "force-app-mulesoft-bridge" is a feature-named directory; the project standard is role-named (Controllers, Services, Handlers, Actions).

### Alternative C — Salesforce Unlocked Packages (true packaging)

Considered for the medium term. Currently rejected because:
- Unlocked Packages require Dev Hub + namespace + version management overhead.
- Cross-package dependencies are explicit (package1 depends on package2) which adds friction during demo iteration where classes move between packages.
- Suitable for a v2.0 production hardening phase, not the current demo phase.
- The six-package SFDX layout is a stepping stone that doesn't lock us out of moving to Unlocked Packages later.

### Alternative D — Default Salesforce CRMA template (single force-app)

Rejected because (see Context):
- 40+ Apex classes in one directory becomes unmanageable.
- No targeted deploy story.
- No architectural-role signal in the directory tree.

## Migration notes

When refactoring an existing single-package SFDX project into six packages:

1. Create the four new directories: `force-app-controllers/main/default/classes/` etc.
2. Update `sfdx-project.json` with the new `packageDirectories` array.
3. Move each `.cls` + `.cls-meta.xml` pair into the appropriate target directory via `sf project retrieve` after relocation OR via direct `git mv`.
4. Update `.github/workflows/ci.yml` PMD scan paths to include all six directories.
5. Update any deploy scripts (`scripts/deploy_all.sh`) to use multiple `--source-dir` flags.
6. Validate via dry-run: `sf project deploy validate --source-dir force-app --source-dir force-app-controllers ... --test-level RunLocalTests`.

The TechnoStore migration from single-package to six-package took ~2 hours including verification.

## References

- **Memory**: `enterprise_apex_layout.md` (5-package layout + framework adoption — pre-tests-package; the tests package was added later, making it 6)
- **Notion portfolio entry**: 44 — "Enterprise Apex Layout — 5 sfdx Package Directories"
- **Code**: `sfdx-project.json` (root)
- **Related ADRs**: ADR-005 (Kevin O'Hara TriggerHandler — lives in `force-app-handlers/`)
- **Salesforce docs**: [Multiple Package Directories](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_mpd_setup.htm)

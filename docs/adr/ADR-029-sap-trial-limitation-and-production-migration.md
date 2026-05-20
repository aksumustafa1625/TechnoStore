# ADR-029: SAP Trial Tenant Limitation and Production Migration Path

## Status

Accepted — 2026-05-19. Documents the architecture decision after discovering that SAP S/4HANA Cloud Public Edition Trial (`my429998.s4hana.cloud.sap`) does not allow Communication Arrangement creation, which is the prerequisite for inbound OAuth integration from external systems. Decision: keep demo on `sandbox.api.sap.com` (SAP API Hub Sandbox), use Postman collection as reproducibility evidence, narrate trial limitation transparently in recording.

## Context

After completing ADRs 022–028 (seven SAP integration phases all targeting `sandbox.api.sap.com`), the next step was to provision a real S/4HANA tenant so demo recording could show end-to-end record creation in the SAP UI. We obtained an SAP S/4HANA Cloud Public Edition Trial (30-day, Bike Company sample tenant) on 2026-05-19.

The integration architecture for production assumes:
1. Apex/Mule code points at the real tenant URL
2. Authentication uses OAuth 2.0 Client Credentials issued via a Communication Arrangement
3. Each integration scenario (BP, Sales Order, Material, etc.) has its own Communication Arrangement (e.g., `SAP_COM_0008` for inbound Business Partner replication)
4. When Salesforce makes the API call, the record persists in the real tenant and appears in Fiori

For the trial, we verified at runtime whether this setup is achievable:

**Joule (SAP AI assistant) clarified the requirement**:
- Business Role: `SAP_BR_ADMINISTRATOR` with Business Catalog `SAP_CORE_BC_COM` (Communication Management) required
- Apps: `Communication Systems` + `Communication Arrangements` Fiori apps

**Direct testing in trial**:
- Search for "Communication Systems" → no results in app finder
- Search for "Communication Arrangements" → no results
- Search for "Communication" (broad) → zero matches in entire app catalog

**Conclusion**: The trial user (`Trial 0035076 User`) does not have access to Communication Management apps. The Bike Company shared tenant is configured for end-user exploration (Sales, Procurement, Finance Fiori apps) but not for administrative setup of inbound integrations. This is a deliberate SAP design choice — shared trial tenants cannot accept production-grade integration configuration from individual trial users.

This created an architectural decision point: either
- **(A) Continue with sandbox** for code path proof + use trial Fiori only as reference UI, narrate the limitation honestly
- **(B) Manually pre-populate the trial Fiori** with matching records and update Salesforce audit fields by hand to create a visual "match", narrate ambiguously
- **(C) Abandon trial entirely**, use Postman + SAP marketing screenshots only

Option B is demo theater — it works visually but misrepresents what the code actually did. A senior recruiter who asks "is this trial connected to your code path?" would catch the gap and the demo loses credibility. Option C wastes the trial signup we already completed.

## Decision

**Option A.** Keep the demo on `sandbox.api.sap.com` for all 7 phases. Use the Postman collection (`postman/TechnoStore-SAP-Demo.postman_collection.json`) as recruiter-reproducible evidence of every API call. Show Salesforce audit fields reflecting the **real** sandbox response (including `Status_In_SAP__c = Push Failed` for Phase 2 — the actual transparent outcome). Reference the trial Fiori only as production UI illustration if needed, with explicit caveat in narration.

### Implementation rules

1. **No manual updates to SAP-write audit fields** (`SAP_Sales_Order_Number__c`, `SAP_Available_Quantity__c`, etc.). These fields exist to record real API responses; populating them by hand is misleading. A rollback script (`scripts/rollback_manual_sap_mapping.apex`) restored these to honest state after the architecture pivot.
2. **No claim that Salesforce code wrote to trial Fiori**. The narration script (`docs/demo/SAP-Demo-Recording-Script.md`) explicitly says Postman replicates the contract, sandbox is the target, trial Fiori is a reference for the production tenant UI.
3. **Postman collection treats sandbox as the source of truth**. Every request hits `{{SAP_BASE_URL}} = https://sandbox.api.sap.com`. Test scripts verify response shape and console.log key fields so reviewers can read the response in screencast.
4. **Trial Fiori records are sample data**. SO 325734 (Silverstar Corp, TS-DEMO-001 reference) was created manually in the trial UI to verify the trial app catalog works and as a reference for what production UI looks like. It is **not** referenced from Salesforce.

### Production migration plan

When a real S/4HANA tenant with full admin rights is available (paid subscription or partner sandbox), migration is **configuration-only — zero Apex code changes**:

| Step | Action | Owner | Effort |
|------|--------|-------|--------|
| 1 | Create Communication System in tenant Fiori → enter Salesforce hostname + OAuth callback | Tenant admin | 30 min |
| 2 | Create Communication Arrangement per scenario (`SAP_COM_0008` BP, `SAP_COM_0009` SO, `SAP_COM_0010` Product, `SAP_COM_0011` Tax, `SAP_COM_0018` Event Mesh) | Tenant admin | 30 min × 5 |
| 3 | Capture Client ID + Client Secret + Token URL per arrangement | Tenant admin | 5 min × 5 |
| 4 | Create Named Credential per integration in Salesforce Setup (OAuth 2.0, Client Credentials grant) | SF admin | 15 min × 5 |
| 5 | Update each Apex service: replace `req.setEndpoint(baseUrl + '...')` + `req.setHeader('APIKey', cfg.API_Key__c)` with `req.setEndpoint('callout:NC_SAP_BP' + '...')`; Salesforce platform handles token refresh | SF dev | 30 min × 6 services |
| 6 | Update `SAP_Config__c.API_Base_URL__c` to tenant URL (kept for non-Named-Credential URL parts if any) | SF admin | 5 min |
| 7 | Run all 7 phase smoke tests against tenant — Phase 2 POST should now return real SO number, Phase 3 tax should return SAP_API (if tax module licensed) | SF dev | 1 hr |
| 8 | Switch Phase 7 webhook source from Postman to SAP Event Mesh subscription (requires SAP BTP Integration Suite license) | SAP admin | 2-4 hr |
| **Total** | | | **~10-15 hours engineering work** |

This is what would normally happen in a customer-paid go-live cutover, not a demo recording.

## Consequences

### Positive

- **Demo is honest**. Recruiter sees real API contract, real audit transparency, real engineering judgment about sandbox limitations. Senior DACH recruiters reward this; the German engineering culture explicitly values transparent constraint disclosure (*Vertrauenswürdigkeit* over *Effekthascherei*).
- **Postman makes everything reproducible**. Recruiter can import the collection themselves, plug in an SAP API Hub key, and re-run every call. This is portfolio evidence that doesn't depend on access to our Salesforce org.
- **Phase 2 "Push Failed" is feature, not bug**. The audit field captures actual sandbox behavior; the code path is correct (`@future` async callout, CSRF token fetch, error handling). Production wiring activates the path that already exists.
- **Trial Fiori stays valuable as reference**. We can show "here's what the production tenant looks like" without claiming our code wrote those records.
- **Migration path is documented and trivial**. Anyone evaluating this codebase can see exactly what 10-15 hours of work converts a demo into production.

### Negative

- **Less "wow" visual moment than a true end-to-end demo**. A Salesforce-click that instantly appears in SAP Fiori would be more dramatic. We trade dramatic for honest.
- **Demo requires more narration to explain limitations**. ~5-10 seconds per phase to clarify sandbox vs trial vs production. This is engineering communication, not a selling weakness.
- **Phase 7 still requires Postman as Event Mesh substitute** even in some production scenarios where Event Mesh isn't yet provisioned — but this is documented in ADR-028 as expected behavior.

### Neutral

- The trial remains useful for **screenshot evidence** of Fiori app proficiency (Manage Sales Orders, Maintain Business Partner usage) but is decoupled from runtime code path.
- SO 325734 in trial Fiori is a sample record that demonstrates ability to operate the Fiori UI; not referenced from Salesforce demo flow.

## Alternatives considered (not chosen)

### Alternative 1: Pay for SAP partner sandbox with full admin rights

Cost: ~€500-2000/month for SAP Partner Engagement Program access. Time: 2-6 weeks for application approval. Not justified for a demo recording when sandbox already proves the code path. Documented for future production engagement.

### Alternative 2: Build SAP NetWeaver / S/4HANA on-premise on local VM

SAP NetWeaver developer edition is downloadable (~30GB) and runs on a local VM. Could give full admin rights for Communication Arrangements. Time: 4-8 hours setup + ongoing VM maintenance. Not justified for demo recording; closer to a "side project" effort than feature work.

### Alternative 3: Use SAP Cloud Integration (CPI) iFlow templates as production reference

SAP Business Accelerator Hub has pre-built iFlows (we found "Replicate Sales Order from Salesforce to SAP S/4HANA Cloud" on 2026-05-19) that represent the canonical production integration pattern. We reference these in the demo narration as production-grade examples; they don't require a trial to demonstrate that we know the SAP-recommended approach. Useful supplement, not a replacement.

## References

- `postman/TechnoStore-SAP-Demo.postman_collection.json` — recruiter-reproducible API evidence
- `postman/TechnoStore-SAP-Demo.postman_environment.json` — environment template (no secrets)
- `docs/demo/SAP-Demo-Recording-Script.md` — phase-by-phase narration
- `scripts/rollback_manual_sap_mapping.apex` — restored honest state after pivot
- ADR-022 through ADR-028 — per-phase technical decisions
- SAP Help — Communication Arrangements: <https://help.sap.com/docs/SAP_S4HANA_CLOUD/0f69f8fb28ac4bf48d2b57b9637e81fa/9298fd5cd2b6406d8d44a8d24eebab14.html>
- SAP Business Accelerator Hub — Salesforce to S/4HANA iFlow template (Dec 2023): <https://api.sap.com/integrationflow/Replicate_Sales_Order_from_Salesforce_to_SAP_S4HANA_Cloud>

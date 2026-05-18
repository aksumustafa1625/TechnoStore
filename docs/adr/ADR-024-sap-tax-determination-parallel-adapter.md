# ADR-024: SAP Tax Determination — Parallel Adapter to the Native commercetax Chain

## Status

Accepted — implemented 2026-05-18 in SAP Sprint Phase 3. SapTaxCalculationService + four new Invoice fields (SAP_Tax_Amount, SAP_Tax_Rate, SAP_Tax_Calculated_At, Tax_Engine_Used) deployed and verified end-to-end.

## Context

ADR-009 documented the choice for tax handling: Quote stage uses formula fields showing estimated VAT; Invoice stage uses the `commercetax.TaxEngineAdapter` chain that comes with Industries CPQ / Revenue Cloud. That covers the demo path with no external dependencies.

ADR-015 documented the production target: tax authority moves out of Salesforce to a dedicated tax engine — SAP FI/SD, Avalara, Vertex, or Oracle Tax. The reasons (DACH e-invoicing compliance §14 UStG + ZUGFeRD + XRechnung format, multi-country VAT rules, exemption handling, jurisdiction precision) are the same reasons mid-market enterprises don't keep tax logic in their CRM.

The question for the SAP sprint: build the SAP parallel adapter NOW so the production migration path is proven, even though the demo's native chain stays authoritative for now.

Two operational constraints shape it:

1. **SAP API Hub Sandbox license-gates the tax module.** Trying `/s4hanacloud/sap/opu/odata/sap/API_DETERMINE_TAX_SRV/$metadata` returns HTTP 403. Same for `API_TAX_CALCULATION`. The endpoints exist in S/4HANA but aren't included in the free trial sandbox. Full S/4HANA licenses unlock them. Demo can't actually call the real SAP tax API.

2. **Tax rules are complex** — full SAP tax determination considers customer tax registration status, product tax category, ship-to jurisdiction, exemption certificates, reverse-charge rules, intra-EU vs export. A complete client-side replica would be a multi-month build. The pragmatic SF-side path is "call the engine, get a number back" not "rebuild the engine."

The shape that fits both constraints: a service that **tries SAP first** and **falls back to a deterministic country-based rate table** when SAP is unavailable. The table is enough for demo + low-complexity production scenarios; the SAP path is the production-readiness verification. Same audit fields on Invoice either way.

## Decision

`SapTaxCalculationService.calculateForInvoice` is an `@InvocableMethod` that takes an Invoice Id, computes tax, writes results back to the Invoice. Two-tier resolution:

### Tier 1 — Try SAP API

`trySapTaxApi` builds the URL `{baseUrl}/s4hanacloud/sap/opu/odata/sap/API_DETERMINE_TAX_SRV/Tax`, sends GET with APIKey header and Accept-Encoding: identity (the SAP API Hub gzip workaround). On 200, parses `d.results[0].TaxRate` and returns the percent. On 403 / 404 / 5xx / exception, returns null to signal fallback.

In production with full licensing the call succeeds and returns the SAP-authoritative rate. In sandbox the call 403s every time; the service catches it cleanly and falls through.

### Tier 2 — Country-based fallback table

`resolveFallbackRate` maps the Account's BillingCountry to a hardcoded standard VAT rate:

| Country code / name | Rate |
|---|---|
| DE / Germany | 19.00% |
| AT / Austria | 20.00% |
| CH / Switzerland | 7.70% |
| NL / Netherlands | 21.00% |
| FR / France | 20.00% |
| IT / Italy | 22.00% |
| ES / Spain | 21.00% |
| BE / Belgium | 21.00% |
| GB / UK | 20.00% |
| US / USA | 0.00% (sales tax is per-state; SAP resolves via tax jurisdiction code in production) |
| (unknown / blank) | DEFAULT_RATE = 19.00% (Germany default for the DACH demo profile) |

These are the **standard** VAT rates for general products. Reduced rates (DE 7% for books, food, certain services), zero rates (intra-EU B2B reverse charge, exports), and exemptions are NOT in the fallback table. They require SAP or a tax engine — that's the gap this ADR explicitly documents.

### Writeback

Either way (SAP API or fallback), the service writes:

- `Invoice.SAP_Tax_Rate__c` — the rate percent (19.00, 20.00, etc.)
- `Invoice.SAP_Tax_Amount__c` — calculated as `TotalAmount * rate / 100` rounded to 2 decimals
- `Invoice.SAP_Tax_Calculated_At__c` — timestamp
- `Invoice.Tax_Engine_Used__c` — `SAP_API` if Tier 1 succeeded, `SAP_FALLBACK_TABLE` otherwise

The Tax_Engine_Used__c picklist is the transparency signal. Production-licensed instances should always show `SAP_API`. Sandbox demos show `SAP_FALLBACK_TABLE` and the storyline acknowledges this honestly.

### Coexistence with the native commercetax chain

The existing `commercetax.TaxEngineAdapter` chain on Invoice line items is NOT replaced. It still runs at Invoice generation, populates the standard Tax fields. This ADR's service writes to the SAP_Tax_* fields in parallel. Audit dashboards can compare the two readings to verify production readiness; if they diverge, that's a flag.

A future Custom Setting flag `Tax_Engine_Source__c` could switch authority from the native chain to the SAP path (per ADR-015's production externalisation pattern). Not built yet because the SAP API doesn't actually return numbers in sandbox; nothing to switch authority to.

## Consequences

### Positive

- **Production-ready service contract.** When the org gets a full SAP license, the only change is the SAP endpoint starts returning 200 instead of 403; no SF-side code changes needed.
- **Transparent sandbox behavior.** `Tax_Engine_Used__c = SAP_FALLBACK_TABLE` makes it obvious in every Invoice record (and reportable in dashboards) that the demo isn't actually hitting SAP. No "is this real?" ambiguity for the recruiter.
- **Two readings on every Invoice** — native commercetax chain AND SAP parallel — let auditors compare without picking one as authoritative yet.
- **Fallback table is fast.** Country lookup is in-memory, no callout overhead when SAP is the trustworthy source.
- **Recruiter signal: "I know SAP tax licensing is layered."** The sandbox 403 / fallback transparency is a real-world scenario in DACH Mittelstand projects where trial sandboxes are common before full procurement. Acknowledging this honestly beats pretending sandbox = production.

### Negative

- **Fallback table is country-only.** Real DACH B2B has reduced rates (DE 7% for books / food / culture), zero rates (intra-EU B2B reverse charge), exemptions (intra-community deliveries with valid USt-IdNr). Demo cases miss these. Production with real SAP catches them; fallback can't.
- **Hardcoded rate table is brittle to rate changes.** When a country changes its VAT rate (rare but happens — e.g., Germany temporarily 16% in COVID), the fallback table needs a code update. Production with SAP gets rate changes via SAP's standard tax-code maintenance. Mitigation: this is the fallback, not the authoritative source.
- **Two systems of record for tax during the parallel-running phase.** Native chain on line items, SAP_Tax_* on Invoice header. They should agree (within rounding) for DACH standard rates; if they don't, that's the kind of drift Integration Health dashboard should flag (future enhancement).
- **No reduced-rate routing without product classification data.** To return 7% for German books, the service would need to know the product belongs to the "books" category. Product2 doesn't carry that today (would need a `Tax_Category__c` field). Out of scope for this ADR; planned for the Material Master sync (ADR-026) which can pull SAP's tax categorisation.

### Future state

- **Switch authority via Custom Setting** (post-licensing): a `Tax_Engine_Source__c` Custom Setting picklist (Native / SAP / Both) drives whether the Invoice's standard Tax fields read from commercetax or from the SAP path. The two-tier internal resolution stays the same; only the "which engine writes authoritatively" question changes.
- **Reduced-rate routing** via SAP product tax category sync (ADR-026 extends Material Master sync to pull SAP tax category onto Product2; tax service then consults it).
- **Multi-line tax** — current service treats Invoice as a single TotalAmount × rate. Real invoices have per-line tax codes that differ (e.g., one line of services 19%, one line of books 7%). Production migration extends the service to iterate line items.
- **EU intra-community deliveries** — when shipping cross-border B2B with both parties tax-registered, the rate is 0% with reverse charge. Requires customer VAT ID lookup (USt-IdNr in DE). Add `Account.VAT_Registration_Number__c` + check `BillingCountry != ShippingCountry`. Future ADR.

## Alternatives Considered

1. **Skip the SAP parallel; keep native chain as sole tax authority.** Rejected — demo can't credibly claim production-readiness for DACH compliance without showing how tax migrates off the CRM. The parallel adapter is the SAP-readiness proof.
2. **Use Avalara instead of SAP.** Considered. Avalara is best-in-class for sales tax (especially US per-state) but DACH Mittelstand audiences expect SAP since they probably already run SAP. SAP is the natural fit; Avalara is a credible alternative documented in ADR-015 production externalisation roadmap.
3. **Build the full tax engine in Apex.** Rejected on cost — that's a months-long product, not an ADR. The parallel-adapter-with-fallback path lands the production pattern in 1-2 hours.
4. **Mock SAP responses for demo.** Considered but rejected — mocking obscures the real integration. The "sandbox 403's → fallback fires" narrative is more credible than "look, SAP says 19%! (it's a mock)".
5. **Run the service from an Invoice trigger** rather than @InvocableMethod. Defer — the demo's Invoice generation already has a complex chain (formula tax fields, OrderItem-driven tax adapter, branded PDF render); adding another trigger node risks instability. The @InvocableMethod can be called from Flow or anonymous Apex when needed; production migration will wire it into the existing Invoice creation path.

## Related Decisions

- ADR-009 (Quote tax formula / Invoice tax adapter) — the native chain this ADR runs in parallel to.
- ADR-013 (Webhook idempotency + Integration_Error__c) — the audit substrate for SAP API failures, used here when the Tier 1 SAP call errors out.
- ADR-015 (Production Externalization Strategy) — the production-target tax row that this ADR is the path toward.
- ADR-022 (SAP MM ATP Integration) — sibling sprint phase. Same pattern (try SAP, fall back transparently), different domain.
- ADR-026 (SAP Material Master Sync) — will extend Product2 with a tax category field that future versions of this service can consult for reduced-rate routing.
- Future ADR-???: Multi-line tax + intra-community deliveries.

# Sister Consult — Quote TaxCalculationFailed: Decision Table Lookup Fails Even After Sync + Rebuild

**Date:** 2026-06-27
**Asker:** TechnoStore demo org owner
**Org:** TechnoStore — Salesforce Developer Edition with Industries Sales Cloud + Revenue Lifecycle Management (RLM)
**Org ID:** `00Dxx0000000000XXX`
**API Version:** 62.0
**Stakes:** TechnoStore is the live demo org that took 3-5 months to build. Quote→Order flow was working BEFORE Configra was installed today. Now even after uninstalling Configra and configuring tax data, the same pink error persists. This blocks the entire E2E Q2C demo (Quote → Order → Invoice → Stripe). Need to restore working state.

---

## TL;DR

Pink banner on every Quote: **"We couldn't process your request. Learn more in the Revenue Transaction Error Logs."**

Underlying error (from `RevenueTransactionErrorLog`):
```
Category: QuoteTaxCalculationFailure
Decision Table ID: 0lDaj000000DanFEAS (StandardTax)
Error: Exception while fetching matching records from Decision Table ID: 0lDaj000000DanFEAS,
       error: Decision Table lookup failed for request at index 0
```

Critically: **Quote.Tax field DOES populate correctly (€66.31 = €349 × 19%)** via formula fields per [ADR-009](../adr/ADR-009-quote-tax-formula-invoice-tax-adapter.md). The architectural design is that RLM Tax Engine should NOT run on Quote — Quote tax is computed declaratively via formula fields, and only Invoice tax invokes `commercetax.TaxEngineAdapter`. Yet RLM is invoking the StandardTax Decision Table on Quote save, and the lookup fails.

We need to either:
1. Make the StandardTax Decision Table lookup succeed (populate it correctly)
2. OR prevent RLM Pricing Procedure from invoking the tax step on Quote
3. OR identify why the original setup worked (Quote tax never failed before today)

---

## Architectural Context (ADR-009 — accepted 2026-05-03)

**Quote-stage tax:** 4 formula fields compute 19% German VAT declaratively.

| Object | Field | Formula |
|--------|-------|---------|
| QuoteLineItem | `Tax_Rate__c` | `0.19` (constant) |
| QuoteLineItem | `Tax_Amount__c` | `UnitPrice * Quantity * Tax_Rate__c` |
| Quote | `Total_Tax__c` | Roll-Up Sum of QLI Tax_Amount__c |
| Quote | `Total_With_VAT__c` | `TotalPrice + Total_Tax__c` |

**Invoice-stage tax:** `commercetax.TaxEngineAdapter` runs against per-address geocoded data, producing legally compliant InvoiceLine tax amounts.

**Why this split:** Quote tax is non-binding estimate (sales rep narrative: "€1,499 + €284.81 VAT = €1,783.81 gross"). Invoice tax is legally binding. Salesforce platform treats them as different lifecycle stages.

**Implication:** The org was deliberately built so that RLM's Quote pricing pipeline does NOT call tax adapters. Quote.Tax populates from formula fields without any Decision Table involvement.

So **the Decision Table lookup that's currently failing was never supposed to happen on Quote save**. Something is now invoking it.

---

## Timeline — What Changed Today

### Before today (working state)
- Quote→Order flow worked end-to-end
- Quote.Tax displayed correctly via formula fields
- No pink "We couldn't process your request" banner
- CalculationStatus likely `CompletedWithPricing` or similar success state
- StandardTax Decision Table either: (a) had empty dataset but was never invoked on Quote, OR (b) was bypassed entirely in the Pricing Procedure

### Today, in order:
1. **Installed Configra Managed v1.0.0-3** (managed 2GP, namespace `configra`)
2. Tested Configra on Mueller GmbH Quote — created 3 placeholder Product2 QLIs
3. Configra's `ConfigraQliInlineEditGuard` trigger fired during RLM Reprice, calling `addError()` on QLI before-update
4. This rolled back the RLM transaction → `CalculationStatus = TaxCalculationFailed`
5. **Patched Configra → built v1.0.0-6** (default-OFF guard + multi-layer defense)
6. Couldn't upgrade Beta packages — had to **uninstall v1.0.0-3 first**, then install v1.0.0-6
7. Tested v1.0.0-6 — confirmed guard no longer interferes, but pink error persisted
8. **Uninstalled Configra v1.0.0-6 entirely** (user decision: stop touching TechnoStore with Configra)
9. **Deleted all 10 DACH test data** (Accounts, Contacts, Opps, Quotes, QLIs)
10. Created fresh Account → Opp → Quote → added 3 products via Browse Catalog
11. **Same pink error appears.** RTE Log shows StandardTax lookup failure.

The pink error PERSISTS after Configra is fully removed. So the trigger fix didn't address the actual issue — and the actual issue may predate Configra.

---

## What We've Already Done to Fix It

### Tax Master Data Setup (today, in TechnoStore)
1. Created **TaxRate** (`TR-00000004`): TaxCode `DE_VAT_19`, Rate 19.00%, RateUsageType `RevCloud`, ApplicationBasis `Net`
2. Created new **TaxTreatment** "TechStore VAT 19 v2": Status `Active`, `ShouldUseTaxTreatmentItems = true`, linked to existing `TaxPolicy` "Tax Policy for LE" (`1Tpaj000000IKTJCA4`)
3. Created **91 TaxTreatmentItem** records — one per active Product2, all with TaxCode `DE_VAT_19`
4. Updated **72 Product2** records — assigned `TaxPolicyId = '1Tpaj000000IKTJCA4'` (Tax Policy for LE)
5. **Salesforce Pricing Setup → Sync** clicked
6. **Product Discovery Settings → Rebuild Index** clicked

### Diagnostics (verified)
```sql
SELECT COUNT() FROM TaxRate          → 1
SELECT COUNT() FROM TaxTreatment     → 2 (original + new)
SELECT COUNT() FROM TaxTreatmentItem → 91
SELECT COUNT() FROM TaxEngineProvider → 1
SELECT COUNT() FROM TaxPolicy        → 1
SELECT COUNT() FROM GeoCountry       → 0  ⚠ EMPTY
```

### Pricing Procedure
Default Pricing Procedure shown in Salesforce Pricing Setup: **"Revenue Management Default Pricing Procedure V1"** (OOTB Salesforce). This procedure likely includes a tax step that calls the StandardTax Decision Table.

### Quote State (after all setup)
- Quote.Tax = **€66.31** (correctly calculated: €349 × 19% via formula field)
- Quote.TotalPrice = **€349.00**
- Quote.GrandTotal = **€415.31**
- Quote.CalculationStatus = **`TaxCalculationFailed`** ← still failed despite Tax field populating
- Pink "We couldn't process your request" banner still showing
- Visible UI confirmation messages: "Taxes were updated", "Quote was updated", "Prices refreshed and configuration was validated" — yet status remains TaxCalculationFailed

---

## The Exact Error

From `RevenueTransactionErrorLog` — most recent entry (2026-06-27 20:04:21):

```
Id:               0nYaj000002vh77EAA
Category:         QuoteTaxCalculationFailure
Severity:         null
ErrorMessage:     Exception while fetching matching records from Decision Table 
                  ID: 0lDaj000000DanFEAS, error: Decision Table lookup failed for 
                  request at index 0 for Decision Table ID: 0lDaj000000DanFEAS
PrimaryRecordId:  0Q0aj000002ghsDCAQ (the Quote)
```

### Decision Table Details
- **ID:** `0lDaj000000DanFEAS`
- **Name:** StandardTax (presumed — this is the standard RLM tax decision table)
- **Dataset Link ID:** `0lXaj000000ChUDEA0` (StandardTax_Default)
- **Status:** Active (Synced via Pricing Setup)

We have NOT inspected the Decision Table rows directly (no straightforward Tooling API path to the dataset rows). Possibly empty or schema-mismatched.

---

## Questions for Sister AIs (Priority Order)

### Q1 (Most important) — How do we make the Decision Table lookup succeed?

Specifically:
- What input parameters does the StandardTax Decision Table expect?
- Is it keyed on `TaxCode`, `GeoCountryId`, `LegalEntityId`, `Product.TaxPolicyId`, or some combination?
- We have a TaxRate row with TaxCode `DE_VAT_19`, a TaxTreatment with 91 items each with TaxCode `DE_VAT_19`. Is `TaxCode` the join key?
- Is the absence of `GeoCountry` records (`SELECT COUNT() FROM GeoCountry → 0`) the actual problem? The TaxRate has no GeoCountryId set.
- Do we need to populate `GeoCountry` table first via some Salesforce admin action?

### Q2 — Why was this working before, with the same formula-field tax design?

Per ADR-009, RLM Quote was intentionally NOT supposed to invoke any tax adapter. Yet the error log shows Decision Table lookups happening. Possibilities:

(a) The Decision Table lookup was ALWAYS failing silently before, just with a different `Severity` (it shows `null` now), and we just never noticed in the working state.

(b) The Pricing Procedure was previously a CUSTOM one that skipped the tax step, but got reset to OOTB "Revenue Management Default Pricing Procedure V1" today during Configra install/uninstall churn.

(c) Some setting or flag was deactivated that bypassed Quote tax calc.

Which is most likely? How do we verify?

### Q3 — Can we EXCISE the tax step from the Pricing Procedure?

If the design says "no RLM tax on Quote, only formula fields", then we should be able to either:
- Edit the Pricing Procedure (Expression Set) to remove the tax decision step
- Or create a custom Pricing Procedure that mirrors the OOTB except without the tax step
- Or configure RLM to skip tax during Quote calculation (some global setting?)

What's the right approach? Is there a documented way to disable tax during Quote calc in RLM?

### Q4 — Should we just IGNORE the pink error?

Quote.Tax is populating correctly (€66.31). The visible total is correct (€415.31 gross). The only ill effect we've observed is that **Create Order fails** with "calculation status of the quote is invalid".

Is there a way to:
- Bypass the CalculationStatus check on Create Order?
- Force-set CalculationStatus to a success state (we tried — it's not writeable via standard or Tooling API)?
- Use a different Order creation path that doesn't check status (manual Apex DML)?

### Q5 — Is there a way to populate the Decision Table dataset rows programmatically?

The Decision Table `0lDaj000000DanFEAS` lookup is failing because (presumably) no rows match the lookup criteria. Can we:
- Add rows to the dataset via Tooling API / Metadata API?
- Trigger a "rebuild" specifically on the StandardTax decision table (separate from Product Discovery Rebuild)?
- Manually populate it via Setup UI?

### Q6 — Git rollback option: is the Pricing Procedure metadata in Git?

The TechnoStore Git repo has all metadata files. If the Pricing Procedure was reset today by something Configra did, can we deploy the OLDER version from Git to restore the working state? Or is the Pricing Procedure data (rather than metadata) in the org, and Git won't help?

### Q7 — Hidden risks I may be missing

Be tough. What am I not seeing that a Salesforce expert would catch immediately? The pattern of "Decision Table lookup failed" with a `null` Severity feels like a configuration issue that should be obvious to someone familiar with RLM internals.

---

## Decision Options I'm Currently Weighing

### Option A — Find the exact Decision Table lookup contract + populate rows
- Risk: Tooling API for Decision Table dataset rows may not exist for sObject CMTs/Sites
- Time: 1-2 days investigation
- Reward: Clean fix, RLM works as designed

### Option B — Remove tax step from Pricing Procedure (Expression Set edit)
- Risk: May affect other RLM flows; Pricing Procedure metadata not always editable
- Time: ~4 hours
- Reward: Matches ADR-009 design exactly

### Option C — Custom Order creation path that bypasses CalculationStatus check
- Risk: Reviewer org won't be using this; subscriber org won't have this; not a real fix
- Time: ~2 hours
- Reward: Demo can continue, but not production-grade

### Option D — Git-based partial rollback
- Risk: May lose other work; org data won't be restored
- Time: 2-3 hours including verification
- Reward: Possibly restore exact working state

### Option E — Just accept that pink banner shows but Create Order works
- Risk: Reviewer sees error message during demo
- Reward: No more debugging time

I'm leaning **A → B**. What would you do?

---

## Context — Why I'm Stressed About This

TechnoStore is the demo org I'll show to recruiters, investors, and (potentially) reviewers. It took 3-5 months to build the full Q2C E2E flow. Everything else still works (8 integrations: Stripe, DocuSign, Sendcloud, JIRA, Slack, Notion, SAP, WhatsApp). The Configra package I tested today is completely uninstalled. But this Decision Table failure persists, blocking Create Order — which means the entire Q2C demo dies at step 3 (Quote → Order).

I cannot rebuild this in another org in time. The fix has to happen in TechnoStore. I'm willing to invest 1-3 days on this if there's a clear path. I'm running out of theories.

**Help me find the path.**

---

## Files & References for Your Inspection

- `docs/adr/ADR-009-quote-tax-formula-invoice-tax-adapter.md` — the original design ADR
- `docs/adr/ADR-024-sap-tax-determination-parallel-adapter.md` — SAP tax adapter for Invoice (Phase 3)
- Memory note `quote_tax_calculation_issue.md` (per CLAUDE.md context, not directly readable in this brief)

## Sister AI Format Request

Please answer Q1-Q5 specifically and directly. If you can confirm the root cause OR rule out my hypotheses, that's high-value. If the right answer is "open Salesforce Support ticket", please tell me what evidence to include.

**Be sharp. Be specific. Don't sugarcoat.** I need actionable next steps within 24 hours.

Thank you.

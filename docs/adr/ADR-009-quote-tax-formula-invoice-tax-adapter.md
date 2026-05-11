# ADR-009: Quote Tax via Formula Fields, Invoice Tax via commercetax Adapter

## Status

**Accepted**

## Date

2026-05-03

## Author

Mustafa Aksu

## Context

TechnoStore is DACH-focused and must display **German 19% VAT** (Mehrwertsteuer) on Quote and QuoteLineItem records **before** Order creation. German B2B buyers expect Net + VAT + Gross breakdown on every Quote PDF — the sales conversation stalls at "what is the gross figure?" if only Net is visible, forcing the rep to mental-math 19% on the spot.

The Salesforce Industries Tax Engine (`commercetax.TaxEngineAdapter` namespace) is the canonical mechanism for tax calculation. It is wired into the **Invoice creation flow** via a configured Tax Engine Adapter assignment. The adapter:

- Computes precise tax via address geocoding (`commercetax.TaxAddress` resolution)
- Applies product-level tax classification mapping (`commercetax.TaxableItem` lookup)
- Handles compound tax rules (federal + state/Land + city) where applicable
- Returns line-item-level tax amounts that are persisted on `InvoiceLine` records

The adapter **does not fire on Quote save** — by Salesforce platform design. `QuoteLineItem.save()` lifecycle invokes the Pricing Procedure (which computes UnitPrice) but not the Tax Engine. This is intentional: Quote tax is non-binding (estimate), Invoice tax is binding (legal compliance) — Salesforce treats them as different lifecycle stages.

Three approaches were considered to expose tax on Quote stage:

1. **Force the adapter to fire on Quote save** via custom invocable wrapper
2. **Apex trigger on QuoteLineItem** that computes tax inline
3. **Formula fields** on QuoteLineItem + Quote that compute tax declaratively

Approach 1 was investigated and rejected: the adapter requires address geocoding (slow, async), product-level tax classification mapping (incomplete in our trial data), and creates phantom `InvoiceLine` records that pollute reporting if fired on Quote stage.

Approach 2 introduces a circular calculation risk: Pricing Procedure updates `UnitPrice` on save, then trigger updates `Tax_Amount__c`, which could trigger another Pricing Procedure pass if Pricing Procedure ever depended on Tax_Amount__c. Circular dependency tech debt.

Approach 3 is the cleanest: formula fields are **read-only derived values** computed at query/render time with zero CPU cost. They participate in Quote PDF rendering, report rollups, and dashboard aggregations without any Apex execution.

## Decision

**Quote-stage tax display: 4 formula fields** computing 19% VAT declaratively.
**Invoice-stage tax: preserve the commercetax adapter chain intact** for legal-compliant calculation.

Quote-stage formula fields:

| Object | Field | Type | Formula |
|--------|-------|------|---------|
| `QuoteLineItem` | `Tax_Rate__c` | Number(3,4) | `0.19` (constant — German VAT rate) |
| `QuoteLineItem` | `Tax_Amount__c` | Currency | `UnitPrice * Quantity * Tax_Rate__c` |
| `Quote` | `Total_Tax__c` | Roll-Up Summary (SUM) | `QuoteLineItem.Tax_Amount__c` |
| `Quote` | `Total_With_VAT__c` | Currency | `TotalPrice + Total_Tax__c` |

The two-stage tax narrative is documented in the demo script + Notion entry 15:

- **Quote stage** — "Estimated VAT" computed via formula. Sales rep can quote a customer "€1,499 + €284.81 VAT = €1,783.81 gross" instantly on save, without any external adapter call.
- **Invoice stage** — "Official VAT" computed via commercetax adapter with per-address geocoding. This is the legally-binding figure that appears on the customer's invoice.

The narrative wording ("estimated" vs "official") is intentional — it preserves the legal distinction Salesforce platform makes between Quote and Invoice tax, while still solving the sales-rep "I can't quote a gross number" pain.

For multi-country expansion (future work — see ADR roadmap), the `0.19` constant becomes a lookup: `Tax_Rate__mdt` Custom Metadata Type keyed by ISO country code (DE=0.19, AT=0.20, CH=0.077). The `Tax_Rate__c` formula then resolves via `Account.BillingCountry`.

## Consequences

### Positive

- **Zero Apex execution on Quote save** — formula fields compute at query/render time. No CPU cost, no governor consumption, no async settling delay.
- **Instant visibility** — opening a Quote with line items renders the Tax_Amount per line + Total_Tax + Total_With_VAT immediately. No "wait for the trigger to fire" UX wart.
- **Quote PDF integration is free** — `TechnoStoreQuotePdf.page` references `{!quote.Total_With_VAT__c}` directly. No controller-side computation needed.
- **Report + dashboard compatibility** — formula fields participate in `SOQL` aggregates, Lightning Reports, CRM Analytics dashboards as first-class numeric fields. A "Pipeline by VAT contribution" report needs no extra plumbing.
- **No circular calculation risk** — formula fields are read-only; Pricing Procedure cannot trip a re-fire.
- **Invoice-stage adapter chain preserved** — the commercetax adapter still runs at Invoice creation for legally-compliant per-address tax. No regression on legal compliance.
- **Two-stage demo narrative is coherent** — Quote shows estimated VAT (formula), Invoice shows official tax (adapter). Sales rep + finance team understand both.

### Negative / Trade-offs

- **Hardcoded `0.19` rate** — Germany-only. Austria (20%) and Switzerland (7.7%) customers see incorrect VAT until the multi-country lookup is added (future work).
- **No address-level precision** — formula fields cannot apply municipality-level overrides (e.g., Helgoland VAT-free zone in Germany). The estimate is "rough" by design; the adapter handles edge cases at Invoice stage.
- **Formula complexity ceiling** — Salesforce formula compilation has a 5,000-character limit. The current formulas are far below this, but as multi-country + product-class tax logic grows, the formula approach may eventually need to graduate to Apex.
- **Cannot model product-level tax classification** — current formula treats all products as 19% VAT. Real-world tax law distinguishes (e.g., books at 7% reduced rate in Germany). For TechnoStore's electronics-only catalog, all items are 19% so no immediate issue, but the formula is not extensible without rewrite.

## Alternatives Considered

### Alternative A — Apex trigger computing Tax_Amount__c on QuoteLineItem save

Rejected because:
- Circular calculation risk if Pricing Procedure ever depends on Tax_Amount.
- Async settling delay (`@future` adds 2-5 sec latency) makes the UX worse than instant formula rendering.
- Hidden CPU cost on every save adds up across bulk Quote operations.
- More code to maintain + test compared to declarative formula.

### Alternative B — Force commercetax adapter to fire on Quote save via custom invocable

Rejected because:
- Adapter requires address geocoding (slow, async, may fail on incomplete address records during demo).
- Phantom InvoiceLine records would be created during Quote stage, polluting reporting.
- Salesforce platform treats Quote vs Invoice tax as deliberately different stages — fighting the platform is technical debt.

### Alternative C — External tax service (Avalara, TaxJar) callout

Rejected because:
- External dependency for what is fundamentally arithmetic (UnitPrice × 0.19).
- DACH GDPR/DSGVO: customer data flowing through US-hosted tax service requires Data Processing Agreement.
- Network latency on every Quote save (~1-3 sec per callout) hurts UX.
- Cost: Avalara starts at ~$50/month minimum; overkill for a demo.

### Alternative D — Use a custom Apex `@AuraEnabled` method called from the Quote Lightning page

Rejected because:
- Requires the user to be on the Lightning page for tax to compute; bulk operations (data loader Quote import) would skip tax.
- LWC-only path; Visualforce Quote PDF cannot easily call an `@AuraEnabled` method during PDF render.

## Multi-country expansion plan (future work)

Documented as Q3 2026 work item:

1. Create `Tax_Rate__mdt` Custom Metadata Type with fields:
   - `Country_ISO__c` (Text 2) — DE / AT / CH / etc.
   - `Rate__c` (Number 3,4) — 0.19 / 0.20 / 0.077 / etc.
   - `Effective_From__c` (Date) — for rate-change historical accuracy
2. Pre-populate with DACH rows: DE=0.19, AT=0.20, CH=0.077.
3. Rewrite `QuoteLineItem.Tax_Rate__c` formula to:
   ```
   VLOOKUP(
     $ObjectType.Tax_Rate__mdt.Fields.Rate__c,
     $ObjectType.Tax_Rate__mdt.Fields.Country_ISO__c,
     Quote.Account.BillingCountryISO
   )
   ```
   (or similar — depending on Salesforce formula function support for mdt lookups)
4. Add `Account.BillingCountryISO` formula field that maps `BillingCountry` text → ISO-2 code.
5. For products with reduced rates (e.g., books, food), add `Product2.Tax_Category__c` picklist + extend Tax_Rate__mdt with Category column.

## References

- **Memory**: `quote_tax_calculation_issue.md`
- **Notion portfolio entry**: 15 — "Quote Tax Display — Formula Field Workaround for commercetax Adapter"
- **Schema**: `force-app/main/default/objects/QuoteLineItem/fields/Tax_Rate__c.field-meta.xml`, `Tax_Amount__c.field-meta.xml`; `Quote/fields/Total_Tax__c.field-meta.xml`, `Total_With_VAT__c.field-meta.xml`
- **VF**: `force-app/main/default/pages/TechnoStoreQuotePdf.page` references the formula fields
- **Related ADRs**: ADR-002 (Custom Metadata Type pattern — same approach for future multi-country tax lookup)
- **Salesforce docs**: [commercetax Namespace](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_namespace_commercetax.htm)

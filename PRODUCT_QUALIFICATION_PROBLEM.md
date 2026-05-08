# Salesforce RLM — Product Qualification Engine Not Filtering at Browse Catalog Runtime

## Environment

- Salesforce Developer Edition org with Industries CPQ + Revenue Lifecycle Management (RLM) enabled
- API version 66.0
- Spring '26 release line
- Standard Browse Products UI (`runtime_industries_oms_components__catalogPicker` / Browse Catalog component)
- TechStore Electronics Catalog (`0ZSaj000000KBlhGAG`)
- Context definition: `BrowseProductsCtxDefinition`

## Goal

Demonstrate buyer-context-based catalog filtering. When sales rep opens Browse Catalog from a Quote on:
- Hamburg DataWorks AG (Industry=Technology, NumberOfEmployees=320) → premium workstations should be visible
- Köln Retail Cloud GmbH (Industry=Retail, NumberOfEmployees=180) → premium workstations should be hidden

## What's been configured (and verified via SOQL)

### Existing product (works as Browse Catalog item, qualification rules NOT enforced)

`WorkStation X Pro` (Id `01taj00000QnnlaAAB`, ProductCode `COMP-WS-001`):
- Type=null, Family=Hardware, BasedOn=Computer classification, IsActive=true
- ProductCategoryProduct: Workstation, Computers & Laptops (catalog `0ZSaj000000KBlhGAG`)
- ProductSellingModelOption: One Time
- PricebookEntries on Standard ($3,299) + 4 custom pricebooks
- ProductQualification: Min=0, Max=999999 (open to all)
- ProductDisqualification: 0 records

### Existing premium product (visible to all — qualification not enforced)

`RenderStation Ultra` (Id `01taj00000QnnlbAAB`):
- Same shape as WorkStation X Pro
- ProductQualification updated to **Min=100 employees** (originally Min=0)
- Added 12 ProductDisqualification rows for Industry IN (Retail, Healthcare, Education, Hospitality, Recreation, Not For Profit, Apparel, Food & Beverage, Government, Construction, Agriculture, Entertainment)
- **Expected**: Köln (Retail) should NOT see this product
- **Actual**: Köln still sees RenderStation Ultra in Workstation category

### My new product (not visible to anyone — not reaching the catalog at all)

`Premium Workstation Pro` (Id `01taj00000RvBiLAAV`, ProductCode `COMP-WS-PREMIUM`):
- Created via Apex with all matching fields:
  - Type=null (no Type field set)
  - Family=Hardware
  - BasedOn=Computer classification (same as working products)
  - IsActive=true
  - QuantityUnitOfMeasure=Each
  - ExternalId set
- Linked to Workstation + Computers & Laptops + Desktop PC categories (3 ProductCategoryProduct rows, all in catalog `0ZSaj000000KBlhGAG`)
- ProductSellingModelOption: One Time (`0jPaj000000EWphEAG`)
- PricebookEntries on Standard ($4,500) and TechStore Summer Campaign ($4,200)
- ProductQualification: Min=100, Max=999999, EffectiveFromDate=today−1, EffectiveToDate=2099-12-31
- 12 ProductDisqualification rows for the same industries
- **Expected**: Hamburg sees it, Köln doesn't see it
- **Actual**: Neither account sees the product in Browse Catalog

A second product `Compact Workstation Studio` was added with identical pattern and same outcome.

## What's been tried

| Action | Result |
|---|---|
| Rebuild Index (Setup → Product Discovery Settings → Rebuild Index) | Completed successfully. Partial rebuild detected the 3 changes (1 delete + 2 inserts). Last Updated 5/8/2026 09:24 AM. |
| Field-by-field SOQL diff Premium Workstation Pro vs WorkStation X Pro | No structural differences in Product2 fields except meta (CreatedDate, etc.) |
| Apex insert ContextDefinitionSync record with Status='in_progress' for BrowseProductsCtxDefinition | Record stays in_progress forever. Platform doesn't pick it up. |
| Set Product2.Type=null (cannot UPDATE Type field — recreated entire product without Type) | New product still doesn't appear |
| Verified ProductQualification has writeable required fields, IsQualified default-true | Verified |

## ProcedurePlan structure (suggests engine IS configured)

3 ProcedurePlanOption records are active:

| PPO Id | Section | Procedure | sectionType |
|---|---|---|---|
| 1FYaj0000004zpiGAA | 1FRaj0000000t2wGAA | Product_Discovery_Pricing_Procedure | (priority=1) |
| 1FYaj000000504DGAQ | 1FRaj0000000t1JGAQ | **Product_Qualification** | **ProductQualificationProcedure** |
| 1FYaj000000504EGAQ | 1FRaj0000000t1KGAQ | Product_Discovery_Pricing_Procedure | PricingProcedure |

ExpressionSetDefinition `9QAaj000000FAyPGAW` = Product_Qualification.

CalculationProcedure named "Product Qualification" exists (Id `0k0aj000000I52sAAC`, UniqueName `Product_Qualification`).

`BrowseProductsCtxDefinition` last successful sync: **2026-04-03**. All my changes (PDQ inserts on existing products + new products) are AFTER that date.

`Custom_ContractsContext` had 2 sync attempts on 2026-04-21 — both **Status=failed**.

## Hypothesis

Browse Catalog's runtime filter pipeline = `Product Discovery Index` (search lookup) + `Product Qualification ExpressionSet` (filter by Account context).

- The Index was rebuilt by user → search/discovery layer knows about my products.
- The Qualification ExpressionSet runtime cache was NOT refreshed → qualification engine evaluating against an old snapshot that doesn't know about my PDQ records or my new products.

The known sync mechanism for ExpressionSet/CalculationProcedure runtime cache is `Salesforce Pricing Setup → Sync` (separate from Product Discovery Settings → Rebuild Index). User doesn't see this menu in Setup search.

## Open questions / what we need

1. **Where is "Salesforce Pricing Setup → Sync" in this org?** Setup search for "Salesforce Pricing" returns nothing actionable. Web research suggests it should be at Setup → Feature Settings → Salesforce Pricing → Salesforce Pricing Setup. In this org only "Product Catalog Management → Product Discovery Settings" is visible.

2. **Is there a separate procedure / context binding step missing?** The PPO records exist but maybe a `ProcedurePlanCriterion` link is missing for new products?

3. **Does the qualification engine need an explicit binding to the BrowseProducts context?** Maybe `ExpressionSetDefinitionContextDefinition` is the missing junction.

4. **Programmatic sync — is there a ConnectApi or REST endpoint?** Inserting ContextDefinitionSync directly with Status=in_progress doesn't trigger platform processing. ConnectApi.SalesforcePricing and ConnectApi.RevenueLifecycleManagement don't exist on this org's API version.

5. **Are my products being EXCLUDED by the discovery procedure?** The `Product_Discovery_Pricing_Procedure` runs first (priority=1) — maybe it has hardcoded product list or default-deny logic that blocks unknown products until added explicitly somewhere.

## Demo context

- Recording video for DACH Salesforce job applications
- TechStore demo org (full Q2C lifecycle: Lead → Quote → Order → Contract → DocuSign → Invoice → Asset)
- This is one of the last features to nail before recording. ProductQualification is a flagship Industries CPQ capability — recruiters expect to see it working, not just configured.

## What I would consider acceptable answers

- Exact UI path to trigger qualification cache rebuild
- OR exact Apex/REST call to programmatically rebuild qualification cache
- OR diagnosis of which related record is missing on my new products that prevents catalog visibility
- OR confirmation that this org config requires custom build (so I stop trying to wire native and pivot to custom LWC catalog)

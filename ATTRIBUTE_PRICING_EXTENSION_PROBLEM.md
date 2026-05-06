# Salesforce Revenue Cloud (RLM) — Cannot Extend Attribute-Based Pricing Beyond Initial Configuration

## TL;DR

In a Dev Edition org running Salesforce Revenue Lifecycle Management (RLM), we have a working attribute-based pricing setup for ONE attribute (Memory/RAM) on a Bundle product. We need to add the SAME pattern for three more attributes (Storage, Processor, Screen Size) on the same Bundle. **Every Apex/REST DML attempt to insert `AttributeAdjustmentCondition` records is blocked by a platform validation: `FIELD_INTEGRITY_EXCEPTION: Ensure that your attribute is price impacting`** — even after setting `IsPriceImpacting=true` on every related `ProductAttributeDefinition` and `ProductClassificationAttr` record.

The existing working RAM configuration must have been created through a path that bypasses this validation. We need to know what that path is.

---

## Working Configuration (Memory / RAM)

The Bundle product:
- `Product2.Id = 01taj00000Qp7IFAAZ` ("Home Office Bundle", `Type=Bundle`)
- `Product2.BasedOnId = 11Baj000015O78DEAS` (a `ProductClassification`)

The 5 attributes attached to this classification:
- `Screen Size` — `AttributeDefinition.Id = 0tjaj000000FbXHAA0`
- `Graphics` — `AttributeDefinition.Id = 0tjaj000000FbXIAA0`
- `Memory` — `AttributeDefinition.Id = 0tjaj000000FbXJAA0` ← **WORKS**
- `Processor` — `AttributeDefinition.Id = 0tjaj000000FbXMAA0`
- `Storage` — `AttributeDefinition.Id = 0tjaj000000FbXNAA0`

For Memory, the data chain is fully populated:

```
AttributeBasedAdjRule (3 records, one per RAM tier)
  Name = "HomeOfficeBundle-RAM16"  → Id 12Haj000000IQSHEA4
  Name = "HomeOfficeBundle-RAM32"  → Id 12Haj000000IQSIEA4
  Name = "HomeOfficeBundle-RAM64"  → Id 12Haj000000IQSJEA4

AttributeAdjustmentCondition (1 per rule, links rule to picklist Value)
  AttributeBasedAdjRuleId  = <rule Id>
  AttributeDefinitionId    = 0tjaj000000FbXJAA0  (Memory)
  Operator                 = "equals"
  StringValue              = "RAM 32GB"           (← matches AttributePicklistValue.Value)

AttributeBasedAdjustment (1 per rule, with the actual price delta)
  AttributeBasedAdjRuleId  = <rule Id>
  PriceAdjustmentScheduleId = 84Xaj000000I0SzEAK   (active schedule)
  AdjustmentType           = "Amount"
  AdjustmentValue          = 200                    (e.g. for RAM32)
  ProductId                = 01taj00000Qp7IFAAZ
  ProductSellingModelId    = 0jPaj000000EWphEAG    (One Time)
  EffectiveFrom            = 2026-01-01

PriceAdjustmentSchedule
  Id        = 84Xaj000000I0SzEAK
  IsActive  = true

ProductAttributeDefinition (multiple records for Memory across the catalog)
  All have IsPriceImpacting = true

ProductClassificationAttr (10 records for Memory)
  All have IsPriceImpacting = true

AttributePicklistValue (cosmetic display labels, separate from Value)
  Id = 0v6aj000000G24UAAS  (RAM 32GB)
  Name         = "RAM 32GB (+$200)"
  DisplayValue = "RAM 32GB (+$200)"
  Value        = "RAM 32GB"   ← StringValue on the Condition matches against this
```

**At runtime**: a custom QuoteLineItem trigger (`beforeUpdate`) reads the `QuoteLineItemAttribute` records on the Bundle QLI, joins to `AttributeAdjustmentCondition`, sums `AttributeBasedAdjustment.AdjustmentValue` for each match, and sets `q.UnitPrice = PricebookEntry.UnitPrice + totalAdjustment` directly on `Trigger.new` (no DML). This works perfectly — selecting RAM 32GB on the Configure UI changes the Bundle's Sales Price from $1,599 to $1,799.

The native Pricing Procedure for this product has 0 `CalculationProcedureSteps` configured. The Builder UI in Setup has been unreliable in this org, so we built the trigger to consume the same data layer the native engine would consume. Migration to the native engine later is config-only.

The RAM rules above **were created some time ago** — we don't know precisely how. Best guess: the Pricing Procedure Builder UI in Setup, which has its own internal endpoint for creating these records.

---

## What We Need

For the same Bundle product, identical configuration for three more attributes:

| Attribute | Picklist Value | Adjustment | AttributePicklistValue Id |
|---|---|---|---|
| Storage | SSD Hard Drive 512GB | +$100 | 0v6aj000000G24iAAC |
| Storage | SSD Hard Drive 1TB | +$200 | 0v6aj000000G24gAAC |
| Storage | SSD Hard Drive 2TB | +$400 | 0v6aj000000G24jAAC |
| Storage | Cloud Storage Enterprise - 2 TB | +$300 | 0v6aj000000G24fAAC |
| Storage | Cloud Storage Enterprise - 6 TB | +$600 | 0v6aj000000G24kAAC |
| Processor | i7-CPU 4.7GHz | +$200 | 0v6aj000000G24cAAC |
| Processor | Intel Core i9 5.2 GHz | +$500 | 0v6aj000000G24dAAC |
| Screen Size | 15 Inch | +$100 | 0v6aj000000G24RAAS |
| Screen Size | 24 Inch | +$200 | 0v6aj000000G24QAAS |
| Screen Size | 27 Inch | +$300 | 0v6aj000000G24OAAS |

Cosmetic dropdown labels (`AttributePicklistValue.Name` + `DisplayValue` with `(+$X)` suffix) are already in place — recruiters see the price differentials. The runtime trigger logic is generic and would consume any new `AttributeBasedAdjRule + Condition + Adjustment` records the same way it consumes RAM's. **The only blocker is creating those three records.**

---

## What We Tried (and the Errors)

### Attempt 1 — Straight Apex DML, Rule → Condition → Adjustment

```apex
AttributeBasedAdjRule rule = new AttributeBasedAdjRule(Name='HomeOfficeBundle-Storage512GB');
insert rule;   // ✓ succeeds

AttributeAdjustmentCondition cond = new AttributeAdjustmentCondition(
    AttributeBasedAdjRuleId = rule.Id,
    AttributeDefinitionId   = '0tjaj000000FbXNAA0',  // Storage
    Operator                = 'equals',
    StringValue             = 'SSD Hard Drive 512GB'
);
insert cond;   // ✗ FAILS
```

> `System.DmlException: Insert failed. First exception on row 0; first error: FIELD_INTEGRITY_EXCEPTION, Ensure that your attribute is price impacting.: []`

### Attempt 2 — Set `IsPriceImpacting=true` first, then retry

We set `IsPriceImpacting=true` on every `ProductAttributeDefinition` and `ProductClassificationAttr` record for Storage, Processor, Screen Size. Verified post-update with SOQL — all true.

Re-ran the condition insert. **Same `FIELD_INTEGRITY_EXCEPTION`**.

### Attempt 3 — Reverse the order: Rule → Adjustment → Condition

```apex
insert rule;          // ✓ succeeds
insert adjustment;    // ✗ FAILS with a different error
```

> `FIELD_INTEGRITY_EXCEPTION, Associate all price impacting attributes with the relevant Attribute Adjustment Condition and try again.`

So Adjustment requires the Rule to already have a Condition. And Condition refuses to insert until... something is true that we can't seem to satisfy. Chicken-and-egg.

### Attempt 4 — Bulk DML, Condition + Adjustment in the same `Database.insert` call

```apex
Database.SaveResult[] results = Database.insert(new SObject[]{cond, adj}, false);
```

Both rows failed. Condition: "Ensure that your attribute is price impacting". Adjustment: "Associate all price impacting attributes...". The platform validates each record independently before commit — bulk DML doesn't bypass either check.

### Attempt 5 — Direct REST API POST (bypassing Apex)

```apex
HttpRequest req = new HttpRequest();
req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/data/v60.0/sobjects/AttributeAdjustmentCondition');
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(new Map<String, Object>{
    'AttributeBasedAdjRuleId' => ruleId,
    'AttributeDefinitionId'   => '0tjaj000000FbXNAA0',
    'Operator'                => 'equals',
    'StringValue'             => 'SSD Hard Drive 512GB'
}));
HttpResponse res = new Http().send(req);
```

> `Status: 400`
> `Body: [{"message":"Ensure that your attribute is price impacting.","errorCode":"FIELD_INTEGRITY_EXCEPTION","fields":[]}]`

Same validation. The block is on the platform record-write layer, not specific to Apex DML.

### Attempt 6 — Test inserting a new condition for the WORKING Memory attribute

To rule out Storage-specific issues, we tried inserting a brand-new condition for Memory (the attribute that already has 3 working conditions and produces correct $1,799 pricing at runtime):

```apex
AttributeBasedAdjRule r = new AttributeBasedAdjRule(Name='HomeOfficeBundle-TEST-RAM');
insert r;
AttributeAdjustmentCondition c = new AttributeAdjustmentCondition(
    AttributeBasedAdjRuleId = r.Id,
    AttributeDefinitionId   = '0tjaj000000FbXJAA0',  // Memory — KNOWN WORKING
    Operator                = 'equals',
    StringValue             = 'RAM 8GB'
);
insert c;  // ✗ FAILS — same error as Storage
```

> `FIELD_INTEGRITY_EXCEPTION, Ensure that your attribute is price impacting.`

**This is the smoking gun.** The validation blocks ALL new `AttributeAdjustmentCondition` inserts via Apex/REST DML, regardless of whether the target attribute is the known-working RAM. The existing 3 RAM conditions still serve runtime queries correctly, but no new conditions can be added through these paths. This means:

1. The RAM conditions were not created through the Apex/REST DML path.
2. Some other internal path created them — likely the Setup → Pricing Procedure Builder UI, which uses a private endpoint exempt from this check.
3. We have no way to reach that internal path programmatically from this Dev Edition org.

### Attempt 7 — `ConnectApi.RevenueCloud` (recommended by one consultant)

```apex
Type t = Type.forName('ConnectApi.RevenueCloud');
System.debug(t == null ? 'NOT FOUND' : 'EXISTS');
// → NOT FOUND
```

Probed adjacent namespaces:
- `ConnectApi.RevenueCloud` → NOT FOUND
- `ConnectApi.CommerceCart` → THROWS `Type is not visible` (exists but no access in this org)
- `ConnectApi.RevenueSales` → NOT FOUND
- `ConnectApi.CartItems` → NOT FOUND
- `ConnectApi.Cart` → NOT FOUND
- `ConnectApi.RevenueLifecycleManagement` → NOT FOUND
- `ConnectApi.QuoteLineItem` → NOT FOUND

So no documented or undocumented Apex bridge to a managed bundle/pricing API in this org.

### Attempt 8 — Apex Triggers / Validation Rules / Flows on the target objects

To rule out custom rules in the org:

```sql
SELECT Name, TableEnumOrId, Status FROM ApexTrigger
WHERE TableEnumOrId IN ('AttributeAdjustmentCondition','AttributeBasedAdjustment','AttributeBasedAdjRule')
-- → 0 records

SELECT EntityDefinition.QualifiedApiName, ValidationName FROM ValidationRule
WHERE EntityDefinition.QualifiedApiName IN ('AttributeAdjustmentCondition','AttributeBasedAdjustment')
-- → 0 records
```

The validation is built into the platform managed code, not from any custom config in the org.

---

## Validation Chain Summary

The error message "Ensure that your attribute is price impacting" surfaces from `AttributeAdjustmentCondition` insert. The error "Associate all price impacting attributes with the relevant Attribute Adjustment Condition" surfaces from `AttributeBasedAdjustment` insert.

What we know:

| Field | Where | Storage / Processor / Screen Size | Memory (working) |
|---|---|---|---|
| `IsPriceImpacting` | `ProductAttributeDefinition` | true (we set it) | true (was already) |
| `IsPriceImpacting` | `ProductClassificationAttr` | true (we set it) | true (was already) |
| `IsActive` | `AttributePicklist` | Active | Active |
| `Status` | `AttributeDefinition` | Active | Active |
| Existing rule | `AttributeBasedAdjRule` | None until we insert | 3 records exist |
| Existing condition | `AttributeAdjustmentCondition` | None | 3 records exist |
| Existing adjustment | `AttributeBasedAdjustment` | None | 3 records exist |

The two attribute groups look schema-identical. Yet only Memory's chain works, and Memory's chain itself can no longer be extended via Apex/REST.

---

## What We Need from a Consultant

A repeatable, scriptable way to insert `AttributeAdjustmentCondition` records (and the matching `AttributeBasedAdjustment` records) for a given Bundle product and AttributeDefinition. Specifically:

1. **The exact Setup UI path** for creating attribute-based price adjustments in Salesforce RLM Dev Edition orgs — including any prerequisite catalog/pricing setup steps that must be completed in a specific order to satisfy the `IsPriceImpacting` validation. Screenshots of where to click would be ideal.

2. **Any documented or undocumented `ConnectApi`, Tooling API, or Metadata API endpoint** that creates `AttributeAdjustmentCondition` records the way the Builder UI does (i.e. without the FIELD_INTEGRITY_EXCEPTION).

3. **Any setup-time prerequisite we might be missing** — a Pricing Procedure step, a `CalculationProcedureVersion`, an `AttributeCategoryAttribute` record, a sync/refresh action — that the platform looks at when it decides whether the chicken-and-egg validation can be satisfied.

4. **An explanation of why the validation now blocks even Memory inserts**, when Memory has working data already. Is there a recent platform change, a feature flag we toggled, or a piece of state the validation reads that we accidentally invalidated?

The runtime trigger that consumes this data is generic and works perfectly for Memory. We just need to seed the same three-table chain for three more attributes, identical pattern, on the same Bundle product.

## Repository Snapshot

- Repo: TechnoStore (Salesforce DX project, multiple package directories)
- Org: your-org.develop.my.salesforce.com (Developer Edition)
- Org email: technostore-admin@example.com
- Trigger handler: `force-app-handlers/main/default/classes/QuoteLineItemTriggerHandler.cls`
  - `applyAttributeAdjustmentsInPlace()` — generic runtime consumer; works for any attribute that has the data chain populated
- Failed setup script: `scripts/add_storage_processor_screen_pricing.apex`
- Diagnostic scripts: `scripts/test_*.apex` (some kept, some deleted as dead-end)

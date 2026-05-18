# ADR-026: SAP Material Master Sync — Nightly Product2 Reconciliation

## Status

Accepted — implemented 2026-05-18 in SAP Sprint Phase 5. SapMaterialMasterSyncService + two new Product2 fields (SAP_Last_Synced_At, SAP_Product_Description) deployed and verified — 10 SAP materials fetched in a sandbox test, 9 created + 1 updated + 1 skipped.

## Context

ADR-022 (SAP MM ATP) depends on `Product2.SAP_Material_Number__c` being populated — the join field between Salesforce products and SAP materials. Without it, the ATP service has nothing to query SAP for; it falls through to the warehouse approval path for every Order.

The demo's first material number was set by hand (`SAP_Material_Number__c = '221'` on the WebCam Pro 4K Studio product, during Phase 1 testing). One product, manual setup. Production with hundreds or thousands of SKUs can't do this manually — it needs an automated sync from SAP material master to SF Product2.

In a DACH manufacturing or distribution enterprise, the **material master** is THE source of truth for product data: SKU number, description, base unit of measure, weight, dimensions, hazard classification, tax category, lifecycle status. SAP is where this data is curated; SF Product2 is a commercial mirror (with extra fields for CRM use — Pricebook entries, classification, bundle composition).

The sync question: how much of the SAP material master flows into SF, how often, with what conflict-resolution rules?

## Decision

`SapMaterialMasterSyncService.sync(maxFetch)` is an `@InvocableMethod` that:

1. Calls `GET /s4hanacloud/sap/opu/odata/sap/API_PRODUCT_SRV/A_Product?$top={N}&$format=json` with the standard SAP credentials (APIKey header from SAP_Config__c).
2. Parses the OData v2 response `d.results` array.
3. For each SAP product:
   - Reads `Product` (material number) and `ProductDescription`.
   - Looks up an existing SF Product2 by `SAP_Material_Number__c = <Product>`.
   - If found → update `SAP_Product_Description__c` + `SAP_Last_Synced_At__c`.
   - If not found → create a new Product2 with Name = `[SAP] <ProductDescription or Product>`, IsActive = true, `SAP_Material_Number__c = <Product>`.
4. Bulk `Database.upsert allOrNone=false` — bad records (empty Product field, validation errors) increment failedCount but don't poison the batch.

### Scope boundary — what the sync DOES NOT touch

- **Pricebook entries.** Pricing is commercial config. SF Pricebook2 is curated by sales ops; the SAP material number is the join key, not the price source. (Production may sync prices via a separate flow, but that's ADR-???.)
- **Product classification / Industries CPQ qualification.** Product2 classification, qualification rules, bundle composition all stay SF-managed. The sync touches only the data fields, not the CPQ relational metadata.
- **AttributeBasedAdjustment.** The bundle attribute pricing data (ADR-016) is SF-administered. SAP doesn't drive it.
- **Type field.** New Product2 records are created with Type=null — required for Industries CPQ Product Qualification visibility (per memory `product_qualification_demo_setup`). Setting Type=Base or anything else would hide the product from Browse Catalog.

### Production deployment — Mule scheduled flow

Demo invocation: anonymous Apex calls `SapMaterialMasterSyncService.sync` ad-hoc. Production: Mule scheduled flow at 02:00 CET nightly:

1. Mule cron-triggers the flow.
2. Mule calls SAP API_PRODUCT_SRV directly (Mule has the same credentials).
3. Mule POSTs the response payload as Composite REST to SF.
4. SF Apex routes to `SapMaterialMasterSyncService.sync` with the payload pre-parsed.

This split moves the SAP callout out of Apex callout limits and lets Mule add retry / DLQ / paging for large catalogues. Apex stays as the SF-side commit step.

### Why full-table fetch, not delta

SAP API_PRODUCT_SRV doesn't natively support a "changed since last sync" filter in the way most modern APIs do. Options to implement delta: maintain a `Last_Modified_DateTime` filter (SAP's CreationDateTime / LastChangeDateTime fields), or compute a hash. For now, full-table-fetch is simpler and works fine for material masters of typical Mittelstand size (a few thousand SKUs). Delta migration is a future optimisation when catalogue size grows past ~10k SKUs.

## Consequences

### Positive

- **ATP integration (ADR-022) becomes data-complete.** Once the nightly sync runs, every Product2 with a SAP material number has a real join key. ATP no longer falls back due to missing SAP_Material_Number__c.
- **Drift visibility.** SAP_Product_Description__c stores SAP's description; SF Product2.Name is the commercial display name. If they diverge dramatically (e.g., SAP renames a product but SF still uses the old name), the audit comparison surfaces it.
- **Upsert pattern is bulk-safe.** Database.upsert with the external id handles "is this a new product?" vs "is this an existing product?" in one DML; allOrNone=false absorbs malformed SAP records gracefully.
- **Production migration is mechanical.** Same service signature; Mule pre-parses the payload and calls Composite REST instead of Apex calling SAP directly. SF-side test logic unchanged.
- **Demo storyline strong.** Recording shows the sync running, X products created with `[SAP]` prefix, the WebCam Pro material number updated. Real call, real data, visible side effect.

### Negative

- **Demo-created Product2 records are noise in the catalogue.** Browse Catalog now shows `[SAP] 21`, `[SAP] 68`, etc. — sandbox material numbers that aren't real TechnoStore products. Mitigation: filter Browse Catalog UI to exclude `[SAP] %` prefixed products, or run the sync only against curated sandbox materials.
- **No description data in sandbox.** SAP API Hub Sandbox returns null or empty `ProductDescription` for most materials. Service falls back to using the material number as the name. Production with a real material master would return meaningful descriptions.
- **Full-table sync is wasteful at scale.** Re-fetching every product nightly when only 1% changed is bandwidth-inefficient. Acceptable for demo; delta sync is the production optimisation.
- **No deletion handling.** If SAP retires a material (sets its lifecycle status to Discontinued), the sync doesn't deactivate the SF Product2. Production may need either a periodic full reconciliation pass that marks missing Product2 records inactive, or a separate SAP→SF event subscription for material-status-change events.

### Future state

- **Mule scheduled flow** (production primary path): `mulesoft/sap-material-master-sync.xml` cron-triggered at 02:00 CET. Mule does the SAP call, posts the JSON to SF Composite REST.
- **Delta sync** when catalogue grows: filter SAP query by `LastChangeDateTime gt {last_sync}`, store last sync timestamp in a Custom Setting.
- **Extended field sync** — pull `BaseUnit`, `GrossWeight`, `NetWeight`, `ProductTaxCategory`, `IsMarkedForDeletion`, etc. into matching Product2 fields. Each extension adds value but requires SF schema work; out of demo scope.
- **Tax category routing for ADR-024.** When this sync extends to pull `ProductTaxCategory` from SAP, the tax determination service (ADR-024) can consult it for reduced-rate routing (DE 7% for books, etc.). Closes the gap noted in ADR-024's future state.
- **Material deletion / lifecycle handling.** Periodic reconciliation that marks SF Product2 inactive when SAP deactivates the material. Adds an extra GET that compares full SF catalogue against SAP's active-only material list. ~1 day of additional work.

## Alternatives Considered

1. **Manual material number maintenance.** Rejected — doesn't scale past demo. The sync is the foundation that makes ATP / Tax / Order-Ack work for the full catalogue.
2. **Sync everything (Pricebook entries, classification, bundle composition) from SAP.** Rejected — these are commercial / CRM-side data, not material master. Keeping the boundary clean (SAP = material master only; SF = commercial layers) keeps ownership clear.
3. **Use a third-party MDM (Reltio, Informatica) to mediate.** Too heavy for the demo. Notes in ADR-021 (Customer Master) apply equally here — MDM justifies when catalogue size + complexity warrant.
4. **Use Salesforce Connect / External Object** to query SAP material master live instead of syncing. Slow (every product page-load hits SAP), expensive (Connect license), and most CRM operations need data the External Object can't provide cheaply (search, related lists, etc.). Sync is the right pattern for material master.

## Related Decisions

- ADR-022 (SAP MM ATP Integration) — depends on this sync to populate `SAP_Material_Number__c` so ATP queries have a join key.
- ADR-024 (SAP Tax Determination) — future extension of this sync would pull tax category onto Product2 for reduced-rate routing.
- ADR-023 (SAP SD Sales Order Acknowledgment) — uses `Product2.SAP_Material_Number__c` in the SO payload's line items.
- ADR-015 (Production Externalization Strategy) — the Material Master row of the externalisation table is what this ADR implements.
- ADR-021 (Customer Master / BillTo Source) — sibling sync for customer data. Both follow the same "SAP is the master; SF mirrors via Mule" pattern.
- Future ADR-???: SAP→SF Event Mesh subscription — replaces nightly polling with real-time material-change events when catalogue size + change rate warrant it.

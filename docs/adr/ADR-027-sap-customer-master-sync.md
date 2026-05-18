# ADR-027: SAP Customer Master Sync — Nightly Account Reconciliation from SAP Business Partner

## Status

Accepted — implemented 2026-05-18 in SAP Sprint Phase 6. SapCustomerMasterSyncService + four new Account fields (SAP_BP_Number, SAP_Customer_Category, SAP_Customer_Group, SAP_Last_Synced_At) deployed and verified — 10 SAP business partners fetched in a sandbox test, 10 Accounts created with real German Mittelstand names including Bechtle AG.

## Context

ADR-021 documented the choice for customer master data: SAP Business Partner master is the production system of record; Salesforce Account is a one-way sync mirror; reps edit Account only via a "Request Customer Master Update" workflow that fires an SAP IDoc. The actual sync mechanism wasn't built — that's this ADR.

ADR-026 implemented the sibling pattern for product master (SAP Material → SF Product2). The customer-side sync needed to follow the same shape so reps see a consistent "your SAP-side data is over here" mental model regardless of whether they're looking at Products or Accounts.

Two demo-specific motivations also pushed customer master to the top of the sprint:

1. **ADR-023 (SAP SD Sales Order Acknowledgment)** uses hardcoded SoldToParty=17100001 in the payload because SF Account doesn't carry a SAP customer number yet. That's a known sandbox-only shortcut. Once `Account.SAP_BP_Number__c` is populated by this sync, the Order push payload can read the real BP number from the Order's Account and the hardcoded default goes away. Note: that wiring isn't done in this ADR's scope (deliberate — the sync ships first, the Order push payload upgrade is a follow-up edit).
2. **Recruiter narrative density.** With customer master synced, the recording can say "every Account in our org has a SAP BP number; every Order automatically knows its SAP customer." That's a stronger story than "products are synced but customers aren't yet."

The implementation pattern follows ADR-026 exactly: full-table fetch with configurable top limit, upsert by external id, scoped to data fields only (commercial config stays SF-managed).

## Decision

`SapCustomerMasterSyncService.sync(maxFetch)` is an `@InvocableMethod` that:

1. Calls `GET /s4hanacloud/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner?$top={N}&$filter=BusinessPartnerCategory eq '2'&$format=json` with the standard SAP credentials (APIKey header from SAP_Config__c).
2. Filters server-side to BusinessPartnerCategory='2' (organisations). Persons (Category=1) and groups (Category=3) are skipped — most B2B Accounts are organisations, and persons would clutter the Account list in the demo. Production removes the filter.
3. Parses the OData v2 response `d.results` array.
4. For each SAP BP:
   - Reads `BusinessPartner` (BP number), `BusinessPartnerFullName` (or fallback to BusinessPartnerName / FirstName+LastName), `BusinessPartnerCategory`, `BusinessPartnerGrouping`.
   - Looks up an existing SF Account by `SAP_BP_Number__c = <BusinessPartner>`.
   - If found → update the SAP-side audit fields (Category, Group, Last_Synced_At). Does NOT touch Name (SF Account.Name may have been edited by sales ops; SAP's name is in the audit Category field only).
   - If not found → create a new Account with Name = `[SAP] <BusinessPartnerFullName or BP number fallback>`, plus all the SAP fields.
5. Bulk `Database.upsert allOrNone=false` keyed on Account.SAP_BP_Number__c — bad records (empty BusinessPartner, FLS conflicts) increment failedCount but don't poison the batch.

### Scope boundary — what the sync DOES NOT touch

- **Account addresses (BillingStreet etc.).** SAP Business Partner Address is a separate API call (A_BusinessPartnerAddress) with its own join logic (one BP can have multiple addresses — bill-to, ship-to, dunning, returns). Adding this multiplies the API call count and the matching complexity. Deferred to a future extension; documented in this ADR's Future state.
- **SF-managed Account fields.** Industry, AnnualRevenue, custom pricing tier, owner — all stay sales-ops-managed. The sync is data mirror, not commercial config push.
- **Account.Name on existing records.** New Accounts get a `[SAP] ` prefix; existing matched Accounts keep their SF Name (which sales ops may have customised). SAP-side name lives in audit fields if drift detection is needed.
- **Contact records.** Contact-equivalent SAP entities (BusinessPartnerRelationship, sub-BPs) are a separate sync; out of scope.

### Production deployment

Demo invocation: anonymous Apex calls `SapCustomerMasterSyncService.sync` ad-hoc. Production: Mule scheduled flow at 02:30 CET nightly (30 minutes after Material Master at 02:00 to avoid resource spikes):

1. Mule cron-triggers the flow.
2. Mule calls SAP API_BUSINESS_PARTNER directly (has the same credentials).
3. Mule POSTs the response payload as Composite REST to SF.
4. SF Apex routes to `SapCustomerMasterSyncService.sync` with the payload pre-parsed.

This split moves the SAP callout out of Apex callout limits and lets Mule add retry / DLQ / paging for large BP catalogues. Apex stays as the SF-side commit step.

## Consequences

### Positive

- **Customer-master data dependency closed** for ADR-022 (ATP) and ADR-023 (SO Ack). Both can now read the real Account.SAP_BP_Number__c when building payloads to SAP instead of using the demo hardcoded default.
- **Demo-grade customer data.** Unlike the Material Master sandbox response (mostly empty descriptions), the BP API returns real German Mittelstand company names — Bechtle AG (a real German IT distributor), Cust15 Cust15, Nue tech inc, Expo technologies Plc, Inlandskunde DE 80. The recording shows a recognisable German company list, which lands stronger than numeric SKU codes.
- **Drift detection enabled.** SAP_Customer_Category__c + SAP_Customer_Group__c on Account show what SAP thinks the customer is. If sales ops set an SF-side "Strategic_Account__c=true" but SAP_Customer_Group__c=BP01 (small business group), that's surfaceable in dashboards as a tier-mismatch flag.
- **Upsert by external id is bulk-safe.** Database.upsert with the external id handles "is this a new Account?" vs "is this an existing Account?" in one DML; allOrNone=false absorbs malformed records gracefully.
- **Production migration is mechanical.** Same service signature; Mule pre-parses the payload and calls Composite REST instead of Apex calling SAP directly. SF-side test logic unchanged.

### Negative

- **Demo creates 10+ Account records named `[SAP] ...`.** These are SAP sandbox BPs, not real TechnoStore customers. Browse Catalog / Quote workflows that select Accounts now see this noise. Mitigation: a SOQL filter `WHERE NOT (Name LIKE '[SAP] %')` in any Account-picker UI; or running the sync only against curated sandbox BP ranges.
- **No address sync.** Account.BillingStreet etc. stay empty on synced records (or carry the SF-side legacy data on matched existing Accounts). For Orders against these Accounts, the OrderTriggerHandler.backfillFromAccount logic still runs but has nothing to fall back to. Documented in Future state.
- **Category filter is sandbox-specific.** Filtering to Category=2 makes for clean demo data but loses persons / groups. Production turns the filter off, which then surfaces Category=1 Contact-equivalents that may need different handling (might want them as Contacts under a parent Account rather than standalone Accounts).
- **No deletion handling.** If SAP retires a BP (blocks it or sets `IsMarkedForBPArchiving`), the sync doesn't deactivate the SF Account. Production needs a periodic reconciliation pass marking missing Accounts inactive, or a separate SAP→SF event subscription for BP-status-change events.

### Future state

- **Extend the sync to A_BusinessPartnerAddress** — for each BP, query its address records, populate Account.BillingStreet/City/PostalCode/Country and (if ShipTo address present) ShippingStreet/etc. Roughly 2-3 hours of additional implementation; closes the gap for OrderTriggerHandler.backfillFromAccount.
- **Wire Account.SAP_BP_Number__c into ADR-023 Order push payload** — `SapSalesOrderService.buildSapPayload` currently hardcodes SoldToParty=17100001; should read `o.Account.SAP_BP_Number__c` once accounts are populated. ~15 minute edit.
- **Mule scheduled flow** (production primary path): `mulesoft/sap-customer-master-sync.xml` cron-triggered at 02:30 CET. Mule does the SAP call, posts the JSON to SF Composite REST. ADR-???: SAP Customer Master Mule Flow.
- **Delta sync** when catalogue grows: filter SAP query by `LastChangeDateTime gt {last_sync}`, store last sync timestamp in a Custom Setting. Same pattern as the deferred Material Master delta.
- **BP relationship sync** — when SAP has BusinessPartnerRelationship records connecting a head office to subsidiaries, sync those as Account.ParentId. Useful for enterprise customers with multiple legal entities under one global account.
- **Reverse direction — "Request Customer Master Update" workflow.** When sales rep notices an Account address is wrong, instead of editing Account directly, they file a request that fires an SAP IDoc. SAP updates the BP; the nightly sync brings the update back to SF. Documented in ADR-021; implementation is a separate ADR.

## Alternatives Considered

1. **Manual BP number maintenance.** Rejected for the same reason as ADR-026: doesn't scale, and the dependent integrations (ADR-022, ADR-023) need the field populated to function.
2. **Sync everything (commercial fields like Industry, Annual Revenue) from SAP.** Rejected — those are CRM-side, not customer master. SAP doesn't typically own "Industry" classification the same way SF does (SF Industry is broader/marketing-focused; SAP IndustrySector is narrower/financial). Two systems with two different categorisations should both keep their own.
3. **Use Salesforce Connect / External Object** to query SAP BP live instead of syncing. Same rejection as Material Master in ADR-026: slow, expensive, doesn't support CRM operations cheaply.
4. **Two-way sync** — sales rep edits SF Account, change flows back to SAP. Rejected for the violation-of-single-source-of-truth reason. One-way sync with a separate "request update" workflow keeps SAP as the authoritative system.

## Related Decisions

- ADR-021 (Customer Master / BillTo Source) — the directional choice (SAP BP = master, SF Account = mirror) this ADR implements.
- ADR-022 (SAP MM ATP Integration) — peer; uses Product2.SAP_Material_Number__c from ADR-026. Will use Account.SAP_BP_Number__c once Order push payloads are wired.
- ADR-023 (SAP SD Sales Order Acknowledgment) — peer; current hardcoded SoldToParty=17100001 will read from Account.SAP_BP_Number__c after this sync runs and the payload-build code is upgraded.
- ADR-026 (SAP Material Master Sync) — sibling. Same pattern (full-fetch, upsert by external id, allOrNone=false, scope-boundary discipline), different domain.
- ADR-015 (Production Externalization Strategy) — the Customer Master row of the externalisation table points to this ADR.
- ADR-005 (Kevin O'Hara TriggerHandler) — applies because new Account creation runs through any AccountTriggerHandler that exists in the org; sync respects that.
- Future ADR-???: SAP A_BusinessPartnerAddress sync — address-level extension.
- Future ADR-???: Request Customer Master Update workflow — the reverse-direction edit path.

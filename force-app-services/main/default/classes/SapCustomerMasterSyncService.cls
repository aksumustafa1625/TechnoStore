/**
 * SAP Customer Master Sync — nightly Account reconciliation from SAP Business Partner (ADR-027).
 *
 * Sibling of SapMaterialMasterSyncService (ADR-026): same pattern, different domain.
 * Material Master pulls product data; Customer Master pulls customer data.
 *
 * Pulls Business Partner records from SAP API_BUSINESS_PARTNER and upserts them into
 * Salesforce Account by SAP_BP_Number__c (external id). The production version runs
 * nightly at 02:30 CET via Mule scheduled flow (staggered from Material Master sync at
 * 02:00 to avoid resource contention). The demo version is a directly-invokable
 * @InvocableMethod so anonymous Apex / manual button can trigger fresh syncs.
 *
 * Sync strategy: full-table fetch (top N) rather than delta. SAP BP master in Mittelstand
 * DACH typically holds 5-50k customers — full fetch is acceptable nightly bandwidth-wise.
 * Delta sync migration documented in ADR-027 future-state for very large catalogues.
 *
 * Match rule: SAP_BP_Number__c is the external id. If an Account already exists with
 * that BP number, it gets the SAP audit fields refreshed; otherwise a new Account is
 * created with Name = BusinessPartnerFullName (or BusinessPartnerName fallback).
 *
 * Scope boundary (per ADR-021): the sync touches Name, SAP_BP_Number, SAP_Customer_Category,
 * SAP_Customer_Group, SAP_Last_Synced_At. Address fields are NOT touched in this version
 * because address sync requires a separate SAP call (A_BusinessPartnerAddress) — planned
 * extension. The sync also does NOT touch SF-managed fields like Industry, AnnualRevenue,
 * Custom_Pricing_Tier__c — those are commercial config owned by sales ops.
 */
public with sharing class SapCustomerMasterSyncService {

    public class Request {
        @InvocableVariable(label='Max BPs to fetch (default 25)')
        public Integer maxFetch;
    }

    public class Result {
        @InvocableVariable(label='Total fetched from SAP')
        public Integer totalFetched;
        @InvocableVariable(label='Created')
        public Integer createdCount;
        @InvocableVariable(label='Updated')
        public Integer updatedCount;
        @InvocableVariable(label='Failed')
        public Integer failedCount;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Sync SAP Customer Master to Salesforce' description='Calls SAP API_BUSINESS_PARTNER, upserts Account by SAP_BP_Number__c. Production calls this nightly via Mule; demo can call ad-hoc.')
    public static List<Result> sync(List<Request> requests) {
        List<Result> results = new List<Result>();
        Integer maxFetch = 25;
        if (requests != null && !requests.isEmpty() && requests[0].maxFetch != null && requests[0].maxFetch > 0) {
            maxFetch = Math.min(requests[0].maxFetch, 200);
        }

        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        Result res = new Result();
        res.totalFetched = 0; res.createdCount = 0; res.updatedCount = 0; res.failedCount = 0;
        if (cfg == null || String.isBlank(cfg.API_Base_URL__c) || String.isBlank(cfg.API_Key__c)) {
            res.status = 'Error';
            res.message = 'SAP_Config__c missing or incomplete.';
            results.add(res);
            return results;
        }

        String baseUrl = cfg.API_Base_URL__c;
        if (!baseUrl.startsWith('http')) baseUrl = 'https://' + baseUrl;
        // Filter to organisations only (Category=2) for the demo; persons (1) and groups (3)
        // tend to be noise. Production removes the filter.
        String endpoint = baseUrl
            + '/s4hanacloud/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner'
            + '?$top=' + maxFetch
            + '&$filter=BusinessPartnerCategory%20eq%20%272%27'
            + '&$format=json';

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('APIKey', cfg.API_Key__c);
            req.setHeader('Accept', 'application/json');
            req.setHeader('Accept-Encoding', 'identity');
            req.setTimeout(60000);

            HttpResponse resp = new Http().send(req);
            if (resp.getStatusCode() != 200) {
                res.status = 'Error';
                res.message = 'SAP HTTP ' + resp.getStatusCode() + ': ' + resp.getBody().abbreviate(300);
                results.add(res);
                return results;
            }

            // Parse OData v2 response: { d: { results: [ { BusinessPartner, BusinessPartnerFullName, ... } ] } }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            List<Map<String, Object>> sapBps = new List<Map<String, Object>>();
            if (body.get('d') instanceof Map<String, Object>) {
                Object rs = ((Map<String, Object>) body.get('d')).get('results');
                if (rs instanceof List<Object>) {
                    for (Object o : (List<Object>) rs) {
                        if (o instanceof Map<String, Object>) sapBps.add((Map<String, Object>) o);
                    }
                }
            }
            res.totalFetched = sapBps.size();
            if (sapBps.isEmpty()) {
                res.status = 'Success';
                res.message = 'SAP returned 0 business partners; nothing to sync.';
                results.add(res);
                return results;
            }

            // Find existing Account records keyed by SAP BP number.
            Set<String> sapBpIds = new Set<String>();
            for (Map<String, Object> sp : sapBps) {
                String b = String.valueOf(sp.get('BusinessPartner'));
                if (String.isNotBlank(b)) sapBpIds.add(b);
            }
            Map<String, Account> existingByBp = new Map<String, Account>();
            for (Account a : [SELECT Id, Name, SAP_BP_Number__c, SAP_Customer_Category__c, SAP_Customer_Group__c FROM Account WHERE SAP_BP_Number__c IN :sapBpIds]) {
                existingByBp.put(a.SAP_BP_Number__c, a);
            }

            Datetime now = System.now();
            List<Account> upserts = new List<Account>();
            for (Map<String, Object> sp : sapBps) {
                String bp = String.valueOf(sp.get('BusinessPartner'));
                if (String.isBlank(bp)) continue;
                String bpName = pickName(sp);
                String bpCategory = sp.get('BusinessPartnerCategory') == null ? null : String.valueOf(sp.get('BusinessPartnerCategory'));
                String bpGroup = sp.get('BusinessPartnerGrouping') == null ? null : String.valueOf(sp.get('BusinessPartnerGrouping'));

                Account a;
                if (existingByBp.containsKey(bp)) {
                    a = existingByBp.get(bp);
                    a.SAP_Customer_Category__c = bpCategory;
                    a.SAP_Customer_Group__c = bpGroup;
                    a.SAP_Last_Synced_At__c = now;
                    res.updatedCount++;
                } else {
                    a = new Account(
                        Name = '[SAP] ' + (String.isBlank(bpName) ? bp : bpName),
                        SAP_BP_Number__c = bp,
                        SAP_Customer_Category__c = bpCategory,
                        SAP_Customer_Group__c = bpGroup,
                        SAP_Last_Synced_At__c = now
                    );
                    res.createdCount++;
                }
                upserts.add(a);
            }

            if (!upserts.isEmpty()) {
                Database.UpsertResult[] saveRes = Database.upsert(upserts, Account.SAP_BP_Number__c, false);
                Integer failed = 0;
                for (Database.UpsertResult ur : saveRes) {
                    if (!ur.isSuccess()) failed++;
                }
                res.failedCount = failed;
            }

            res.status = 'Success';
            res.message = String.format('Synced {0} SAP business partners: {1} created, {2} updated, {3} failed.',
                new List<Object>{ res.totalFetched, res.createdCount, res.updatedCount, res.failedCount });
        } catch (Exception e) {
            res.status = 'Error';
            res.message = e.getTypeName() + ': ' + e.getMessage();
        }
        results.add(res);
        return results;
    }

    @TestVisible
    private static String pickName(Map<String, Object> sp) {
        Object full = sp.get('BusinessPartnerFullName');
        if (full != null && String.isNotBlank(String.valueOf(full))) return String.valueOf(full);
        Object bpName = sp.get('BusinessPartnerName');
        if (bpName != null && String.isNotBlank(String.valueOf(bpName))) return String.valueOf(bpName);
        Object firstName = sp.get('FirstName');
        Object lastName = sp.get('LastName');
        String combined = (firstName == null ? '' : String.valueOf(firstName))
            + ' '
            + (lastName == null ? '' : String.valueOf(lastName));
        return combined.trim();
    }
}

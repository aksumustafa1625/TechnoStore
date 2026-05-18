/**
 * SAP Material Master Sync — nightly Product2 reconciliation (ADR-026).
 *
 * Pulls product master records from SAP API_PRODUCT_SRV and upserts them
 * into Salesforce Product2 by SAP_Material_Number__c (external id). The
 * production version is a Mule scheduled flow running nightly at 02:00
 * CET that hands the batch to this Apex via Composite REST. The demo
 * version is a directly-invokable @InvocableMethod, so anonymous Apex
 * (or a manual button) can trigger a fresh sync at any time.
 *
 * Sync strategy: full-table fetch (top N) rather than delta. SAP's
 * material master is small enough (typically a few thousand SKUs) that
 * a nightly full fetch is simpler than delta tracking. Production may
 * shift to delta when catalogue size justifies it; the upsert pattern
 * works for both.
 *
 * Match rule: SAP_Material_Number__c is the external id. If a Product2
 * already exists with that material number, it's updated; otherwise a
 * new Product2 is created with Type=null (compatible with Industries
 * CPQ Product Qualification per memory product_qualification_demo_setup).
 *
 * NOT a replacement for sales-rep-managed product attributes. The sync
 * touches name + description + SAP_Material_Number__c + SAP_Last_Synced_At__c
 * only. Pricebook entries, classification, bundle composition, attribute
 * adjustments — those stay SF-managed because they're commercial config,
 * not material master.
 */
public with sharing class SapMaterialMasterSyncService {

    public class Request {
        @InvocableVariable(label='Max materials to fetch (default 25)')
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

    @InvocableMethod(label='Sync SAP Material Master to Salesforce' description='Calls SAP API_PRODUCT_SRV, upserts Product2 by SAP_Material_Number__c. Production calls this nightly via Mule; demo can call ad-hoc.')
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
        String endpoint = baseUrl + '/s4hanacloud/sap/opu/odata/sap/API_PRODUCT_SRV/A_Product?$top=' + maxFetch + '&$format=json';

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

            // Parse OData v2 response: { d: { results: [ { Product, ProductDescription, ... } ] } }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            List<Map<String, Object>> sapProducts = new List<Map<String, Object>>();
            if (body.get('d') instanceof Map<String, Object>) {
                Object rs = ((Map<String, Object>) body.get('d')).get('results');
                if (rs instanceof List<Object>) {
                    for (Object o : (List<Object>) rs) {
                        if (o instanceof Map<String, Object>) sapProducts.add((Map<String, Object>) o);
                    }
                }
            }
            res.totalFetched = sapProducts.size();
            if (sapProducts.isEmpty()) {
                res.status = 'Success';
                res.message = 'SAP returned 0 products; nothing to sync.';
                results.add(res);
                return results;
            }

            // Find existing Product2 records keyed by SAP material number.
            Set<String> sapMatlIds = new Set<String>();
            for (Map<String, Object> sp : sapProducts) {
                String m = String.valueOf(sp.get('Product'));
                if (String.isNotBlank(m)) sapMatlIds.add(m);
            }
            Map<String, Product2> existingByMatl = new Map<String, Product2>();
            for (Product2 p : [SELECT Id, Name, SAP_Material_Number__c, SAP_Product_Description__c FROM Product2 WHERE SAP_Material_Number__c IN :sapMatlIds]) {
                existingByMatl.put(p.SAP_Material_Number__c, p);
            }

            Datetime now = System.now();
            List<Product2> upserts = new List<Product2>();
            for (Map<String, Object> sp : sapProducts) {
                String matl = String.valueOf(sp.get('Product'));
                if (String.isBlank(matl)) continue;
                String productDescription = sp.get('ProductDescription') == null ? null : String.valueOf(sp.get('ProductDescription'));
                if (String.isBlank(productDescription)) productDescription = sp.get('ProductOldID') == null ? matl : String.valueOf(sp.get('ProductOldID'));

                Product2 p;
                if (existingByMatl.containsKey(matl)) {
                    p = existingByMatl.get(matl);
                    p.SAP_Product_Description__c = productDescription;
                    p.SAP_Last_Synced_At__c = now;
                    res.updatedCount++;
                } else {
                    p = new Product2(
                        Name = '[SAP] ' + (String.isBlank(productDescription) ? matl : productDescription),
                        IsActive = true,
                        SAP_Material_Number__c = matl,
                        SAP_Product_Description__c = productDescription,
                        SAP_Last_Synced_At__c = now
                    );
                    res.createdCount++;
                }
                upserts.add(p);
            }

            if (!upserts.isEmpty()) {
                Database.UpsertResult[] saveRes = Database.upsert(upserts, Product2.SAP_Material_Number__c, false);
                Integer failed = 0;
                for (Database.UpsertResult ur : saveRes) {
                    if (!ur.isSuccess()) failed++;
                }
                res.failedCount = failed;
            }

            res.status = 'Success';
            res.message = String.format('Synced {0} SAP materials: {1} created, {2} updated, {3} failed.',
                new List<Object>{ res.totalFetched, res.createdCount, res.updatedCount, res.failedCount });
        } catch (Exception e) {
            res.status = 'Error';
            res.message = e.getTypeName() + ': ' + e.getMessage();
        }
        results.add(res);
        return results;
    }
}

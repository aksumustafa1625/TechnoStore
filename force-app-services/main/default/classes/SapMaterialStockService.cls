/**
 * SAP MM ATP Integration — Material Stock Service
 *
 * Calls SAP S/4HANA Cloud Sandbox API_MATERIAL_STOCK_SRV to get real-time
 * available-to-promise (ATP) quantity for a Material. Used by the inventory
 * check flow as the "SAP-first" leg of the hybrid SAP-first / JIRA-fallback
 * pattern (see ADR-022).
 *
 * The SAP API Hub Sandbox URL pattern is:
 *   {host}/s4hanacloud/sap/opu/odata/sap/API_MATERIAL_STOCK_SRV/A_MatlStkInAcctMod?$filter=Material eq 'XXX'
 *
 * Authentication: APIKey header sourced from SAP_Config__c Custom Setting
 * (org-default record). Same credential block used by all SAP-related Apex
 * services (SapSalesOrderService etc.) and by the parallel Mule integration
 * layer (mulesoft/sap-integration-FULL.xml).
 *
 * Production target (per ADR-015): this Apex call routes through MuleSoft
 * which adds retry / DLQ / idempotency. The demo calls SAP direct because
 * keeping Mule out of the loop simplifies the recording. The Apex method
 * signature stays the same when the call moves behind Mule.
 */
public with sharing class SapMaterialStockService {

    public class Request {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    public class Result {
        @InvocableVariable(label='Order Id')
        public Id orderId;
        @InvocableVariable(label='SAP Material Number')
        public String sapMaterialNumber;
        @InvocableVariable(label='Available Quantity (per SAP)')
        public Decimal availableQuantity;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Check SAP Material Stock for Order' description='Calls SAP MM API_MATERIAL_STOCK_SRV for the primary product on the Order, writes SAP_Available_Quantity__c + SAP_Inventory_Checked_At__c back to the Order, returns the ATP number.')
    public static List<Result> checkOrderStock(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.API_Base_URL__c) || String.isBlank(cfg.API_Key__c)) {
            for (Request r : requests) {
                Result res = new Result();
                res.orderId = r.orderId;
                res.status = 'Error';
                res.message = 'SAP_Config__c missing or incomplete.';
                results.add(res);
            }
            return results;
        }

        Set<Id> orderIds = new Set<Id>();
        for (Request r : requests) if (r.orderId != null) orderIds.add(r.orderId);
        if (orderIds.isEmpty()) return results;

        // Fetch the first OrderItem on each Order — demo treats the primary line as the gating product.
        // Production would aggregate across all lines and surface per-line ATP, but the demo flow is
        // single-product-bundle so one lookup is enough.
        Map<Id, OrderItem> primaryItemByOrder = new Map<Id, OrderItem>();
        Map<Id, String> sapMaterialByOrder = new Map<Id, String>();
        for (OrderItem oi : [
            SELECT Id, OrderId, Quantity, Product2.Name, Product2.SAP_Material_Number__c
            FROM OrderItem
            WHERE OrderId IN :orderIds
            AND Product2.SAP_Material_Number__c != null
            ORDER BY CreatedDate ASC
        ]) {
            if (!primaryItemByOrder.containsKey(oi.OrderId)) {
                primaryItemByOrder.put(oi.OrderId, oi);
                sapMaterialByOrder.put(oi.OrderId, oi.Product2.SAP_Material_Number__c);
            }
        }

        String baseUrl = cfg.API_Base_URL__c;
        if (!baseUrl.startsWith('http')) baseUrl = 'https://' + baseUrl;
        Datetime now = System.now();
        List<Order> ordersToUpdate = new List<Order>();

        for (Request r : requests) {
            Result res = new Result();
            res.orderId = r.orderId;

            OrderItem primary = primaryItemByOrder.get(r.orderId);
            if (primary == null) {
                res.status = 'Skipped';
                res.message = 'No OrderItem with a SAP_Material_Number__c found on this Order.';
                results.add(res);
                continue;
            }

            String sapMatl = sapMaterialByOrder.get(r.orderId);
            res.sapMaterialNumber = sapMatl;

            String endpoint = baseUrl
                + '/s4hanacloud/sap/opu/odata/sap/API_MATERIAL_STOCK_SRV/A_MatlStkInAcctMod'
                + '?$filter=Material%20eq%20%27' + EncodingUtil.urlEncode(sapMatl, 'UTF-8') + '%27'
                + '&$format=json';

            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setHeader('APIKey', cfg.API_Key__c);
                req.setHeader('Accept', 'application/json');
                req.setHeader('Accept-Encoding', 'identity');
                req.setTimeout(30000);

                HttpResponse resp = new Http().send(req);
                Integer status = resp.getStatusCode();
                if (status < 200 || status >= 300) {
                    res.status = 'Error';
                    res.message = 'SAP HTTP ' + status + ': ' + resp.getBody().abbreviate(200);
                    results.add(res);
                    continue;
                }

                // Parse OData v2: { d: { results: [ { MatlWrhsStkQtyInMatlBaseUnit, ... }, ... ] } }
                Decimal totalAvailable = 0;
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
                Object d = body.get('d');
                if (d instanceof Map<String, Object>) {
                    Object resultsObj = ((Map<String, Object>) d).get('results');
                    if (resultsObj instanceof List<Object>) {
                        for (Object rowObj : (List<Object>) resultsObj) {
                            if (rowObj instanceof Map<String, Object>) {
                                Map<String, Object> row = (Map<String, Object>) rowObj;
                                Object qty = row.get('MatlWrhsStkQtyInMatlBaseUnit');
                                if (qty == null) qty = row.get('UnrstrcdUseStkQtyInMatlBaseUnit');
                                if (qty == null) qty = row.get('QuantityInBaseUnit');
                                if (qty != null) {
                                    totalAvailable += Decimal.valueOf(String.valueOf(qty));
                                }
                            }
                        }
                    }
                }

                res.availableQuantity = totalAvailable;
                res.status = 'Success';
                res.message = 'SAP reports ' + totalAvailable + ' units available for material ' + sapMatl;

                ordersToUpdate.add(new Order(
                    Id = r.orderId,
                    SAP_Available_Quantity__c = totalAvailable,
                    SAP_Inventory_Checked_At__c = now
                ));
            } catch (Exception e) {
                res.status = 'Error';
                res.message = e.getTypeName() + ': ' + e.getMessage();
            }
            results.add(res);
        }

        if (!ordersToUpdate.isEmpty()) {
            try {
                update ordersToUpdate;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Failed to write SAP ATP fields back to Order(s): ' + e.getMessage());
            }
        }
        return results;
    }
}

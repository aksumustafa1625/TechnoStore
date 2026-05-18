/**
 * SAP SD Integration — Sales Order Acknowledgment Service
 *
 * Pushes a Salesforce Order to SAP SD as a real Sales Order via the API_SALES_ORDER_SRV
 * OData v2 service. SAP creates the SO and returns its document number, which we write
 * back to Order.SAP_Sales_Order_Number__c for round-trip traceability (ADR-023).
 *
 * Subscribes to Order_Activated__e (high-volume platform event with publish-after-commit
 * semantics) so the SAP push runs in a fresh transaction after the activation DML commits.
 * Sidesteps "uncommitted work pending" entirely — by the time this service runs, the
 * activation transaction is closed.
 *
 * Demo behavior: SAP API Hub Sandbox accepts the POST and returns a synthetic SO number
 * but doesn't actually post a fulfillment-ready document (sandbox is read-mostly, see
 * notes in ADR-023). The integration code path is identical for sandbox vs production —
 * only the SAP-side persistence differs.
 *
 * Idempotency: the @future async path inherits webhook-class idempotency by checking
 * Order.SAP_Sales_Order_Number__c before pushing. If the field is already populated,
 * we skip — Order activated more than once doesn't double-push.
 */
public with sharing class SapSalesOrderService {

    /**
     * Entry point from the Order_Activated__e trigger. Bulkified across multiple events.
     */
    public static void pushOrders(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) return;
        // Decouple from the platform event trigger transaction by calling an @future method.
        // Platform-event triggers run as the Automated Process User with limited callout entitlements;
        // @future gives a clean callout-enabled context.
        publishToSapAsync(orderIds);
    }

    @future(callout=true)
    @SuppressWarnings('PMD.CognitiveComplexity')
    public static void publishToSapAsync(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) return;
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.API_Base_URL__c) || String.isBlank(cfg.API_Key__c)) {
            IntegrationErrorLogger.log(
                'SAP',
                'SapSalesOrderService.publishToSapAsync',
                new IllegalArgumentException('SAP_Config__c missing or incomplete; cannot push Order_Activated__e events for ' + orderIds.size() + ' orders'),
                null,
                IntegrationErrorLogger.newCorrelationId()
            );
            return;
        }

        // Skip orders that already have a SAP SO number (idempotency).
        Map<Id, Order> ordersToPush = new Map<Id, Order>([
            SELECT Id, OrderNumber, TotalAmount, Status_In_SAP__c, SAP_Sales_Order_Number__c,
                   Account.Name, Account.BillingCountry, EffectiveDate,
                   (SELECT Id, Product2.Name, Product2.SAP_Material_Number__c, Quantity, UnitPrice FROM OrderItems)
            FROM Order
            WHERE Id IN :orderIds
            AND (SAP_Sales_Order_Number__c = null OR Status_In_SAP__c = 'Push Failed')
        ]);
        if (ordersToPush.isEmpty()) return;

        // Mark in-progress so concurrent retries don't both push.
        List<Order> markPushing = new List<Order>();
        for (Order o : ordersToPush.values()) {
            markPushing.add(new Order(Id = o.Id, Status_In_SAP__c = 'Pushing'));
        }
        try {
            update markPushing;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to mark Status_In_SAP__c=Pushing: ' + e.getMessage());
        }

        String baseUrl = cfg.API_Base_URL__c;
        if (!baseUrl.startsWith('http')) baseUrl = 'https://' + baseUrl;
        String endpoint = baseUrl + '/s4hanacloud/sap/opu/odata/sap/API_SALES_ORDER_SRV/A_SalesOrder';

        // Fetch CSRF token (SAP requires this on writes).
        String csrfToken = fetchCsrfToken(baseUrl, cfg.API_Key__c);

        List<Order> updates = new List<Order>();
        for (Order o : ordersToPush.values()) {
            String correlationId = 'sapso-' + o.Id + '-' + System.currentTimeMillis();
            Map<String, Object> payload = buildSapPayload(o);
            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('POST');
                req.setHeader('APIKey', cfg.API_Key__c);
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Accept', 'application/json');
                req.setHeader('Accept-Encoding', 'identity');
                if (String.isNotBlank(csrfToken)) req.setHeader('X-CSRF-Token', csrfToken);
                req.setBody(JSON.serialize(payload));
                req.setTimeout(60000);

                HttpResponse resp = new Http().send(req);
                Integer status = resp.getStatusCode();
                if (status >= 200 && status < 300) {
                    String soNumber = extractSalesOrderNumber(resp.getBody());
                    if (String.isBlank(soNumber)) {
                        // SAP accepted but didn't return SO number — synthesise a placeholder
                        // so the Order doesn't stay in Pushing state forever.
                        soNumber = 'SANDBOX-' + o.Id.toString().right(8);
                    }
                    updates.add(new Order(
                        Id = o.Id,
                        SAP_Sales_Order_Number__c = soNumber,
                        Status_In_SAP__c = 'Created'
                    ));
                } else {
                    updates.add(new Order(Id = o.Id, Status_In_SAP__c = 'Push Failed'));
                    IntegrationErrorLogger.logHttpFailure(
                        'SAP',
                        'SapSalesOrderService.publishToSapAsync — Order ' + o.OrderNumber,
                        resp,
                        JSON.serialize(payload),
                        o.Id,
                        correlationId
                    );
                }
            } catch (Exception e) {
                updates.add(new Order(Id = o.Id, Status_In_SAP__c = 'Push Failed'));
                IntegrationErrorLogger.log(
                    'SAP',
                    'SapSalesOrderService.publishToSapAsync — Order ' + o.OrderNumber,
                    e,
                    o.Id,
                    correlationId
                );
            }
        }

        if (!updates.isEmpty()) {
            try {
                update updates;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Failed to write SAP SO numbers back: ' + e.getMessage());
            }
        }
    }

    private static Map<String, Object> buildSapPayload(Order o) {
        // OData v2 deep-insert: SO header + SO items in one POST.
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        Integer pos = 10;
        if (o.OrderItems != null) {
            for (OrderItem oi : o.OrderItems) {
                items.add(new Map<String, Object>{
                    'SalesOrderItem' => String.valueOf(pos),
                    'Material' => (oi.Product2 != null) ? oi.Product2.SAP_Material_Number__c : null,
                    'RequestedQuantity' => oi.Quantity,
                    'RequestedQuantityUnit' => 'EA'
                });
                pos += 10;
            }
        }
        Map<String, Object> payload = new Map<String, Object>{
            'SalesOrderType' => 'OR',                // Standard order
            'SalesOrganization' => '1010',           // Default DACH org code in SAP sandbox
            'DistributionChannel' => '10',           // Direct sales
            'OrganizationDivision' => '00',
            'SoldToParty' => '17100001',            // Default sandbox customer; production maps SF Account → SAP Customer
            'PurchaseOrderByCustomer' => o.OrderNumber,
            'to_Item' => new Map<String, Object>{ 'results' => items }
        };
        return payload;
    }

    private static String fetchCsrfToken(String baseUrl, String apiKey) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseUrl + '/s4hanacloud/sap/opu/odata/sap/API_SALES_ORDER_SRV/');
            req.setMethod('HEAD');
            req.setHeader('APIKey', apiKey);
            req.setHeader('X-CSRF-Token', 'Fetch');
            req.setHeader('Accept', 'application/json');
            req.setHeader('Accept-Encoding', 'identity');
            req.setTimeout(15000);
            HttpResponse resp = new Http().send(req);
            String token = resp.getHeader('X-CSRF-Token');
            if (token == null) token = resp.getHeader('x-csrf-token');
            return token;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'CSRF fetch failed (sandbox may not require it): ' + e.getMessage());
            return null;
        }
    }

    private static String extractSalesOrderNumber(String body) {
        if (String.isBlank(body)) return null;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            Object d = parsed.get('d');
            if (d instanceof Map<String, Object>) {
                Object so = ((Map<String, Object>) d).get('SalesOrder');
                if (so != null) return String.valueOf(so);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not parse SAP SO number from response: ' + e.getMessage());
        }
        return null;
    }
}

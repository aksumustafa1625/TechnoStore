/**
 * Routes inbound SAP CloudEvents to the appropriate domain service based on the
 * CloudEvent "type" field (ADR-028).
 *
 * Called directly by SapEventWebhook after HMAC validation + idempotency check.
 * The webhook hands the dispatcher a parsed CloudEvent envelope (id, type, subject,
 * source, data) instead of going through a platform-event indirection step. The
 * platform-event indirection from ADR-003 was the original plan; this org has hit
 * the Developer Edition custom-object cap (platform events count) so the dispatch
 * runs inline in the webhook transaction. Production org with no custom-object
 * pressure can reintroduce the SAP_Inbound_Event__e platform event for trust-
 * boundary cleanness — the dispatcher signature is unchanged.
 *
 * Type-prefix routing rules (extensible — add a new branch per SAP entity):
 *
 *   sap.s4.beh.salesorder.*       → updateSalesOrderStatus
 *   sap.s4.beh.businesspartner.*  → refreshBusinessPartner
 *   sap.s4.beh.product.*          → refreshProduct
 *   sap.s4.beh.payment.*          → recordPayment
 *
 * Each route is small — parses the event payload, locates the matching SF record
 * by the SAP key (Order.SAP_Sales_Order_Number__c, Account.SAP_BP_Number__c,
 * Product2.SAP_Material_Number__c, Invoice.SAP_Payment_Reference__c), and updates
 * the SF audit fields. Heavy lifting stays in the Sap*Service classes from the
 * SAP sync sprint.
 *
 * Runs as `without sharing` so guest-user-context webhook updates land via
 * Database.update with allOrNone=false. Failures route to Integration_Error__c
 * via IntegrationErrorLogger so the Integration Health dashboard surfaces them.
 */
public without sharing class SapInboundEventDispatcher {

    public class CloudEvent {
        public String eventId;
        public String eventType;
        public String subject;
        public String source;
        public Map<String, Object> data;
    }

    public static void dispatch(CloudEvent e) {
        if (e == null) return;
        String correlationId = IntegrationErrorLogger.newCorrelationId();
        try {
            String t = (e.eventType == null) ? '' : e.eventType.toLowerCase();
            if (t.startsWith('sap.s4.beh.salesorder.')) {
                updateSalesOrderStatus(e, correlationId);
            } else if (t.startsWith('sap.s4.beh.businesspartner.')) {
                refreshBusinessPartner(e, correlationId);
            } else if (t.startsWith('sap.s4.beh.product.')) {
                refreshProduct(e, correlationId);
            } else if (t.startsWith('sap.s4.beh.payment.')) {
                recordPayment(e, correlationId);
            } else {
                System.debug(LoggingLevel.INFO, 'SapInboundEventDispatcher unknown type: ' + e.eventType);
            }
        } catch (Exception ex) {
            IntegrationErrorLogger.log('SAP', 'SapInboundEventDispatcher — ' + e.eventType, ex, null, correlationId);
        }
    }

    // ============================================================
    // ROUTE: SalesOrder status change
    // ============================================================
    private static void updateSalesOrderStatus(CloudEvent e, String correlationId) {
        String sapSo = e.subject;
        if (String.isBlank(sapSo)) return;

        String overallStatus = null;
        if (e.data != null) {
            Object s = e.data.get('OverallSDProcessStatus');
            if (s != null) overallStatus = String.valueOf(s);
        }
        String sfStatus = mapSapStatus(overallStatus);

        List<Order> matches = [SELECT Id, OrderNumber, Status_In_SAP__c FROM Order WHERE SAP_Sales_Order_Number__c = :sapSo LIMIT 1];
        if (matches.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'No Order found for SAP SO ' + sapSo + ' (event ' + e.eventId + ')');
            return;
        }
        Order o = matches[0];
        Order upd = new Order(Id = o.Id, Status_In_SAP__c = sfStatus);
        Database.SaveResult sr = Database.update(upd, false);
        if (!sr.isSuccess()) {
            IntegrationErrorLogger.log('SAP', 'SapInboundEventDispatcher.updateSalesOrderStatus', new IllegalArgumentException(sr.getErrors()[0].getMessage()), o.Id, correlationId);
        }
    }

    private static String mapSapStatus(String sapCode) {
        if (sapCode == null) return null;
        switch on sapCode {
            when 'A' { return 'Created'; }
            when 'B' { return 'Created'; }
            when 'C' { return 'Fulfilled'; }
            when 'V' { return 'Cancelled'; }
            when else { return null; }
        }
    }

    // ============================================================
    // ROUTE: BusinessPartner refresh
    // ============================================================
    private static void refreshBusinessPartner(CloudEvent e, String correlationId) {
        String bpNumber = e.subject;
        if (String.isBlank(bpNumber)) return;

        String bpGroup = null;
        if (e.data != null && e.data.get('BusinessPartnerGrouping') != null) {
            bpGroup = String.valueOf(e.data.get('BusinessPartnerGrouping'));
        }

        List<Account> matches = [SELECT Id FROM Account WHERE SAP_BP_Number__c = :bpNumber LIMIT 1];
        if (matches.isEmpty()) return;

        Account upd = new Account(Id = matches[0].Id, SAP_Last_Synced_At__c = System.now());
        if (String.isNotBlank(bpGroup)) upd.SAP_Customer_Group__c = bpGroup;
        Database.update(upd, false);
    }

    // ============================================================
    // ROUTE: Product (material) refresh
    // ============================================================
    private static void refreshProduct(CloudEvent e, String correlationId) {
        String matlNumber = e.subject;
        if (String.isBlank(matlNumber)) return;

        String matlDescription = null;
        if (e.data != null && e.data.get('ProductDescription') != null) {
            matlDescription = String.valueOf(e.data.get('ProductDescription'));
        }

        List<Product2> matches = [SELECT Id FROM Product2 WHERE SAP_Material_Number__c = :matlNumber LIMIT 1];
        if (matches.isEmpty()) return;
        Product2 upd = new Product2(Id = matches[0].Id, SAP_Last_Synced_At__c = System.now());
        if (String.isNotBlank(matlDescription)) upd.SAP_Product_Description__c = matlDescription;
        Database.update(upd, false);
    }

    // ============================================================
    // ROUTE: Payment posting
    // ============================================================
    private static void recordPayment(CloudEvent e, String correlationId) {
        String paymentRef = e.subject;
        if (String.isBlank(paymentRef)) return;

        List<Invoice> matches = [SELECT Id FROM Invoice WHERE SAP_Payment_Reference__c = :paymentRef LIMIT 1];
        if (matches.isEmpty()) return;
        Invoice upd = new Invoice(Id = matches[0].Id, SAP_Payment_Posted_At__c = System.now());
        Database.update(upd, false);
    }
}

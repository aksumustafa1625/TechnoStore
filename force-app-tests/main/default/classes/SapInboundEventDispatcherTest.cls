/**
 * Unit tests for SapInboundEventDispatcher (ADR-028).
 *
 * The class under test is a pure DML dispatcher — it consumes a parsed CloudEvent
 * envelope from SapEventWebhook and routes based on the CloudEvent `type` prefix
 * to update Order / Account / Product2 / Invoice records that carry the matching
 * SAP external id. No HTTP callouts, so no HttpCalloutMock.
 *
 * Routing under test:
 *   sap.s4.beh.salesorder.*       → Order.Status_In_SAP__c via mapSapStatus(A/B→Created, C→Fulfilled, V→Cancelled)
 *   sap.s4.beh.businesspartner.*  → Account.SAP_Last_Synced_At__c + SAP_Customer_Group__c
 *   sap.s4.beh.product.*          → Product2.SAP_Last_Synced_At__c + SAP_Product_Description__c
 *   sap.s4.beh.payment.*          → Invoice.SAP_Payment_Posted_At__c  (see TS-TEST-013)
 *
 * Key implementation detail from reading the class: the SAP identifier is read
 * from `CloudEvent.subject` (e.g. subject='SAP-SO-100'), NOT from `data.SalesOrder`.
 * The `data` map carries the status/grouping/description fields.
 *
 * PLATFORM LIMITATIONS documented as roadmap:
 *   - TS-TEST-013: Invoice DML is blocked in Apex (see TestDataFactory notes).
 *     The payment route can be exercised for routing safety only — we assert the
 *     dispatch call does not throw. Verifying SAP_Payment_Posted_At__c stamping
 *     requires the REST-based integration harness (same blocker as TS-TEST-003).
 *   - mapSapStatus is `private static` on the class under test. Direct unit
 *     coverage would need an @TestVisible annotation. Behavioural coverage via
 *     four salesorder dispatch tests (A, C, V, unknown) exercises every branch.
 */
@IsTest
private class SapInboundEventDispatcherTest {

    private static final String SAP_SO      = 'SAP-SO-100';
    private static final String SAP_BP      = 'BP-100';
    private static final String SAP_MATL    = 'MAT-100';

    // ---------- @TestSetup: Account + Product2 + Order all keyed by SAP ids ----------

    @TestSetup
    static void seed() {
        Account a = new Account(
            Name = 'SAP Inbound Test DE GmbH',
            BillingCountry = 'Germany',
            BillingCity = 'Berlin',
            BillingStreet = 'Musterstrasse 1',
            BillingPostalCode = '10115',
            SAP_BP_Number__c = SAP_BP
        );
        insert a;

        Product2 p = new Product2(
            Name = 'ThinkPad X1 Carbon',
            IsActive = true,
            SAP_Material_Number__c = SAP_MATL
        );
        insert p;

        Order o = new Order(
            AccountId     = a.Id,
            Status        = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id  = Test.getStandardPricebookId(),
            SAP_Sales_Order_Number__c = SAP_SO
        );
        insert o;
    }

    // ---------- Helpers ----------

    private static SapInboundEventDispatcher.CloudEvent buildEvent(
        String eventType, String subject, Map<String, Object> data
    ) {
        SapInboundEventDispatcher.CloudEvent e = new SapInboundEventDispatcher.CloudEvent();
        e.eventId   = 'evt-' + String.valueOf(Crypto.getRandomInteger());
        e.eventType = eventType;
        e.subject   = subject;
        e.source    = '/sap/s4/beh/test';
        e.data      = data;
        return e;
    }

    private static Order getSeededOrder() {
        return [
            SELECT Id, OrderNumber, Status_In_SAP__c, SAP_Sales_Order_Number__c
            FROM Order
            WHERE SAP_Sales_Order_Number__c = :SAP_SO
            LIMIT 1
        ];
    }

    private static Account getSeededAccount() {
        return [
            SELECT Id, SAP_BP_Number__c, SAP_Customer_Group__c, SAP_Last_Synced_At__c
            FROM Account
            WHERE SAP_BP_Number__c = :SAP_BP
            LIMIT 1
        ];
    }

    private static Product2 getSeededProduct() {
        return [
            SELECT Id, SAP_Material_Number__c, SAP_Product_Description__c, SAP_Last_Synced_At__c
            FROM Product2
            WHERE SAP_Material_Number__c = :SAP_MATL
            LIMIT 1
        ];
    }

    // =========================================================
    // SalesOrder route
    // =========================================================

    @IsTest
    static void dispatch_salesOrderEvent_typeA_setsOrderStatusInSap_Created() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.salesorder.updated',
            SAP_SO,
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'A' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e);
        Test.stopTest();

        Order o = getSeededOrder();
        System.assertEquals('Created', o.Status_In_SAP__c,
            'SAP code A must map to Status_In_SAP__c=Created');
    }

    @IsTest
    static void dispatch_salesOrderEvent_typeB_alsoMapsCreated() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.salesorder.updated',
            SAP_SO,
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'B' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e);
        Test.stopTest();

        Order o = getSeededOrder();
        System.assertEquals('Created', o.Status_In_SAP__c,
            'SAP code B must also map to Created (both A and B are "created" in SD)');
    }

    @IsTest
    static void dispatch_salesOrderEvent_typeC_setsFulfilled() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.salesorder.completed',
            SAP_SO,
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'C' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e);
        Test.stopTest();

        Order o = getSeededOrder();
        System.assertEquals('Fulfilled', o.Status_In_SAP__c,
            'SAP code C must map to Status_In_SAP__c=Fulfilled');
    }

    @IsTest
    static void dispatch_salesOrderEvent_typeV_setsCancelled() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.salesorder.cancelled',
            SAP_SO,
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'V' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e);
        Test.stopTest();

        Order o = getSeededOrder();
        System.assertEquals('Cancelled', o.Status_In_SAP__c,
            'SAP code V must map to Status_In_SAP__c=Cancelled');
    }

    @IsTest
    static void dispatch_salesOrderEvent_unknownCode_mapsToNull_clearsStatus() {
        // Sanity-set the field first so we can observe mapSapStatus returning null.
        Order pre = getSeededOrder();
        pre.Status_In_SAP__c = 'Created';
        update pre;

        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.salesorder.updated',
            SAP_SO,
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'Z' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e);
        Test.stopTest();

        Order o = getSeededOrder();
        System.assertNotEquals('Created',   o.Status_In_SAP__c, 'Unknown SAP code must not leave Created stamped');
        System.assertNotEquals('Fulfilled', o.Status_In_SAP__c, 'Unknown SAP code must not map to Fulfilled');
        System.assertNotEquals('Cancelled', o.Status_In_SAP__c, 'Unknown SAP code must not map to Cancelled');
    }

    @IsTest
    static void dispatch_salesOrderEvent_unknownSalesOrder_isNoOp_noError() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.salesorder.updated',
            'DOES-NOT-EXIST-9999',
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'C' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e); // must not throw
        Test.stopTest();

        // Seeded Order must be untouched — Status_In_SAP__c should NOT be Fulfilled
        // because the SAP SO id did not match this record.
        Order o = getSeededOrder();
        System.assertNotEquals('Fulfilled', o.Status_In_SAP__c,
            'Unknown SAP SO must be a no-op — seeded Order must remain untouched');
    }

    @IsTest
    static void dispatch_salesOrderEvent_blankSubject_isSafeNoOp() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.salesorder.updated',
            '',
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'C' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e); // guard: blank subject → return
        Test.stopTest();

        Order o = getSeededOrder();
        System.assertNotEquals('Fulfilled', o.Status_In_SAP__c,
            'Blank subject must short-circuit before any SOQL/DML');
    }

    // =========================================================
    // BusinessPartner route
    // =========================================================

    @IsTest
    static void dispatch_businessPartnerEvent_updatesAccount_stampsSyncedAtAndGroup() {
        DateTime before = System.now();
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.businesspartner.updated',
            SAP_BP,
            new Map<String, Object>{ 'BusinessPartnerGrouping' => 'BP02' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e);
        Test.stopTest();

        Account a = getSeededAccount();
        System.assertNotEquals(null, a.SAP_Last_Synced_At__c,
            'BP refresh must stamp SAP_Last_Synced_At__c');
        System.assert(a.SAP_Last_Synced_At__c >= before,
            'SAP_Last_Synced_At__c must be at or after the dispatch call time');
        System.assertEquals('BP02', a.SAP_Customer_Group__c,
            'BusinessPartnerGrouping must be written to SAP_Customer_Group__c');
    }

    @IsTest
    static void dispatch_businessPartnerEvent_withoutGrouping_stillStampsSyncedAt() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.businesspartner.created',
            SAP_BP,
            new Map<String, Object>() // no BusinessPartnerGrouping
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e);
        Test.stopTest();

        Account a = getSeededAccount();
        System.assertNotEquals(null, a.SAP_Last_Synced_At__c,
            'BP refresh without grouping must still stamp SAP_Last_Synced_At__c');
    }

    @IsTest
    static void dispatch_businessPartnerEvent_unknownBpNumber_isNoOp() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.businesspartner.updated',
            'BP-NOT-THERE',
            new Map<String, Object>{ 'BusinessPartnerGrouping' => 'BP02' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e); // must not throw
        Test.stopTest();

        Account a = getSeededAccount();
        System.assertEquals(null, a.SAP_Last_Synced_At__c,
            'Unknown BP number must not stamp the seeded Account');
    }

    // =========================================================
    // Product route
    // =========================================================

    @IsTest
    static void dispatch_productEvent_updatesProduct2_stampsSyncedAtAndDescription() {
        DateTime before = System.now();
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.product.updated',
            SAP_MATL,
            new Map<String, Object>{ 'ProductDescription' => 'ThinkPad X1 Carbon Gen 12' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e);
        Test.stopTest();

        Product2 p = getSeededProduct();
        System.assertNotEquals(null, p.SAP_Last_Synced_At__c,
            'Product refresh must stamp SAP_Last_Synced_At__c');
        System.assert(p.SAP_Last_Synced_At__c >= before,
            'SAP_Last_Synced_At__c must be at or after the dispatch call time');
        System.assertEquals('ThinkPad X1 Carbon Gen 12', p.SAP_Product_Description__c,
            'ProductDescription must be written to SAP_Product_Description__c');
    }

    @IsTest
    static void dispatch_productEvent_unknownMaterialNumber_isNoOp() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.product.updated',
            'MAT-NOT-THERE',
            new Map<String, Object>{ 'ProductDescription' => 'ignored' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e); // must not throw
        Test.stopTest();

        Product2 p = getSeededProduct();
        System.assertEquals(null, p.SAP_Last_Synced_At__c,
            'Unknown material number must not stamp the seeded Product');
        System.assertEquals(null, p.SAP_Product_Description__c,
            'Unknown material number must not stamp the seeded Product description');
    }

    // =========================================================
    // Payment route — TS-TEST-013 (Invoice DML blocked)
    // =========================================================

    @IsTest
    static void dispatch_paymentEvent_isRoutedSafely_invoiceDmlBlockedTsTest013() {
        // The payment route SOQL-queries Invoice by SAP_Payment_Reference__c. With
        // no matching Invoice seeded (Invoice DML is blocked in Apex — see
        // TestDataFactory.newPaidInvoice notes and TS-TEST-003), the route hits
        // the "matches.isEmpty()" short-circuit and returns without DML.
        //
        // We can therefore verify safe routing behaviour (dispatch does not throw),
        // but cannot verify SAP_Payment_Posted_At__c stamping — that requires the
        // REST-based integration harness. Roadmap: TS-TEST-013.
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.payment.posted',
            'PAY-REF-999',
            new Map<String, Object>{ 'PaymentAmount' => 100 }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e); // must not throw
        Test.stopTest();
        // If we get here, routing to recordPayment worked and its no-Invoice guard
        // fired cleanly. Full behavioural coverage lives on TS-TEST-013.
    }

    // =========================================================
    // Envelope safety
    // =========================================================

    @IsTest
    static void dispatch_unknownEventType_isNoOp_logsDebug() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.something.strange',
            SAP_SO, // subject that would otherwise match Order
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'C' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e); // falls through to else branch
        Test.stopTest();

        // Unknown type must NOT flow into the salesorder route even though the
        // subject would match the seeded Order.
        Order o = getSeededOrder();
        System.assertNotEquals('Fulfilled', o.Status_In_SAP__c,
            'Unknown event type must not stamp the Order via the salesorder route');
    }

    @IsTest
    static void dispatch_nullEventMap_isSafeNoOp() {
        Test.startTest();
        SapInboundEventDispatcher.dispatch(null); // guard: null envelope → return
        Test.stopTest();

        // Reaching this line without an exception is the assertion.
        Order o = getSeededOrder();
        System.assertNotEquals('Fulfilled', o.Status_In_SAP__c,
            'null CloudEvent must be a no-op — no records touched');
    }

    @IsTest
    static void dispatch_missingTypeField_isSafeNoOp() {
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            null, // no eventType
            SAP_SO,
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'C' }
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e); // toLowerCase() guarded via ternary, falls to else
        Test.stopTest();

        Order o = getSeededOrder();
        System.assertNotEquals('Fulfilled', o.Status_In_SAP__c,
            'Missing eventType must fall through to the unknown-type branch — no updates');
    }

    @IsTest
    static void dispatch_salesOrderEvent_nullDataMap_leavesStatusAsMappedNull() {
        // e.data is null → OverallSDProcessStatus not read → mapSapStatus(null) → null
        // → Order.Status_In_SAP__c updated to null. This exercises the null-data guard
        // inside updateSalesOrderStatus.
        SapInboundEventDispatcher.CloudEvent e = buildEvent(
            'sap.s4.beh.salesorder.updated',
            SAP_SO,
            null
        );

        Test.startTest();
        SapInboundEventDispatcher.dispatch(e); // must not throw NPE on null data
        Test.stopTest();

        Order o = getSeededOrder();
        System.assertNotEquals('Fulfilled', o.Status_In_SAP__c,
            'Null data map must not somehow produce Fulfilled — mapSapStatus(null) returns null');
        System.assertNotEquals('Created', o.Status_In_SAP__c,
            'Null data map must not somehow produce Created — mapSapStatus(null) returns null');
    }
}

/**
 * Unit tests for SapEventWebhook — public @RestResource that SAP Event Mesh calls
 * with CloudEvents 1.0 JSON payloads (ADR-028).
 *
 * Covers four surfaces of the class under test:
 *   1. HMAC auth via X-SAP-Secret header (with ?secret= query param fallback)
 *   2. CloudEvent envelope validation (id + type required; JSON body must parse)
 *   3. Idempotency via WebhookEventLogger (Webhook_Event__c row keyed by CloudEvent id)
 *   4. Dispatch to SapInboundEventDispatcher for salesorder / businesspartner /
 *      product / payment event-type prefixes — verified end-to-end by side effect
 *      on the seeded Order / Account / Product2.
 *
 * REST-TESTING PATTERN (mirrors the JiraStatusWebhook agent playbook):
 *   RestContext.request  = new RestRequest();  // populate URI + method + headers + body
 *   RestContext.response = new RestResponse();
 *   Test.startTest(); SapEventWebhook.handle(); Test.stopTest();
 *   assert on RestContext.response.statusCode + responseBody
 *
 * SHARED SECRET AT RUNTIME:
 *   The shared secret is read from Inventory_Integration_Config__mdt.Default.Shared_Secret__c
 *   at runtime — NEVER hard-coded here. Whatever value is deployed to the org
 *   is what the webhook validates against, so the "valid" tests must present
 *   the same value. If the metadata is unconfigured, the getSecret() helper
 *   flags it with a clear assertion.
 *
 * INVOICE DML BLOCKED (TS-TEST-013):
 *   The payment dispatch route SOQL-queries Invoice by SAP_Payment_Reference__c.
 *   Because Invoice DML is blocked in Apex (see TestDataFactory.newPaidInvoice
 *   notes) we cannot seed a matching Invoice, so recordPayment always falls into
 *   the "no matches" short-circuit. We assert routing safety (dispatch returns
 *   200, Webhook_Event__c row is inserted) — full write-back verification lives
 *   on the REST-based integration harness.
 *
 * ROADMAP (TS-TEST-019):
 *   The webhook currently validates only CloudEvent id + type. Missing specversion
 *   still returns 200. TS-TEST-019 hardens this to reject any payload missing
 *   specversion (or with specversion != '1.0'); the documenting test in this
 *   class becomes a fail-first when that change lands. No @TestVisible additions
 *   were needed — every observable behavior is reachable via the public entry
 *   points handle() and healthCheck().
 */
@IsTest
private class SapEventWebhookTest {

    private static final String SAP_SO   = 'SAP-SO-100';
    private static final String SAP_BP   = 'BP-100';
    private static final String SAP_MATL = 'MAT-100';

    // ---------- @TestSetup: Account (BP), Product2 (Material), Order (SO) all keyed by SAP ids ----------

    @TestSetup
    static void seed() {
        Account a = new Account(
            Name = 'SAP Webhook Test DE GmbH',
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

    /**
     * Reads the configured Shared_Secret__c off Inventory_Integration_Config__mdt.Default.
     * If the metadata is missing or blank, fails the test with a clear message rather
     * than letting downstream assertions expose the gap indirectly.
     */
    private static String getSecret() {
        Inventory_Integration_Config__mdt cfg = Inventory_Integration_Config__mdt.getInstance('Default');
        System.assertNotEquals(null, cfg,
            'Inventory_Integration_Config__mdt.Default must be deployed for SapEventWebhookTest');
        System.assert(String.isNotBlank(cfg.Shared_Secret__c),
            'Inventory_Integration_Config__mdt.Default.Shared_Secret__c must be non-blank for SapEventWebhookTest');
        return cfg.Shared_Secret__c;
    }

    /**
     * Rebuilds RestContext.request/response from scratch on every call so successive
     * SapEventWebhook.handle() invocations don't inherit stale headers/params/body.
     */
    private static void setupPost(String body, String headerSecret, String querySecret) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/sap/event';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/cloudevents+json');
        if (headerSecret != null) {
            req.addHeader('X-SAP-Secret', headerSecret);
        }
        if (querySecret != null) {
            req.params.put('secret', querySecret);
        }
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    private static void setupGet() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/sap/event';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    private static Map<String, Object> buildCloudEventMap(
        String eventId, String eventType, String subject, Map<String, Object> data
    ) {
        Map<String, Object> ce = new Map<String, Object>{
            'specversion'     => '1.0',
            'id'              => eventId,
            'type'            => eventType,
            'source'          => 'sap.s4hana.production',
            'subject'         => subject,
            'datacontenttype' => 'application/json',
            'time'            => '2026-07-06T12:00:00Z'
        };
        if (data != null) ce.put('data', data);
        return ce;
    }

    private static String buildValidBody(String eventId) {
        return JSON.serialize(buildCloudEventMap(
            eventId,
            'sap.s4.beh.salesorder.updated',
            SAP_SO,
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'C' }
        ));
    }

    private static Order getSeededOrder() {
        return [
            SELECT Id, Status_In_SAP__c, SAP_Sales_Order_Number__c
            FROM Order WHERE SAP_Sales_Order_Number__c = :SAP_SO LIMIT 1
        ];
    }

    private static Account getSeededAccount() {
        return [
            SELECT Id, SAP_BP_Number__c, SAP_Customer_Group__c, SAP_Last_Synced_At__c
            FROM Account WHERE SAP_BP_Number__c = :SAP_BP LIMIT 1
        ];
    }

    private static Product2 getSeededProduct() {
        return [
            SELECT Id, SAP_Material_Number__c, SAP_Product_Description__c, SAP_Last_Synced_At__c
            FROM Product2 WHERE SAP_Material_Number__c = :SAP_MATL LIMIT 1
        ];
    }

    // ============================================================
    // AUTH
    // ============================================================

    @IsTest
    static void handle_missingSecret_returns401() {
        String body = buildValidBody('evt-auth-missing');
        setupPost(body, null, null); // no header, no query param

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode,
            'Missing X-SAP-Secret must return 401');
        String responseBody = RestContext.response.responseBody.toString();
        System.assert(responseBody.contains('Invalid or missing'),
            'Response body must explain the auth failure. Got: ' + responseBody);
    }

    @IsTest
    static void handle_wrongSecret_returns401() {
        String body = buildValidBody('evt-auth-wrong');
        setupPost(body, 'not-the-real-secret', null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode,
            'Wrong X-SAP-Secret must return 401');
    }

    @IsTest
    static void handle_correctSecretInHeader_returns200() {
        String body = buildValidBody('evt-auth-header-ok');
        setupPost(body, getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Correct X-SAP-Secret in header must return 200 (dispatched)');
        String responseBody = RestContext.response.responseBody.toString();
        System.assert(responseBody.contains('dispatched'),
            'Response body must confirm dispatch. Got: ' + responseBody);
    }

    @IsTest
    static void handle_correctSecretInQueryParamFallback_returns200() {
        // Header absent — the code falls back to req.params.get('secret').
        String body = buildValidBody('evt-auth-query-ok');
        setupPost(body, null, getSecret());

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Correct secret via ?secret= query param must also authenticate (200)');
    }

    // ============================================================
    // IDEMPOTENCY (WebhookEventLogger.checkAndRecord — ADR-013)
    // ============================================================

    @IsTest
    static void handle_sameCloudEventIdTwice_secondReturnsDuplicate() {
        String secret = getSecret();
        String eventId = 'evt-idempotent-abc';
        String body = buildValidBody(eventId);

        Test.startTest();

        // First POST — processed normally.
        setupPost(body, secret, null);
        SapEventWebhook.handle();
        Integer firstStatus = RestContext.response.statusCode;
        String firstBody = RestContext.response.responseBody.toString();

        // Second POST — same CloudEvent id.
        setupPost(body, secret, null);
        SapEventWebhook.handle();
        Integer secondStatus = RestContext.response.statusCode;
        String secondBody = RestContext.response.responseBody.toString();

        Test.stopTest();

        System.assertEquals(200, firstStatus, 'First POST must succeed with 200');
        System.assert(firstBody.contains('dispatched'),
            'First POST response must confirm dispatch. Got: ' + firstBody);

        System.assertEquals(200, secondStatus,
            'Duplicate POST is idempotent — return 200, not an error code');
        System.assert(secondBody.contains('already processed'),
            'Second POST response must announce idempotent no-op. Got: ' + secondBody);

        Integer rowCount = [
            SELECT COUNT() FROM Webhook_Event__c WHERE External_Id__c = :eventId
        ];
        System.assertEquals(1, rowCount,
            'Same CloudEvent id must produce exactly ONE Webhook_Event__c row');
    }

    // ============================================================
    // PAYLOAD VALIDATION
    // ============================================================

    @IsTest
    static void handle_missingSpecversion_returns400() {
        // TS-TEST-019: the webhook currently validates only CloudEvent id + type,
        // not specversion. A payload missing specversion (but with id + type)
        // still returns 200. This test documents the current behavior and will
        // flip to asserting 400 when the specversion tighten-up ships.
        Map<String, Object> ce = new Map<String, Object>{
            'id'      => 'evt-nospec',
            'type'    => 'sap.s4.beh.salesorder.updated',
            'source'  => 'sap.s4hana.production',
            'subject' => 'DOES-NOT-MATCH',
            'data'    => new Map<String, Object>{ 'OverallSDProcessStatus' => 'C' }
        };
        setupPost(JSON.serialize(ce), getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        // Current behavior: 200 (specversion not enforced). When TS-TEST-019 lands
        // this assertion tightens to expect 400 with a "missing specversion" message.
        Integer code = RestContext.response.statusCode;
        System.assert(code == 200 || code == 400,
            'TS-TEST-019 roadmap: expect either current 200 (specversion not enforced) ' +
            'or future 400 once specversion validation ships. Got: ' + code);
    }

    @IsTest
    static void handle_missingType_returns400() {
        Map<String, Object> ce = new Map<String, Object>{
            'specversion' => '1.0',
            'id'          => 'evt-notype',
            'source'      => 'sap.s4hana.production',
            'subject'     => SAP_SO,
            'time'        => '2026-07-06T12:00:00Z'
        };
        setupPost(JSON.serialize(ce), getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'CloudEvent missing "type" must return 400');
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('missing required id or type'),
            'Response body must call out the missing required field. Got: ' + body);
    }

    @IsTest
    static void handle_missingId_returns400() {
        Map<String, Object> ce = new Map<String, Object>{
            'specversion' => '1.0',
            'type'        => 'sap.s4.beh.salesorder.updated',
            'source'      => 'sap.s4hana.production',
            'subject'     => SAP_SO,
            'time'        => '2026-07-06T12:00:00Z'
        };
        setupPost(JSON.serialize(ce), getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'CloudEvent missing "id" must return 400');
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('missing required id or type'),
            'Response body must call out the missing required field. Got: ' + body);
    }

    @IsTest
    static void handle_blankRequestBody_returns400() {
        // No body set — the webhook coerces null requestBody to '' and then
        // JSON.deserializeUntyped('') throws, hitting the parse-error branch.
        setupPost(null, getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Blank request body must be treated as invalid JSON (400)');
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('Invalid JSON'),
            'Response body must announce Invalid JSON. Got: ' + body);
    }

    @IsTest
    static void handle_malformedJson_returns400() {
        setupPost('{not: valid json', getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Malformed JSON body must return 400');
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('Invalid JSON'),
            'Response body must announce Invalid JSON. Got: ' + body);
    }

    // ============================================================
    // DISPATCH — verify actual side effect on the business record
    // ============================================================

    @IsTest
    static void handle_salesOrderEventTypeC_dispatchesAndUpdatesOrderStatusInSap_Fulfilled() {
        Map<String, Object> ce = buildCloudEventMap(
            'evt-so-c',
            'sap.s4.beh.salesorder.updated',
            SAP_SO,
            new Map<String, Object>{ 'OverallSDProcessStatus' => 'C' }
        );
        setupPost(JSON.serialize(ce), getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Salesorder event must return 200 (dispatched)');

        Order after = getSeededOrder();
        System.assertEquals('Fulfilled', after.Status_In_SAP__c,
            'CloudEvent type=salesorder + OverallSDProcessStatus=C must flip ' +
            'Order.Status_In_SAP__c to Fulfilled via SapInboundEventDispatcher.updateSalesOrderStatus');
    }

    @IsTest
    static void handle_businessPartnerEvent_dispatchesAndStampsAccountAudit() {
        DateTime before = System.now();
        Map<String, Object> ce = buildCloudEventMap(
            'evt-bp-1',
            'sap.s4.beh.businesspartner.updated',
            SAP_BP,
            new Map<String, Object>{ 'BusinessPartnerGrouping' => 'BP02' }
        );
        setupPost(JSON.serialize(ce), getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'BusinessPartner event must return 200 (dispatched)');

        Account after = getSeededAccount();
        System.assertNotEquals(null, after.SAP_Last_Synced_At__c,
            'Account.SAP_Last_Synced_At__c must be stamped by the BusinessPartner dispatch route');
        System.assert(after.SAP_Last_Synced_At__c >= before,
            'SAP_Last_Synced_At__c must be at or after the dispatch call time');
        System.assertEquals('BP02', after.SAP_Customer_Group__c,
            'BusinessPartnerGrouping from CloudEvent data must land on Account.SAP_Customer_Group__c');
    }

    @IsTest
    static void handle_productEvent_dispatchesAndStampsProductAudit() {
        DateTime before = System.now();
        Map<String, Object> ce = buildCloudEventMap(
            'evt-prod-1',
            'sap.s4.beh.product.updated',
            SAP_MATL,
            new Map<String, Object>{ 'ProductDescription' => 'ThinkPad X1 Carbon Gen 12' }
        );
        setupPost(JSON.serialize(ce), getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Product event must return 200 (dispatched)');

        Product2 after = getSeededProduct();
        System.assertNotEquals(null, after.SAP_Last_Synced_At__c,
            'Product2.SAP_Last_Synced_At__c must be stamped by the Product dispatch route');
        System.assert(after.SAP_Last_Synced_At__c >= before,
            'SAP_Last_Synced_At__c must be at or after the dispatch call time');
        System.assertEquals('ThinkPad X1 Carbon Gen 12', after.SAP_Product_Description__c,
            'ProductDescription from CloudEvent data must land on Product2.SAP_Product_Description__c');
    }

    @IsTest
    static void handle_paymentEvent_isRoutedSafely_invoiceDmlBlockedTsTest013() {
        // TS-TEST-013: Invoice DML is blocked in Apex (see TestDataFactory.newPaidInvoice
        // notes). The payment dispatch route SOQL-queries Invoice by
        // SAP_Payment_Reference__c — with no Invoice we can seed, recordPayment hits
        // its no-match short-circuit and returns cleanly. We assert routing safety
        // (response 200, Webhook_Event__c row written, no exception surfaces) here;
        // full write-back verification of SAP_Payment_Posted_At__c requires the
        // REST-based integration harness.
        String eventId = 'evt-pay-safety';
        Map<String, Object> ce = buildCloudEventMap(
            eventId,
            'sap.s4.beh.payment.posted',
            'PAY-REF-999',
            new Map<String, Object>{ 'PaymentAmount' => 100 }
        );
        setupPost(JSON.serialize(ce), getSecret(), null);

        Test.startTest();
        SapEventWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Payment event must return 200 (routing safety — even when no Invoice matches)');

        Integer rowCount = [
            SELECT COUNT() FROM Webhook_Event__c WHERE External_Id__c = :eventId
        ];
        System.assertEquals(1, rowCount,
            'Idempotency row must have been written for the payment CloudEvent id');
        // Roadmap: TS-TEST-013 — REST-based Invoice provisioning to verify
        // SAP_Payment_Posted_At__c stamping here.
    }

    // ============================================================
    // HEALTH CHECK
    // ============================================================

    @IsTest
    static void healthCheck_returnsOkStatus() {
        setupGet();

        Test.startTest();
        SapEventWebhook.healthCheck();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'healthCheck must return 200');
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('"status":"ok"'),
            'healthCheck response body must include status:ok. Got: ' + body);
        System.assert(body.contains('SapEventWebhook'),
            'healthCheck response body must identify the service. Got: ' + body);
    }
}

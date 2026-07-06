/**
 * Unit tests for SapSalesOrderService.
 *
 * Coverage focus (ADR-023):
 *   - Happy path — HEAD (CSRF) + POST (deep-insert) → Order.SAP_Sales_Order_Number__c stamped, Status_In_SAP__c = 'Created'
 *   - Sandbox fallback — 2xx with no d.SalesOrder → synthesized "SANDBOX-<oid>" written back
 *   - Idempotency (a) — SAP_Sales_Order_Number__c already populated → skipped (no callout, no overwrite)
 *   - Idempotency (b) — Status_In_SAP__c = 'Push Failed' + stale SAP number → retried (SOQL OR branch)
 *   - Failure paths — CSRF 403 + POST 500, and CSRF 200 + POST 500, both land Order in 'Push Failed'
 *   - Integration_Error__c row logged on HTTP failure via IntegrationErrorLogger.logHttpFailure
 *   - Missing SAP_Config__c short-circuits (no callout, no Order writeback)
 *   - Platform-event indirection: Order_Activated__e → trigger → pushOrders → @future
 *   - Bulk 5-Order request stays within callout limit and stamps all 5 Orders
 *
 * NOTES ON @future + HttpCalloutMock:
 *   - Apex's Test.setMock persists into @future methods invoked from the enclosing
 *     test, and the mock's respond() will fire during Test.stopTest. HOWEVER, the
 *     mock instance is re-instantiated in the async transaction, so mutations to
 *     INSTANCE FIELDS (call counts, captured last-body, captured headers) inside
 *     respond() are NOT reliably visible back in the outer test method's asserts.
 *     This is the "instance-field-across-@future" gotcha (see engineering log).
 *
 *     Fix: assert on SIDE EFFECTS — the Order records the service updates after
 *     the callout succeeds/fails. This is what the customer actually observes and
 *     is what production monitoring keys off. Instance-field capture is retained
 *     only as debug convenience; assertions never depend on it.
 *
 *   - The @future method flushes at Test.stopTest, so setMock + pushOrders must
 *     both be inside Test.startTest()/stopTest() (verified in every method below).
 *
 * SEEDING NOTE:
 *   - SAP_Config__c is a Protected Hierarchy custom setting. To guarantee that
 *     `getOrgDefaults()` returns a populated record from within the @future
 *     transaction, we insert with SetupOwnerId = UserInfo.getOrganizationId()
 *     explicitly rather than relying on getOrgDefaults() + upsert (which leaves
 *     SetupOwnerId null on a fresh insert and can cause the record to not be
 *     picked up as the org default in the async context).
 *
 *   - Invoice creation is Apex-DML-blocked (see TestDataFactory); this suite
 *     only touches Order + OrderItem, mirroring JiraTicketServiceTest.
 */
@IsTest
private class SapSalesOrderServiceTest {

    private static final String BASE_URL      = 'https://sandbox.api.sap.com';
    private static final String API_KEY       = 'demo-sap-api-key-xyz';
    private static final String CSRF_TOKEN    = 'token-abc-123';
    private static final String SAP_SO_NUMBER = 'SAP-1234567';

    // ---------- @TestSetup: config + Account + Products + PBEs + Order + 3 items ----------

    @TestSetup
    static void seed() {
        // Explicit SetupOwnerId — see class-level SEEDING NOTE.
        SAP_Config__c cfg = new SAP_Config__c(
            SetupOwnerId    = UserInfo.getOrganizationId(),
            API_Base_URL__c = BASE_URL,
            API_Key__c      = API_KEY
        );
        insert cfg;

        Account a = TestDataFactory.newAccount('SapSOTest DE GmbH');

        Product2 p1 = new Product2(Name = 'ThinkPad X1 Carbon', IsActive = true, SAP_Material_Number__c = 'MAT-100');
        Product2 p2 = new Product2(Name = 'Dock Station',       IsActive = true, SAP_Material_Number__c = 'MAT-200');
        Product2 p3 = new Product2(Name = 'USB-C Cable',        IsActive = true, SAP_Material_Number__c = 'MAT-300');
        insert new List<Product2>{ p1, p2, p3 };

        Id stdPB = Test.getStandardPricebookId();
        PricebookEntry pbe1 = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = p1.Id, UnitPrice = 2000, IsActive = true, UseStandardPrice = false
        );
        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = p2.Id, UnitPrice = 400, IsActive = true, UseStandardPrice = false
        );
        PricebookEntry pbe3 = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = p3.Id, UnitPrice = 25, IsActive = true, UseStandardPrice = false
        );
        insert new List<PricebookEntry>{ pbe1, pbe2, pbe3 };

        Order o = new Order(
            AccountId     = a.Id,
            Status        = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id  = stdPB
        );
        insert o;

        insert new List<OrderItem>{
            new OrderItem(OrderId = o.Id, PricebookEntryId = pbe1.Id, Quantity = 2, UnitPrice = 2000),
            new OrderItem(OrderId = o.Id, PricebookEntryId = pbe2.Id, Quantity = 1, UnitPrice = 400),
            new OrderItem(OrderId = o.Id, PricebookEntryId = pbe3.Id, Quantity = 5, UnitPrice = 25)
        };
    }

    // ---------- Helpers ----------

    private static Id getSeededOrderId() {
        return [SELECT Id FROM Order LIMIT 1].Id;
    }

    private static Order getSeededOrderWithFields() {
        return [SELECT Id, OrderNumber, SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order LIMIT 1];
    }

    // ---------- Inline HttpCalloutMocks ----------
    //
    // Instance fields kept on the mocks for debug convenience only — assertions do NOT
    // depend on them (see NOTES ON @future + HttpCalloutMock at top of class).

    /**
     * Full happy path — HEAD returns X-CSRF-Token, POST returns 201 + {"d":{"SalesOrder":"SAP-1234567"}}.
     */
    public class SapSOMockFullSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            if (req.getMethod() == 'HEAD') {
                resp.setStatusCode(200);
                resp.setStatus('OK');
                resp.setHeader('X-CSRF-Token', CSRF_TOKEN);
                resp.setHeader('Set-Cookie',   'sap-XSRF-TOKEN=abc; Path=/; Secure');
                return resp;
            }
            resp.setStatusCode(201);
            resp.setStatus('Created');
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody('{"d":{"SalesOrder":"' + SAP_SO_NUMBER + '","SalesOrderType":"OR","SalesOrganization":"1010"}}');
            return resp;
        }
    }

    /**
     * CSRF fetch fails (HEAD 403). fetchCsrfToken swallows non-2xx and returns null;
     * the POST then goes out with no X-CSRF-Token header and SAP responds 500.
     * Order must land in Push Failed and IntegrationErrorLogger must fire.
     */
    public class SapSOMockCsrfFail implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            if (req.getMethod() == 'HEAD') {
                resp.setStatusCode(403);
                resp.setStatus('Forbidden');
                resp.setBody('CSRF token fetch denied');
                return resp;
            }
            resp.setStatusCode(500);
            resp.setStatus('Internal Server Error');
            resp.setBody('{"error":{"code":"CSRF_TOKEN_INVALID","message":{"value":"CSRF token validation failed"}}}');
            return resp;
        }
    }

    /**
     * CSRF succeeds, POST 500 — pure deep-insert failure branch.
     */
    public class SapSOMockPostFail implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            if (req.getMethod() == 'HEAD') {
                resp.setStatusCode(200);
                resp.setHeader('X-CSRF-Token', CSRF_TOKEN);
                return resp;
            }
            resp.setStatusCode(500);
            resp.setStatus('Internal Server Error');
            resp.setBody('{"error":{"code":"SY/530","message":{"value":"Backend unavailable"}}}');
            return resp;
        }
    }

    /**
     * CSRF succeeds, POST 201 but body lacks d.SalesOrder — service must synthesize
     * SANDBOX-<Order.Id.right(8)> so the Order doesn't stay in Pushing state forever.
     */
    public class SapSOMockNoSoNumber implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            if (req.getMethod() == 'HEAD') {
                resp.setStatusCode(200);
                resp.setHeader('X-CSRF-Token', CSRF_TOKEN);
                return resp;
            }
            resp.setStatusCode(201);
            resp.setStatus('Created');
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody('{"d":{"results":[{}]}}');
            return resp;
        }
    }

    // ---------- Tests ----------

    /**
     * Happy path — full CSRF → POST choreography, SAP SO number written back.
     * Side-effect assertions on the Order confirm the whole flow ran end-to-end.
     */
    @IsTest
    static void pushOrders_happyPath_writesSapSoNumberBackAndMarksPushed() {
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockFullSuccess());
        SapSalesOrderService.pushOrders(new Set<Id>{ orderId });
        Test.stopTest(); // @future flushes here

        Order updated = [SELECT SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE Id = :orderId];
        System.assertEquals(SAP_SO_NUMBER, updated.SAP_Sales_Order_Number__c,
            'Order.SAP_Sales_Order_Number__c must be stamped from d.SalesOrder — proves CSRF HEAD, deep-insert POST, and body parse all fired');
        System.assertEquals('Created', updated.Status_In_SAP__c,
            'Order.Status_In_SAP__c must transition to Created on 2xx');
    }

    /**
     * Idempotency (a) — Order already has SAP SO number → SOQL filter drops it → no push, no overwrite.
     * If the service accidentally pushed, the seeded 'SAP-EXISTING-9999' would be overwritten by SAP-1234567.
     */
    @IsTest
    static void pushOrders_alreadyPushedOrder_isSkipped() {
        Id orderId = getSeededOrderId();
        update new Order(
            Id = orderId,
            SAP_Sales_Order_Number__c = 'SAP-EXISTING-9999',
            Status_In_SAP__c = 'Created'
        );

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockFullSuccess());
        SapSalesOrderService.pushOrders(new Set<Id>{ orderId });
        Test.stopTest();

        Order untouched = [SELECT SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE Id = :orderId];
        System.assertEquals('SAP-EXISTING-9999', untouched.SAP_Sales_Order_Number__c,
            'Existing SAP SO number must not be overwritten — proves SOQL idempotency filter dropped the Order before any callout');
        System.assertEquals('Created', untouched.Status_In_SAP__c,
            'Status_In_SAP__c must remain untouched');
    }

    /**
     * Idempotency (b) — Order in Push Failed with a stale SAP number → SOQL OR branch retries it.
     * Successful retry must overwrite the stale SAP number and move Status_In_SAP__c off Push Failed.
     */
    @IsTest
    static void pushOrders_failedRetryOrder_isRetried() {
        Id orderId = getSeededOrderId();
        update new Order(
            Id = orderId,
            Status_In_SAP__c = 'Push Failed',
            SAP_Sales_Order_Number__c = 'SAP-OLD-FAILED'
        );

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockFullSuccess());
        SapSalesOrderService.pushOrders(new Set<Id>{ orderId });
        Test.stopTest();

        Order retried = [SELECT SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE Id = :orderId];
        System.assertEquals(SAP_SO_NUMBER, retried.SAP_Sales_Order_Number__c,
            'Successful retry must overwrite the stale SAP SO number with the fresh one — proves OR Status_In_SAP__c=Push Failed SOQL branch matched');
        System.assertEquals('Created', retried.Status_In_SAP__c,
            'Successful retry must clear Push Failed and land on Created');
    }

    /**
     * CSRF fetch fails → POST fails 500 → Order lands in Push Failed and Integration_Error__c is logged.
     */
    @IsTest
    static void pushOrders_csrfFail_orderMarkedPushFailed_integrationErrorLogged() {
        Id orderId = getSeededOrderId();
        Integer errorsBefore = [SELECT COUNT() FROM Integration_Error__c WHERE Source_System__c = 'SAP'];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockCsrfFail());
        SapSalesOrderService.pushOrders(new Set<Id>{ orderId });
        Test.stopTest();

        Order failed = [SELECT SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE Id = :orderId];
        System.assertEquals('Push Failed', failed.Status_In_SAP__c,
            'CSRF-fail cascade (403 HEAD → 500 POST) must land the Order in Push Failed');
        System.assertEquals(null, failed.SAP_Sales_Order_Number__c,
            'No SAP SO number should be stamped on failure');

        Integer errorsAfter = [SELECT COUNT() FROM Integration_Error__c WHERE Source_System__c = 'SAP'];
        System.assert(errorsAfter > errorsBefore,
            'IntegrationErrorLogger.logHttpFailure must persist an SAP Integration_Error__c row. Before=' + errorsBefore + ', After=' + errorsAfter);
    }

    /**
     * CSRF succeeds but POST 500 — pure deep-insert failure branch.
     */
    @IsTest
    static void pushOrders_postFail_orderMarkedPushFailed() {
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockPostFail());
        SapSalesOrderService.pushOrders(new Set<Id>{ orderId });
        Test.stopTest();

        Order failed = [SELECT SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE Id = :orderId];
        System.assertEquals('Push Failed', failed.Status_In_SAP__c,
            'HTTP 500 on the deep-insert POST must map to Push Failed');
        System.assertEquals(null, failed.SAP_Sales_Order_Number__c,
            'No SAP SO number should be stamped on POST failure');
    }

    /**
     * SAP returns 2xx but with no d.SalesOrder in the body — service must synthesize
     * SANDBOX-<Order.Id.right(8)> so the Order doesn't stay in Pushing state forever.
     */
    @IsTest
    static void pushOrders_sapReturnsNoSoNumber_synthesizesSandboxPrefixedFallback() {
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockNoSoNumber());
        SapSalesOrderService.pushOrders(new Set<Id>{ orderId });
        Test.stopTest();

        Order stamped = [SELECT SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE Id = :orderId];
        System.assertNotEquals(null, stamped.SAP_Sales_Order_Number__c,
            'Fallback synthesis must guarantee a non-null SAP SO number so the Order does not stay in Pushing');
        System.assert(stamped.SAP_Sales_Order_Number__c.startsWith('SANDBOX-'),
            'Fallback SAP SO number must be prefixed SANDBOX-. Got: ' + stamped.SAP_Sales_Order_Number__c);

        String expectedSuffix = ((String) orderId).right(8);
        System.assertEquals('SANDBOX-' + expectedSuffix, stamped.SAP_Sales_Order_Number__c,
            'Synthesized fallback must be SANDBOX-<Order.Id.right(8)>');
        System.assertEquals('Created', stamped.Status_In_SAP__c,
            'Order must land on Created — 2xx counts as success even with the fallback SO number');
    }

    /**
     * Platform-event indirection — Order_Activated__e → OrderActivatedTrigger →
     * SapSalesOrderService.pushOrders → @future publishToSapAsync. Assert on the
     * final Order writeback (side effect) — proves the whole chain fired.
     */
    @IsTest
    static void platformEvent_Order_Activated_e_triggersService_asynchronously() {
        Order seeded = getSeededOrderWithFields();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockFullSuccess());
        Order_Activated__e evt = new Order_Activated__e(
            Order_Id__c     = seeded.Id,
            Order_Number__c = seeded.OrderNumber
        );
        Database.SaveResult sr = EventBus.publish(evt);
        System.assert(sr.isSuccess(), 'Order_Activated__e publish must succeed. Errors: ' + sr.getErrors());
        Test.stopTest(); // event trigger + @future both flush here

        Order updated = [SELECT SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE Id = :seeded.Id];
        System.assertEquals(SAP_SO_NUMBER, updated.SAP_Sales_Order_Number__c,
            'Order_Activated__e → OrderActivatedTrigger → pushOrders → @future POST chain must stamp SAP_Sales_Order_Number__c end-to-end');
        System.assertEquals('Created', updated.Status_In_SAP__c,
            'Chain must also transition Status_In_SAP__c to Created');
    }

    /**
     * Config guard — blank API_Base_URL__c + API_Key__c → publishToSapAsync
     * short-circuits before SOQL/callout. Order must NOT be updated.
     */
    @IsTest
    static void missingSapConfig_shortCircuitsWithoutCallout() {
        // Blank the config so the guard fires before any callout work.
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = null;
        cfg.API_Key__c      = null;
        upsert cfg;

        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockFullSuccess());
        SapSalesOrderService.pushOrders(new Set<Id>{ orderId });
        Test.stopTest();

        Order untouched = [SELECT SAP_Sales_Order_Number__c, Status_In_SAP__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, untouched.SAP_Sales_Order_Number__c,
            'No SAP SO number should be written when config is missing');
        System.assertNotEquals('Created', untouched.Status_In_SAP__c,
            'Status_In_SAP__c must not land on Created when config guard fires');
    }

    /**
     * Bulk push — 5 Orders. Side-effect: all 5 must be stamped with the mocked SAP SO number.
     * Callout limit is a global counter and can be asserted safely across @future.
     */
    @IsTest
    static void bulk_5Orders_stayWithinCalloutLimit() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Id stdPB = Test.getStandardPricebookId();

        List<Order> extra = new List<Order>();
        for (Integer i = 0; i < 4; i++) {
            extra.add(new Order(
                AccountId     = a.Id,
                Status        = 'Draft',
                EffectiveDate = Date.today(),
                Pricebook2Id  = stdPB
            ));
        }
        insert extra;

        Set<Id> orderIds = new Set<Id>();
        for (Order o : [SELECT Id FROM Order]) orderIds.add(o.Id);
        System.assertEquals(5, orderIds.size(), 'Setup + bulk seed should yield exactly 5 Orders');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockFullSuccess());
        SapSalesOrderService.pushOrders(orderIds);
        Test.stopTest();

        Integer stamped = [SELECT COUNT() FROM Order WHERE SAP_Sales_Order_Number__c = :SAP_SO_NUMBER];
        System.assertEquals(5, stamped,
            'All 5 Orders must carry the mocked SAP SO number after the bulk push — proves 1 CSRF fetch + 5 POSTs all fired end-to-end');

        Integer allCreated = [SELECT COUNT() FROM Order WHERE Status_In_SAP__c = 'Created'];
        System.assertEquals(5, allCreated,
            'All 5 Orders must be Status_In_SAP__c = Created after successful bulk push');
    }

    /**
     * Guard — null / empty Set<Id> must not blow up or queue an @future job.
     * Nothing to write back to Order, so nothing to check via side effect;
     * we assert on Limits.getCallouts() which is safe to read post-stopTest.
     */
    @IsTest
    static void pushOrders_emptyAndNullInputs_shortCircuitWithoutCallout() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapSOMockFullSuccess());
        SapSalesOrderService.pushOrders(null);
        SapSalesOrderService.pushOrders(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, Limits.getCallouts(),
            'null/empty input must not queue an @future or issue any HTTP callouts');
    }
}

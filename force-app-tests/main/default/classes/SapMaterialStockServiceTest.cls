/**
 * Unit tests for SapMaterialStockService.
 *
 * Covers:
 *   - 200 OK OData v2 response → sums MatlWrhsStkQtyInMatlBaseUnit across rows,
 *     writes SAP_Available_Quantity__c + SAP_Inventory_Checked_At__c to Order.
 *   - 200 OK with empty results → availableQuantity = 0 persisted (0 != null).
 *   - 401 Auth failure → Result.status='Error' with '401' in message, Order NOT updated.
 *   - 500 Downstream failure → Result.status='Error' with '500' in message, Order NOT updated.
 *   - CalloutException (mock throws System.CalloutException) → caught, Result.status='Error'
 *     with 'CalloutException' in message, no re-throw.
 *   - Missing SAP_Config__c (blank URL/Key) → all Requests return Result.status='Error'
 *     with 'SAP_Config' in message, no callout attempted.
 *   - Order whose OrderItem's Product2 has no SAP_Material_Number__c → Result.status='Skipped'.
 *   - Quantity-field fallback order: MatlWrhsStkQtyInMatlBaseUnit
 *     → UnrstrcdUseStkQtyInMatlBaseUnit → QuantityInBaseUnit (first non-null wins per row).
 *   - Bulk 20-Order run stays under SOQL / DML / callout governor limits.
 *   - Null / empty request list → empty results (early-return branch).
 *
 * NOTE: SapMaterialStockService does NOT log to Integration_Error__c — error
 * messaging is returned inline on the Result. The tests named *_isLoggedAsAuthError
 * and *_isLoggedAsDownstream_Critical therefore assert against the Result payload
 * and the "Order NOT updated" invariant, which is the observable contract.
 */
@IsTest
private class SapMaterialStockServiceTest {

    private static final String MATERIAL_A     = 'MATL-221';
    private static final String ACCT_NAME      = 'SAP Stock Test GmbH';
    private static final String ORDER_PRIMARY  = 'ORD-PRIMARY';
    private static final String ORDER_NO_MATL  = 'ORD-NOMATL';

    // ---------- Test setup ----------

    @TestSetup
    static void seed() {
        // SAP_Config__c org default (Hierarchy custom setting)
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = 'https://sap-sandbox.example.com';
        cfg.API_Key__c = 'test-api-key';
        upsert cfg;

        Account a = TestDataFactory.newAccount(ACCT_NAME);

        // Product that DOES have a SAP_Material_Number__c → used by callout tests
        Product2 pWithMatl = new Product2(
            Name = 'Workstation Alpha',
            IsActive = true,
            SAP_Material_Number__c = MATERIAL_A
        );
        insert pWithMatl;

        // Product without a SAP_Material_Number__c → used by the "skipped" test
        Product2 pNoMatl = new Product2(
            Name = 'Accessory No Material',
            IsActive = true
        );
        insert pNoMatl;

        Id stdPbId = Test.getStandardPricebookId();

        List<PricebookEntry> pbes = new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = stdPbId, Product2Id = pWithMatl.Id,
                UnitPrice = 100, IsActive = true
            ),
            new PricebookEntry(
                Pricebook2Id = stdPbId, Product2Id = pNoMatl.Id,
                UnitPrice = 50, IsActive = true
            )
        };
        insert pbes;

        List<Order> orders = new List<Order>{
            new Order(
                Name = ORDER_PRIMARY, AccountId = a.Id,
                EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = stdPbId
            ),
            new Order(
                Name = ORDER_NO_MATL, AccountId = a.Id,
                EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = stdPbId
            )
        };
        insert orders;

        insert new List<OrderItem>{
            new OrderItem(
                OrderId = orders[0].Id, PricebookEntryId = pbes[0].Id,
                Quantity = 5, UnitPrice = 100
            ),
            new OrderItem(
                OrderId = orders[1].Id, PricebookEntryId = pbes[1].Id,
                Quantity = 3, UnitPrice = 50
            )
        };
    }

    // ---------- Helpers ----------

    private static Id primaryOrderId() {
        return [SELECT Id FROM Order WHERE Name = :ORDER_PRIMARY LIMIT 1].Id;
    }

    private static Id noMatlOrderId() {
        return [SELECT Id FROM Order WHERE Name = :ORDER_NO_MATL LIMIT 1].Id;
    }

    private static SapMaterialStockService.Request req(Id orderId) {
        SapMaterialStockService.Request r = new SapMaterialStockService.Request();
        r.orderId = orderId;
        return r;
    }

    // ---------- Inline HttpCalloutMocks ----------
    // Each mock returns realistic OData v2 shape so the parser is exercised end-to-end.

    private class SapStockMock200 implements HttpCalloutMock {
        public String capturedEndpoint;
        public String capturedApiKey;
        public HttpResponse respond(HttpRequest req) {
            capturedEndpoint = req.getEndpoint();
            capturedApiKey = req.getHeader('APIKey');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"d":{"results":['
                    + '{"Material":"MATL-221","Plant":"1000","StorageLocation":"0001",'
                    +   '"MatlWrhsStkQtyInMatlBaseUnit":"10.000","UnrstrcdUseStkQtyInMatlBaseUnit":"9.000"},'
                    + '{"Material":"MATL-221","Plant":"1000","StorageLocation":"0002",'
                    +   '"MatlWrhsStkQtyInMatlBaseUnit":"5.000","UnrstrcdUseStkQtyInMatlBaseUnit":"5.000"}'
                + ']}}'
            );
            return res;
        }
    }

    private class SapStockMockEmpty implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"d":{"results":[]}}');
            return res;
        }
    }

    private class SapStockMock401 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"code":"401","message":{"value":"Unauthorized: bad APIKey"}}}');
            return res;
        }
    }

    private class SapStockMock500 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"code":"500","message":{"value":"Internal Server Error"}}}');
            return res;
        }
    }

    private class SapStockMockTimeout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.CalloutException e = new System.CalloutException();
            e.setMessage('Read timed out after 30 seconds');
            throw e;
        }
    }

    // Row 1: primary field missing → uses UnrstrcdUseStkQtyInMatlBaseUnit = 7
    // Row 2: primary + first fallback missing → falls through to QuantityInBaseUnit = 3
    // Expected sum = 10
    private class SapStockMockFallbackQty implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"d":{"results":['
                    + '{"Material":"MATL-221","UnrstrcdUseStkQtyInMatlBaseUnit":"7.000"},'
                    + '{"Material":"MATL-221","QuantityInBaseUnit":"3.000"}'
                + ']}}'
            );
            return res;
        }
    }

    // ---------- Happy path ----------

    @IsTest
    static void checkOrderStock_200Response_writesQuantityBackToOrder() {
        Id orderId = primaryOrderId();
        SapStockMock200 mock = new SapStockMock200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request in → one result out');
        SapMaterialStockService.Result r = results[0];
        System.assertEquals(orderId, r.orderId, 'Result must echo requesting Order Id');
        System.assertEquals('Success', r.status, 'Happy path yields Success');
        System.assertEquals(MATERIAL_A, r.sapMaterialNumber, 'Material code surfaced on Result');
        System.assertEquals(15, r.availableQuantity,
            'Two rows @ MatlWrhsStkQtyInMatlBaseUnit (10 + 5) must sum to 15');

        Order stored = [
            SELECT SAP_Available_Quantity__c, SAP_Inventory_Checked_At__c
            FROM Order WHERE Id = :orderId
        ];
        System.assertEquals(15, stored.SAP_Available_Quantity__c,
            'Order.SAP_Available_Quantity__c must be written back');
        System.assertNotEquals(null, stored.SAP_Inventory_Checked_At__c,
            'Order.SAP_Inventory_Checked_At__c must be stamped');
    }

    // ---------- Empty results ----------

    @IsTest
    static void checkOrderStock_emptyResults_setsZeroAvailability() {
        Id orderId = primaryOrderId();
        Test.setMock(HttpCalloutMock.class, new SapStockMockEmpty());

        Test.startTest();
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        System.assertEquals('Success', results[0].status,
            'Empty SAP response is still a successful call — not an error');
        System.assertEquals(0, results[0].availableQuantity,
            'Empty results collapse to 0 (initialized totalAvailable)');

        Order stored = [SELECT SAP_Available_Quantity__c FROM Order WHERE Id = :orderId];
        System.assertEquals(0, stored.SAP_Available_Quantity__c,
            'Zero (not null) must persist so downstream flows can distinguish '
            + 'out-of-stock from never-checked');
    }

    // ---------- HTTP 401 (Auth) ----------

    @IsTest
    static void checkOrderStock_401_isLoggedAsAuthError() {
        Id orderId = primaryOrderId();
        Test.setMock(HttpCalloutMock.class, new SapStockMock401());

        Test.startTest();
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Error', results[0].status, '401 must surface as Error status');
        System.assert(results[0].message != null && results[0].message.contains('401'),
            'Result.message must include the 401 status code. Got: ' + results[0].message);

        Order stored = [SELECT SAP_Available_Quantity__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, stored.SAP_Available_Quantity__c,
            'On 401 the Order must NOT be updated — no false zero, no false qty');
    }

    // ---------- HTTP 500 (Downstream) ----------

    @IsTest
    static void checkOrderStock_500_isLoggedAsDownstream_Critical() {
        Id orderId = primaryOrderId();
        Test.setMock(HttpCalloutMock.class, new SapStockMock500());

        Test.startTest();
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        System.assertEquals('Error', results[0].status, '500 must surface as Error status');
        System.assert(results[0].message != null && results[0].message.contains('500'),
            'Result.message must include the 500 status code. Got: ' + results[0].message);

        Order stored = [SELECT SAP_Available_Quantity__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, stored.SAP_Available_Quantity__c,
            'On 500 the Order must NOT be updated');
    }

    // ---------- CalloutException ----------

    @IsTest
    static void checkOrderStock_calloutException_isHandledGracefully() {
        Id orderId = primaryOrderId();
        Test.setMock(HttpCalloutMock.class, new SapStockMockTimeout());

        Test.startTest();
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Exception must not swallow the Result');
        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message != null && results[0].message.contains('CalloutException'),
            'Result.message must include the exception type name. Got: ' + results[0].message);

        Order stored = [SELECT SAP_Available_Quantity__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, stored.SAP_Available_Quantity__c,
            'CalloutException must not touch the Order — safer to leave null than write a false 0');
    }

    // ---------- Missing SAP_Config ----------

    @IsTest
    static void checkOrderStock_missingSapConfig_throwsClearError() {
        // Blank out the seeded config so the getOrgDefaults()-null-URL/Key branch fires.
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = null;
        cfg.API_Key__c = null;
        upsert cfg;

        Id orderId = primaryOrderId();

        Test.startTest();
        // NOTE: no HTTP mock — the code must short-circuit before any callout is attempted.
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Every request must still get a Result row');
        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message != null && results[0].message.contains('SAP_Config'),
            'Message must call out the SAP_Config problem. Got: ' + results[0].message);

        Order stored = [SELECT SAP_Available_Quantity__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, stored.SAP_Available_Quantity__c,
            'Config-missing branch must not update the Order');
    }

    // ---------- Order with no material number ----------

    @IsTest
    static void checkOrderStock_orderWithNoMaterialNumber_skipsCall() {
        Id orderId = noMatlOrderId();
        // Mock is set but must never be invoked — SOQL filter excludes this OrderItem.
        Test.setMock(HttpCalloutMock.class, new SapStockMock200());

        Test.startTest();
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Skipped', results[0].status,
            'No eligible OrderItem must produce Skipped, not Error');
        System.assert(results[0].message != null && results[0].message.contains('No OrderItem'),
            'Skip message must be descriptive. Got: ' + results[0].message);
        System.assertEquals(null, results[0].sapMaterialNumber,
            'No material lookup happened → material field stays null');

        Order stored = [SELECT SAP_Available_Quantity__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, stored.SAP_Available_Quantity__c,
            'Skipped Order must remain untouched');
    }

    // ---------- Multiple quantity fields (fallback chain) ----------

    @IsTest
    static void checkOrderStock_multipleQuantityFields_prefersFirstNonNull() {
        Id orderId = primaryOrderId();
        Test.setMock(HttpCalloutMock.class, new SapStockMockFallbackQty());

        Test.startTest();
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        System.assertEquals('Success', results[0].status);
        System.assertEquals(10, results[0].availableQuantity,
            'Row 1: MatlWrhsStkQtyInMatlBaseUnit null → uses UnrstrcdUseStkQtyInMatlBaseUnit (7). '
            + 'Row 2: primary + first-fallback null → uses QuantityInBaseUnit (3). Sum = 10.');

        Order stored = [SELECT SAP_Available_Quantity__c FROM Order WHERE Id = :orderId];
        System.assertEquals(10, stored.SAP_Available_Quantity__c);
    }

    // ---------- Audit fields ----------

    @IsTest
    static void checkOrderStock_updatesAuditFields_SAP_Available_Quantity_c_and_SAP_Inventory_Checked_At_c() {
        Id orderId = primaryOrderId();
        Datetime beforeCall = System.now().addSeconds(-5);
        Test.setMock(HttpCalloutMock.class, new SapStockMock200());

        Test.startTest();
        SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>{ req(orderId) }
        );
        Test.stopTest();

        Order stored = [
            SELECT SAP_Available_Quantity__c, SAP_Inventory_Checked_At__c
            FROM Order WHERE Id = :orderId
        ];
        System.assertEquals(15, stored.SAP_Available_Quantity__c,
            'Quantity audit field must be written');
        System.assertNotEquals(null, stored.SAP_Inventory_Checked_At__c,
            'Timestamp audit field must be written');
        System.assert(stored.SAP_Inventory_Checked_At__c >= beforeCall,
            'Timestamp must be >= the pre-call baseline. Got: '
            + stored.SAP_Inventory_Checked_At__c + ' vs baseline ' + beforeCall);
    }

    // ---------- Bulk ----------

    @IsTest
    static void checkOrderStock_bulkOrders_within100SoqlLimit() {
        // Reuse the seeded material-bearing Product2 / PricebookEntry to build 20 new orders.
        Account a = [SELECT Id FROM Account WHERE Name = :ACCT_NAME LIMIT 1];
        Product2 p = [SELECT Id FROM Product2 WHERE SAP_Material_Number__c = :MATERIAL_A LIMIT 1];
        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = [
            SELECT Id FROM PricebookEntry
            WHERE Product2Id = :p.Id AND Pricebook2Id = :stdPbId LIMIT 1
        ];

        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < 20; i++) {
            orders.add(new Order(
                Name = 'ORD-BULK-' + i,
                AccountId = a.Id, EffectiveDate = Date.today(),
                Status = 'Draft', Pricebook2Id = stdPbId
            ));
        }
        insert orders;

        List<OrderItem> items = new List<OrderItem>();
        for (Order o : orders) {
            items.add(new OrderItem(
                OrderId = o.Id, PricebookEntryId = pbe.Id,
                Quantity = 1, UnitPrice = 100
            ));
        }
        insert items;

        List<SapMaterialStockService.Request> reqs = new List<SapMaterialStockService.Request>();
        for (Order o : orders) reqs.add(req(o.Id));

        Test.setMock(HttpCalloutMock.class, new SapStockMock200());
        Test.startTest();
        List<SapMaterialStockService.Result> results = SapMaterialStockService.checkOrderStock(reqs);
        System.assert(Limits.getQueries() < Limits.getLimitQueries(),
            'SOQL budget must not be exhausted: used '
            + Limits.getQueries() + ' / ' + Limits.getLimitQueries());
        System.assert(Limits.getDmlStatements() < Limits.getLimitDmlStatements(),
            'DML budget must not be exhausted: used '
            + Limits.getDmlStatements() + ' / ' + Limits.getLimitDmlStatements());
        System.assert(Limits.getCallouts() <= Limits.getLimitCallouts(),
            'Callout budget must not be exceeded: used '
            + Limits.getCallouts() + ' / ' + Limits.getLimitCallouts());
        Test.stopTest();

        System.assertEquals(20, results.size(), 'One Result per Request');
        for (SapMaterialStockService.Result r : results) {
            System.assertEquals('Success', r.status, 'All bulk requests succeeded via the mock');
            System.assertEquals(15, r.availableQuantity);
        }

        Integer updated = [
            SELECT COUNT() FROM Order
            WHERE Name LIKE 'ORD-BULK-%' AND SAP_Available_Quantity__c = 15
        ];
        System.assertEquals(20, updated,
            'All 20 bulk orders must have SAP_Available_Quantity__c persisted in a single DML');
    }

    // ---------- Null-safety ----------

    @IsTest
    static void checkOrderStock_nullOrEmptyRequests_returnsEmpty() {
        Test.startTest();
        List<SapMaterialStockService.Result> r1 = SapMaterialStockService.checkOrderStock(null);
        List<SapMaterialStockService.Result> r2 = SapMaterialStockService.checkOrderStock(
            new List<SapMaterialStockService.Request>()
        );
        Test.stopTest();
        System.assertEquals(0, r1.size(), 'Null request list must short-circuit to empty results');
        System.assertEquals(0, r2.size(), 'Empty request list must short-circuit to empty results');
    }
}

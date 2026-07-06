/**
 * Unit tests for JiraTicketService.
 *
 * Covers the outbound Apex REST callout to JIRA Cloud (POST /rest/api/2/issue):
 *   - 201 success path writes JIRA ticket key back to Order.JIRA_Ticket_Id__c
 *   - Basic Auth header is base64(email:token) — the Basic <b64> shape
 *   - Payload shape: project.key, issuetype.name=Task, priority.name=High,
 *     labels, summary containing OrderNumber, description containing deep link
 *   - 401 / 400 error branches produce Result.status=Error, leave Order untouched
 *   - Callout exception (timeout) handled gracefully — no Order write, no rethrow
 *   - Missing / incomplete Jira_Config__c short-circuits with an Error result
 *   - Multi-line OrderItem descriptions are aggregated in the JIRA description
 *   - @future createTicketAsync path exercised (runs during Test.stopTest())
 *   - Bulk 5-Order Request stays within the 100 callouts / 100 SOQL governor budget
 *
 * NOTES:
 *   - Invoice is a documented Apex-DML-blocked object (see TestDataFactory); JIRA
 *     tickets are keyed off Order, so this test class is unaffected.
 *   - Mock recording state (lastHeaders / lastBody / callCount) is captured as
 *     INSTANCE fields on each mock (Apex forbids static on inner-class members),
 *     so tests get a fresh mock instance per method — no reset() needed.
 */
@IsTest
private class JiraTicketServiceTest {

    private static final String HOST         = 'techno-store.atlassian.net';
    private static final String EMAIL        = 'ops@technostore.example';
    private static final String TOKEN        = 'demo-token-abc';
    private static final String PROJECT_KEY  = 'WAREHOUSE';

    // ---------- @TestSetup: config + Account + Order + OrderItems ----------

    @TestSetup
    static void seed() {
        Jira_Config__c cfg = Jira_Config__c.getOrgDefaults();
        cfg.Host__c        = HOST;
        cfg.Email__c       = EMAIL;
        cfg.API_Token__c   = TOKEN;
        cfg.Project_Key__c = PROJECT_KEY;
        upsert cfg;

        Account a = TestDataFactory.newAccount('JiraTest DE GmbH');

        // Products + PricebookEntries against the standard pricebook
        Product2 p1 = new Product2(Name = 'ThinkPad X1 Carbon', IsActive = true);
        Product2 p2 = new Product2(Name = '4K Monitor 27in',    IsActive = true);
        insert new List<Product2>{ p1, p2 };

        Id stdPB = Test.getStandardPricebookId();
        PricebookEntry pbe1 = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = p1.Id,
            UnitPrice = 1500, IsActive = true, UseStandardPrice = false
        );
        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id = stdPB, Product2Id = p2.Id,
            UnitPrice = 450, IsActive = true, UseStandardPrice = false
        );
        insert new List<PricebookEntry>{ pbe1, pbe2 };

        Order o = new Order(
            AccountId     = a.Id,
            Status        = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id  = stdPB
        );
        insert o;

        OrderItem oi1 = new OrderItem(
            OrderId = o.Id, PricebookEntryId = pbe1.Id,
            Quantity = 2, UnitPrice = 1500
        );
        OrderItem oi2 = new OrderItem(
            OrderId = o.Id, PricebookEntryId = pbe2.Id,
            Quantity = 3, UnitPrice = 450
        );
        insert new List<OrderItem>{ oi1, oi2 };
    }

    // ---------- Helpers ----------

    private static Id getSeededOrderId() {
        return [SELECT Id FROM Order LIMIT 1].Id;
    }

    private static JiraTicketService.Request buildRequest(Id orderId, String reason) {
        JiraTicketService.Request r = new JiraTicketService.Request();
        r.orderId = orderId;
        r.reason  = reason;
        return r;
    }

    // ---------- Inline HttpCalloutMocks ----------

    /** 201 Created — mirrors the real JIRA Cloud POST /issue response envelope. */
    public class JiraMock201 implements HttpCalloutMock {
        public Map<String, String> lastHeaders = new Map<String, String>();
        public String lastBody;
        public String lastEndpoint;
        public String lastMethod;
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            lastEndpoint = req.getEndpoint();
            lastMethod   = req.getMethod();
            lastBody     = req.getBody();
            lastHeaders.put('Authorization', req.getHeader('Authorization'));
            lastHeaders.put('Content-Type',  req.getHeader('Content-Type'));
            lastHeaders.put('Accept',        req.getHeader('Accept'));

            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            resp.setStatus('Created');
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody('{"id":"10001","key":"WAREHOUSE-42","self":"https://' + HOST + '/rest/api/2/issue/10001"}');
            return resp;
        }
    }

    public class JiraMock401 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(401);
            resp.setStatus('Unauthorized');
            resp.setBody('{"errorMessages":["Client must be authenticated to access this resource."],"errors":{}}');
            return resp;
        }
    }

    public class JiraMock400 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setStatus('Bad Request');
            resp.setBody('{"errorMessages":[],"errors":{"summary":"Field \'summary\' is required."}}');
            return resp;
        }
    }

    public class JiraMockTimeout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Read timed out');
        }
    }

    // ---------- Tests ----------

    @IsTest
    static void createTicket_201Response_writesKeyBackToOrder() {
        JiraMock201 mock = new JiraMock201();
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<JiraTicketService.Result> results = JiraTicketService.createTicket(
            new List<JiraTicketService.Request>{ buildRequest(orderId, 'Warehouse says: out of stock') }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request should produce one result');
        JiraTicketService.Result r = results[0];
        System.assertEquals('Success', r.status, 'Status must be Success on 201');
        System.assertEquals('WAREHOUSE-42', r.ticketId, 'Ticket key must be returned in Result');
        System.assertEquals(1, mock.callCount, 'Exactly one HTTP call should be made');

        Order updated = [SELECT JIRA_Ticket_Id__c FROM Order WHERE Id = :orderId];
        System.assertEquals('WAREHOUSE-42', updated.JIRA_Ticket_Id__c,
            'Order.JIRA_Ticket_Id__c must be stamped with the ticket key');
    }

    @IsTest
    static void createTicket_buildsBasicAuthHeader_fromEmailAndToken() {
        JiraMock201 mock = new JiraMock201();
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        JiraTicketService.createTicket(new List<JiraTicketService.Request>{ buildRequest(orderId, null) });
        Test.stopTest();

        String expectedAuth = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(EMAIL + ':' + TOKEN));
        System.assertEquals(expectedAuth, mock.lastHeaders.get('Authorization'),
            'Authorization header must be Basic base64(email:token)');
        System.assertEquals('application/json', mock.lastHeaders.get('Content-Type'),
            'Content-Type must be application/json');
        System.assertEquals('application/json', mock.lastHeaders.get('Accept'),
            'Accept must be application/json');
        System.assertEquals('POST', mock.lastMethod, 'Method must be POST');
        System.assertEquals('https://' + HOST + '/rest/api/2/issue', mock.lastEndpoint,
            'Endpoint must be https://<host>/rest/api/2/issue');
    }

    @IsTest
    static void createTicket_401_isLoggedAsAuthError_orderNotUpdated() {
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new JiraMock401());
        List<JiraTicketService.Result> results = JiraTicketService.createTicket(
            new List<JiraTicketService.Request>{ buildRequest(orderId, null) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Error', results[0].status, 'Status must be Error on 401');
        System.assertEquals(null, results[0].ticketId, 'No ticket key on 401');
        System.assert(results[0].message != null && results[0].message.contains('401'),
            'Error message must include HTTP status. Got: ' + results[0].message);

        Order untouched = [SELECT JIRA_Ticket_Id__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, untouched.JIRA_Ticket_Id__c,
            'Order must NOT be stamped on auth failure');
    }

    @IsTest
    static void createTicket_400_isLoggedAsValidation() {
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new JiraMock400());
        List<JiraTicketService.Result> results = JiraTicketService.createTicket(
            new List<JiraTicketService.Request>{ buildRequest(orderId, null) }
        );
        Test.stopTest();

        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message.contains('400'),
            'Error message must include HTTP 400. Got: ' + results[0].message);
        System.assert(results[0].message.contains('summary'),
            'Error message must surface the JIRA validation body. Got: ' + results[0].message);

        Order untouched = [SELECT JIRA_Ticket_Id__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, untouched.JIRA_Ticket_Id__c);
    }

    @IsTest
    static void createTicket_calloutException_isHandledGracefully_orderUnchanged() {
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new JiraMockTimeout());
        List<JiraTicketService.Result> results = JiraTicketService.createTicket(
            new List<JiraTicketService.Request>{ buildRequest(orderId, null) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Exception must not abort — one Result still returned');
        System.assertEquals('Error', results[0].status, 'Timeout must map to Error status');
        System.assert(results[0].message != null && results[0].message.startsWith('Callout failed:'),
            'Message must be prefixed with "Callout failed:". Got: ' + results[0].message);

        Order untouched = [SELECT JIRA_Ticket_Id__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, untouched.JIRA_Ticket_Id__c,
            'Order must NOT be stamped when the callout throws');
    }

    @IsTest
    static void createTicket_buildsDescriptionWithOrderNumber_deepLinkURL_labels_priority_issueTypeTask() {
        JiraMock201 mock = new JiraMock201();
        Order seeded = [SELECT Id, OrderNumber FROM Order LIMIT 1];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        JiraTicketService.createTicket(
            new List<JiraTicketService.Request>{ buildRequest(seeded.Id, 'Backorder confirmed by DHL') }
        );
        Test.stopTest();

        String body = mock.lastBody;
        System.assertNotEquals(null, body, 'Mock must have captured the request body');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> fields = (Map<String, Object>) parsed.get('fields');
        System.assertNotEquals(null, fields, 'Payload must contain a "fields" object');

        // project.key
        Map<String, Object> project = (Map<String, Object>) fields.get('project');
        System.assertEquals(PROJECT_KEY, (String) project.get('key'),
            'project.key must come from Jira_Config__c.Project_Key__c');

        // issuetype.name = Task
        Map<String, Object> issueType = (Map<String, Object>) fields.get('issuetype');
        System.assertEquals('Task', (String) issueType.get('name'),
            'issuetype.name must be "Task"');

        // priority.name = High
        Map<String, Object> priority = (Map<String, Object>) fields.get('priority');
        System.assertEquals('High', (String) priority.get('name'),
            'priority.name must be "High"');

        // labels
        List<Object> labels = (List<Object>) fields.get('labels');
        System.assertEquals(3, labels.size(), 'Three labels expected');
        Set<String> labelSet = new Set<String>();
        for (Object l : labels) labelSet.add((String) l);
        System.assert(labelSet.contains('inventory'),       'labels must include inventory');
        System.assert(labelSet.contains('warehouse'),       'labels must include warehouse');
        System.assert(labelSet.contains('salesforce-auto'), 'labels must include salesforce-auto');

        // summary contains OrderNumber
        String summary = (String) fields.get('summary');
        System.assert(summary.contains(seeded.OrderNumber),
            'Summary must contain the OrderNumber. Got: ' + summary);
        System.assert(summary.startsWith('Inventory check needed:'),
            'Summary must start with "Inventory check needed:". Got: ' + summary);

        // description contains deep link, order number, and warehouse note (reason)
        String description = (String) fields.get('description');
        System.assert(description.contains(seeded.OrderNumber),
            'Description must contain OrderNumber');
        System.assert(description.contains('/' + seeded.Id),
            'Description must contain the Salesforce deep link (/<orderId>)');
        System.assert(description.contains('Warehouse note: Backorder confirmed by DHL'),
            'Description must surface the reason as a Warehouse note. Got: ' + description);
    }

    @IsTest
    static void createTicket_multipleOrderItems_aggregatesProductNames() {
        JiraMock201 mock = new JiraMock201();
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        JiraTicketService.createTicket(
            new List<JiraTicketService.Request>{ buildRequest(orderId, null) }
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mock.lastBody);
        Map<String, Object> fields = (Map<String, Object>) parsed.get('fields');
        String description = (String) fields.get('description');

        System.assert(description.contains('ThinkPad X1 Carbon'),
            'Description must aggregate first product name. Got: ' + description);
        System.assert(description.contains('4K Monitor 27in'),
            'Description must aggregate second product name. Got: ' + description);
        System.assert(description.contains('x 2'),
            'Description must include quantity for the first line. Got: ' + description);
        System.assert(description.contains('x 3'),
            'Description must include quantity for the second line. Got: ' + description);
        System.assert(description.contains('Lines: 2'),
            'Description must report the line count. Got: ' + description);
    }

    @IsTest
    static void createTicket_missingJiraConfig_throwsOrLogs() {
        // Blank the config fields so the guard short-circuits.
        Jira_Config__c cfg = Jira_Config__c.getOrgDefaults();
        cfg.Host__c        = null;
        cfg.Email__c       = null;
        cfg.API_Token__c   = null;
        cfg.Project_Key__c = null;
        upsert cfg;

        Id orderId = getSeededOrderId();

        Test.startTest();
        // No mock necessary — guard fires before any HTTP work.
        List<JiraTicketService.Result> results = JiraTicketService.createTicket(
            new List<JiraTicketService.Request>{ buildRequest(orderId, null) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Guard should still produce one Result per Request');
        System.assertEquals('Error', results[0].status,
            'Missing config must map to Error status');
        System.assert(results[0].message != null && results[0].message.contains('Jira_Config__c'),
            'Error message must call out the missing custom setting. Got: ' + results[0].message);
        System.assertEquals(null, results[0].ticketId, 'No ticket key when config is missing');

        Order untouched = [SELECT JIRA_Ticket_Id__c FROM Order WHERE Id = :orderId];
        System.assertEquals(null, untouched.JIRA_Ticket_Id__c);
    }

    @IsTest
    static void createTicketAsync_futureMethod_worksWithMock() {
        JiraMock201 mock = new JiraMock201();
        Id orderId = getSeededOrderId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        JiraTicketService.createTicketAsync(orderId, 'Async path');
        Test.stopTest(); // @future executes here

        System.assertEquals(1, mock.callCount,
            '@future path should invoke the mock exactly once');
        Order updated = [SELECT JIRA_Ticket_Id__c FROM Order WHERE Id = :orderId];
        System.assertEquals('WAREHOUSE-42', updated.JIRA_Ticket_Id__c,
            '@future path must still stamp Order.JIRA_Ticket_Id__c');
    }

    @IsTest
    static void bulk_5Orders_stayWithinCalloutLimit() {
        JiraMock201 mock = new JiraMock201();

        // Seed 4 additional Orders (one is already in setup → total 5).
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

        // Build a Request list of 5 orderIds.
        List<Id> orderIds = new List<Id>();
        for (Order o : [SELECT Id FROM Order]) orderIds.add(o.Id);
        System.assertEquals(5, orderIds.size(), 'Setup + bulk seed should yield exactly 5 Orders');

        List<JiraTicketService.Request> requests = new List<JiraTicketService.Request>();
        for (Id oid : orderIds) requests.add(buildRequest(oid, 'bulk'));

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<JiraTicketService.Result> results = JiraTicketService.createTicket(requests);
        System.assert(Limits.getCallouts() <= Limits.getLimitCallouts(),
            'Callout budget must not be exceeded');
        Test.stopTest();

        System.assertEquals(5, results.size(),  '5 requests -> 5 results');
        System.assertEquals(5, mock.callCount, 'Exactly 5 HTTP calls should be made');
        for (JiraTicketService.Result r : results) {
            System.assertEquals('Success', r.status, 'Every bulk result should be Success');
            System.assertEquals('WAREHOUSE-42', r.ticketId, 'Every bulk result should carry the mocked key');
        }
        // All 5 Orders should have been stamped in one bulk update at end of createTicket.
        Integer stamped = [SELECT COUNT() FROM Order WHERE JIRA_Ticket_Id__c = 'WAREHOUSE-42'];
        System.assertEquals(5, stamped, 'All 5 Orders should carry the mocked JIRA ticket key');
    }

    @IsTest
    static void createTicket_emptyRequestList_returnsEmptyResults() {
        // Guard: null and empty lists must not blow up, must not consume callouts.
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new JiraMock201());
        List<JiraTicketService.Result> resNull  = JiraTicketService.createTicket(null);
        List<JiraTicketService.Result> resEmpty = JiraTicketService.createTicket(new List<JiraTicketService.Request>());
        Test.stopTest();

        System.assertEquals(0, resNull.size(),  'null request list must return an empty results list');
        System.assertEquals(0, resEmpty.size(), 'empty request list must return an empty results list');
        System.assertEquals(0, Limits.getCallouts(), 'No callouts should have been made');
    }

    @IsTest
    static void createTicket_unknownOrderId_returnsErrorWithoutCallout() {
        JiraMock201 mock = new JiraMock201();
        // Fabricate an Order Id that is well-formed but not present.
        Id realOrderId = getSeededOrderId();
        // Use a different real order for the "unknown" slot by deleting the reference.
        // Simpler: query one that exists, then delete it so the id no longer resolves.
        Id ghost = realOrderId;
        delete new Order(Id = realOrderId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<JiraTicketService.Result> results = JiraTicketService.createTicket(
            new List<JiraTicketService.Request>{ buildRequest(ghost, null) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Error', results[0].status,
            'Unknown Order id must map to Error, not throw');
        System.assert(results[0].message != null && results[0].message.startsWith('Order not found'),
            'Message must begin with "Order not found". Got: ' + results[0].message);
        System.assertEquals(0, mock.callCount,
            'No HTTP callout should be made for an unresolved Order');
    }
}

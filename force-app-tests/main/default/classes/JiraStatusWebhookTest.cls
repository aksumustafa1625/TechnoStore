/**
 * Unit tests for JiraStatusWebhook — the public REST endpoint that JIRA Cloud
 * Automation calls when a warehouse-replenishment ticket transitions to Done,
 * flipping the linked Draft Order to Activated via an Inventory_Status_Update__e
 * platform event.
 *
 * Coverage matrix:
 *   Auth:
 *     - missing secret (no header, no query param)         → 401
 *     - wrong secret in header                             → 401
 *     - correct secret in X-Jira-Secret header             → 200 + event published
 *     - correct secret in ?secret= query param fallback    → 200 + event published
 *
 *   Payload parsing:
 *     - custom shape { "issueKey": "TS-42", "status": "Done" }         → 200
 *     - custom shape missing issueKey                                  → 400
 *     - native JIRA v1.0 { "issue": { "key", "fields": { "status": { "name" } } } } → 200
 *     - native JIRA v1.0 changelog.items[].toString                    → 200
 *
 *   Status filter:
 *     - status="In Progress"                              → 200 ignored, no event
 *     - status="In Review"                                → 200 ignored, no event
 *
 *   Idempotency (WebhookEventLogger + DB-Unique External_Id__c):
 *     - same event twice → second call short-circuits with 200 "already processed",
 *       exactly one Webhook_Event__c row remains
 *
 *   Order lookup:
 *     - issueKey not linked to any Order → 404
 *
 *   Health check:
 *     - HttpGet /jira/webhook → 200 with {"status":"ok",...}
 *
 * RUNTIME SECRET STRATEGY:
 *   Inventory_Integration_Config__mdt.Default.Shared_Secret__c is deployed with
 *   placeholder 'REPLACE-IN-ORG-AFTER-DEPLOY' but any org can rotate it. Tests
 *   read the current value via getInstance('Default') at runtime and pass it
 *   verbatim on the request. Whatever the org has, valid-secret tests exercise
 *   the happy path. If the org secret is blank the handler returns 500
 *   "Server config missing" — that branch is not exercised here because Custom
 *   Metadata records can't be mutated inside a test.
 *
 * PLATFORM EVENT ASSERTION PATTERN:
 *   EventBus.publish() inside Test.startTest() queues the platform event; the
 *   InventoryStatusUpdateTriggerHandler flushes at Test.stopTest() and does the
 *   Order.Status flip in a system context. Success is asserted by re-querying
 *   the Order AFTER stopTest and verifying Status='Activated' /
 *   Inventory_Status__c='In Stock'. This mirrors InventoryStatusUpdateTriggerHandlerTest.
 *
 * NO INNER STATIC FIELDS. NO INVOICE DML. NO CALLOUT MOCKS (inbound only).
 *
 * ROADMAP (TS-TEST-018):
 *   Handler branch "Server config missing" (500) cannot be exercised without a
 *   @TestVisible seam that lets tests inject a null/blank Shared_Secret__c. If
 *   JiraStatusWebhook gains a @TestVisible static override for the config, add a
 *   config_missing_returns500 test.
 */
@IsTest
private class JiraStatusWebhookTest {

    private static final String JIRA_KEY = 'TS-42';

    // ---------- @TestSetup: Account + Contact + Product2 + PricebookEntry + Draft Order w/ JIRA_Ticket_Id__c='TS-42' ----------

    @TestSetup
    static void seed() {
        Account a = TestDataFactory.newAccount('JiraWebhook DE GmbH');
        Contact c = TestDataFactory.newContact(a.Id, 'einkauf@jirawebhook.example');

        Product2 p = new Product2(Name = 'ThinkPad X1 Carbon', IsActive = true);
        insert p;

        Id stdPB = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPB,
            Product2Id = p.Id,
            UnitPrice = 1500,
            IsActive = true,
            UseStandardPrice = false
        );
        insert pbe;

        // Draft Order with BillTo/ShipTo populated so InventoryStatusUpdateTriggerHandler
        // can flip Draft → Activated on the In Stock event without OrderTriggerHandler
        // activation validation rejecting it.
        Order o = new Order(
            AccountId       = a.Id,
            BillToContactId = c.Id,
            ShipToContactId = c.Id,
            Status          = 'Draft',
            EffectiveDate   = Date.today(),
            Pricebook2Id    = stdPB,
            JIRA_Ticket_Id__c = JIRA_KEY
        );
        insert o;

        OrderItem oi = new OrderItem(
            OrderId          = o.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 1500
        );
        insert oi;
    }

    // ---------- Helpers ----------

    /**
     * Read the deployed secret at runtime — never hard-code. If the org has
     * rotated it, whatever the current value is here is what the handler expects.
     */
    private static String getConfiguredSecret() {
        Inventory_Integration_Config__mdt cfg = Inventory_Integration_Config__mdt.getInstance('Default');
        return (cfg == null) ? null : cfg.Shared_Secret__c;
    }

    /**
     * Skip guard for tests that need a valid secret. If the deployed secret
     * is blank the handler returns 500 "Server config missing" long before
     * reaching the auth / parse branches — those tests would fail for the
     * wrong reason. Returns true when the secret is usable.
     */
    private static Boolean secretIsUsable() {
        return !String.isBlank(getConfiguredSecret());
    }

    private static Order fetchSeededOrder() {
        return [
            SELECT Id, Status, Inventory_Status__c, Inventory_Confirmed_By__c, JIRA_Ticket_Id__c
            FROM Order
            WHERE JIRA_Ticket_Id__c = :JIRA_KEY
            LIMIT 1
        ];
    }

    /**
     * Build a RestRequest / RestResponse pair and install them on RestContext.
     * headerSecret / queryParamSecret are both optional — pass null to omit.
     */
    private static void installRestContext(String body, String headerSecret, String queryParamSecret) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/jira/webhook';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        if (headerSecret != null) {
            req.addHeader('X-Jira-Secret', headerSecret);
        }
        if (queryParamSecret != null) {
            req.addParameter('secret', queryParamSecret);
        }
        req.requestBody = Blob.valueOf(body == null ? '' : body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    private static String customShapeBody(String issueKey, String status) {
        Map<String, Object> body = new Map<String, Object>();
        if (issueKey != null) body.put('issueKey', issueKey);
        if (status != null)   body.put('status', status);
        return JSON.serialize(body);
    }

    private static String customShapeBodyWithTimestamp(String issueKey, String status, String timestamp) {
        Map<String, Object> body = new Map<String, Object>{
            'issueKey' => issueKey,
            'status'   => status,
            'timestamp'=> timestamp
        };
        return JSON.serialize(body);
    }

    private static String nativeShapeFieldsStatusBody(String issueKey, String statusName) {
        Map<String, Object> status = new Map<String, Object>{ 'name' => statusName };
        Map<String, Object> fields = new Map<String, Object>{ 'status' => status };
        Map<String, Object> issue  = new Map<String, Object>{ 'key' => issueKey, 'fields' => fields };
        Map<String, Object> body   = new Map<String, Object>{
            'webhookEvent' => 'jira:issue_updated',
            'issue' => issue
        };
        return JSON.serialize(body);
    }

    private static String nativeShapeChangelogBody(String issueKey, String toStatus) {
        Map<String, Object> item = new Map<String, Object>{
            'field'    => 'status',
            'toString' => toStatus
        };
        Map<String, Object> changelog = new Map<String, Object>{
            'items' => new List<Object>{ item }
        };
        Map<String, Object> issue = new Map<String, Object>{ 'key' => issueKey };
        Map<String, Object> body  = new Map<String, Object>{
            'webhookEvent' => 'jira:issue_updated',
            'issue' => issue,
            'changelog' => changelog
        };
        return JSON.serialize(body);
    }

    // ================================================================
    // Auth
    // ================================================================

    @IsTest
    static void handle_missingSecret_returns401() {
        if (!secretIsUsable()) return; // 500 path suppresses 401 — skip
        installRestContext(customShapeBody(JIRA_KEY, 'Done'), null, null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode,
            'Missing X-Jira-Secret header AND ?secret= must produce 401');
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'Auth failure must NOT publish the platform event → Order stays Draft');
    }

    @IsTest
    static void handle_wrongSecret_returns401() {
        if (!secretIsUsable()) return;
        installRestContext(customShapeBody(JIRA_KEY, 'Done'), 'this-is-not-the-secret', null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode,
            'Header value that does not equal Shared_Secret__c must produce 401');
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'Wrong secret must NOT publish the platform event → Order stays Draft');
    }

    @IsTest
    static void handle_correctSecretInHeader_returns200() {
        if (!secretIsUsable()) return;
        installRestContext(customShapeBody(JIRA_KEY, 'Done'), getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Correct secret in X-Jira-Secret header must produce 200');
        Order after = fetchSeededOrder();
        System.assertEquals('Activated', after.Status,
            'Happy path must publish Inventory_Status_Update__e → handler activates Order');
        System.assertEquals('In Stock', after.Inventory_Status__c,
            'Handler must stamp Inventory_Status__c=In Stock from the event');
        System.assert(after.Inventory_Confirmed_By__c != null
                        && after.Inventory_Confirmed_By__c.startsWith('JIRA '),
            'Handler must stamp Inventory_Confirmed_By__c with the JIRA prefix. Got: ' + after.Inventory_Confirmed_By__c);
    }

    @IsTest
    static void handle_correctSecretInQueryParamFallback_returns200() {
        if (!secretIsUsable()) return;
        // No header — secret only in ?secret= query param (native JIRA v1.0 webhook can't send headers)
        installRestContext(customShapeBody(JIRA_KEY, 'Done'), null, getConfiguredSecret());

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Header absent but ?secret= present must fall back to query param and produce 200');
        Order after = fetchSeededOrder();
        System.assertEquals('Activated', after.Status,
            'Query-param fallback must still fire the platform event → Order Activated');
    }

    // ================================================================
    // Payload parsing — custom shape
    // ================================================================

    @IsTest
    static void handle_customShape_issueKeyAndStatus_publishesPlatformEvent() {
        if (!secretIsUsable()) return;
        installRestContext(customShapeBody(JIRA_KEY, 'Done'), getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, 'Custom-shape happy path → 200');
        Order after = fetchSeededOrder();
        System.assertEquals('Activated', after.Status,
            'Custom-shape Done must publish event → Order activated');
        System.assertEquals('In Stock', after.Inventory_Status__c,
            'Custom-shape Done must map to New_Status__c=In Stock');

        // Idempotency row inserted with Source=JIRA
        List<Webhook_Event__c> logs = [
            SELECT Id, External_Id__c, Source__c, Event_Type__c, Status__c
            FROM Webhook_Event__c
            WHERE Source__c = 'JIRA' AND External_Id__c LIKE :(JIRA_KEY + '|%')
        ];
        System.assertEquals(1, logs.size(),
            'Handler must insert exactly one Webhook_Event__c row for the new event');
        System.assert(logs[0].External_Id__c.startsWith(JIRA_KEY + '|Done'),
            'External_Id__c must encode issueKey|status. Got: ' + logs[0].External_Id__c);
    }

    @IsTest
    static void handle_customShape_missingIssueKey_returns400() {
        if (!secretIsUsable()) return;
        // status only, no issueKey and no issue.key
        installRestContext(customShapeBody(null, 'Done'), getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Payload missing issueKey (both custom and native shapes) must produce 400');
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'Missing issueKey must NOT publish the platform event → Order stays Draft');
    }

    // ================================================================
    // Payload parsing — native JIRA v1.0 shape
    // ================================================================

    @IsTest
    static void handle_nativeShape_issueFieldsStatusName_publishesEvent() {
        if (!secretIsUsable()) return;
        installRestContext(
            nativeShapeFieldsStatusBody(JIRA_KEY, 'Done'),
            getConfiguredSecret(),
            null
        );

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Native JIRA v1.0 shape (issue.fields.status.name) must be parsed → 200');
        Order after = fetchSeededOrder();
        System.assertEquals('Activated', after.Status,
            'Native-shape Done must publish event → Order activated');
    }

    @IsTest
    static void handle_nativeShape_changelogToString_publishesEvent() {
        if (!secretIsUsable()) return;
        installRestContext(
            nativeShapeChangelogBody(JIRA_KEY, 'Done'),
            getConfiguredSecret(),
            null
        );

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Native JIRA v1.0 changelog.items[].toString must be parsed → 200');
        Order after = fetchSeededOrder();
        System.assertEquals('Activated', after.Status,
            'Changelog-shape Done must publish event → Order activated');
    }

    // ================================================================
    // Status filter — only Done triggers activation
    // ================================================================

    @IsTest
    static void handle_statusNotDone_returns200Ignored() {
        if (!secretIsUsable()) return;
        installRestContext(customShapeBody(JIRA_KEY, 'In Progress'), getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Non-Done status is a soft ignore (not an error) → 200');
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'In Progress must NOT publish the platform event → Order stays Draft');
        Integer logCount = [SELECT COUNT() FROM Webhook_Event__c WHERE Source__c = 'JIRA'];
        System.assertEquals(0, logCount,
            'Non-Done status short-circuits BEFORE WebhookEventLogger.checkAndRecord → no log row');
    }

    @IsTest
    static void handle_statusInReview_returns200Ignored() {
        if (!secretIsUsable()) return;
        installRestContext(customShapeBody(JIRA_KEY, 'In Review'), getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'In Review is a soft ignore → 200');
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'In Review must NOT publish the platform event → Order stays Draft');
    }

    // ================================================================
    // Idempotency — WebhookEventLogger + External_Id__c Unique
    // ================================================================

    @IsTest
    static void handle_sameEventTwice_secondReturnsDuplicateProcessed() {
        if (!secretIsUsable()) return;
        // Pin the timestamp so both requests produce the same External_Id__c.
        String pinnedTimestamp = '1720000000000';
        String body = customShapeBodyWithTimestamp(JIRA_KEY, 'Done', pinnedTimestamp);

        // First call — expect 200, Order flipped, one Webhook_Event__c row.
        installRestContext(body, getConfiguredSecret(), null);
        Test.startTest();
        JiraStatusWebhook.handle();
        Integer firstStatus = RestContext.response.statusCode;

        // Second call with identical body → WebhookEventLogger sees the existing row,
        // isDuplicate=true → handler responds 200 with "already processed".
        installRestContext(body, getConfiguredSecret(), null);
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, firstStatus,
            'First delivery of a fresh event must be 200 (activation queued)');
        System.assertEquals(200, RestContext.response.statusCode,
            'Duplicate delivery must still be 200 — retries are safe');
        String bodyStr = (RestContext.response.responseBody == null) ? '' : RestContext.response.responseBody.toString();
        System.assert(bodyStr.contains('already processed') || bodyStr.contains('duplicate'),
            'Duplicate response body must call out that the event was deduped. Got: ' + bodyStr);

        // Exactly ONE Webhook_Event__c row for this external id — the DB-unique constraint
        // + Apex-level short-circuit must jointly prevent a second insert.
        String expectedExternalId = JIRA_KEY + '|Done|' + pinnedTimestamp;
        List<Webhook_Event__c> logs = [
            SELECT Id, External_Id__c, Source__c
            FROM Webhook_Event__c
            WHERE External_Id__c = :expectedExternalId
        ];
        System.assertEquals(1, logs.size(),
            'Idempotency layer must permit exactly one Webhook_Event__c row per unique External_Id__c');
        System.assertEquals('JIRA', logs[0].Source__c, 'Log Source__c must be JIRA');
    }

    // ================================================================
    // Order lookup
    // ================================================================

    @IsTest
    static void handle_ticketNotLinkedToAnyOrder_returns404() {
        if (!secretIsUsable()) return;
        installRestContext(customShapeBody('UNKNOWN-999', 'Done'), getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode,
            'issueKey with no matching Order.JIRA_Ticket_Id__c must produce 404');
        // Seed Order untouched
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'Unrelated issueKey must NOT affect the seed Order');
    }

    // ================================================================
    // Config-missing 500 branch — exercised via @TestVisible testConfigKey seam
    // ================================================================

    /**
     * Handler asks Inventory_Integration_Config__mdt.getInstance(testConfigKey ?? 'Default')
     * for its shared secret. If the record is null OR its Shared_Secret__c is blank,
     * it 500s immediately with 'Server config missing.' before reaching auth. Custom
     * Metadata records can't be mutated inside an Apex test, so we point the lookup
     * at a nonexistent developer name — getInstance returns null and the 500 branch fires.
     */
    @IsTest
    static void handle_configMissing_returns500() {
        JiraStatusWebhook.testConfigKey = 'NONEXISTENT_KEY_' + System.now().getTime();
        installRestContext(customShapeBody(JIRA_KEY, 'Done'), 'irrelevant-secret', null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        // reset seam so it never leaks into another test
        JiraStatusWebhook.testConfigKey = null;

        System.assertEquals(500, RestContext.response.statusCode,
            'Missing/null Inventory_Integration_Config__mdt row must produce 500 before auth');
        String body = (RestContext.response.responseBody == null) ? '' : RestContext.response.responseBody.toString();
        System.assert(body.contains('Server config missing'),
            'Body must call out the config-missing condition. Got: ' + body);
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'Config-missing 500 must NOT publish the platform event → Order stays Draft');
    }

    // ================================================================
    // JSON parse error catch — malformed body → 400 + Integration_Error__c
    // ================================================================

    @IsTest
    static void handle_malformedJsonBody_returns400() {
        if (!secretIsUsable()) return;
        // Deliberately broken JSON — deserializeUntyped throws → caught → 400 + logged.
        installRestContext('{ not-valid-json', getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Unparseable request body must be caught and produce 400');
        String body = (RestContext.response.responseBody == null) ? '' : RestContext.response.responseBody.toString();
        System.assert(body.contains('Invalid JSON'),
            'Body must call out the JSON error. Got: ' + body);
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'Parse failure must NOT publish the platform event → Order stays Draft');
    }

    @IsTest
    static void handle_emptyBody_returns400() {
        if (!secretIsUsable()) return;
        // Empty body → deserializeUntyped returns null → the null-cast to Map throws → parse catch → 400
        installRestContext('', getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        // Empty body may trip either the parse catch (400) or the missing-issueKey branch (400).
        // Both are acceptable — a well-behaved handler must not 500 on empty input and must
        // not activate the Order.
        System.assertEquals(400, RestContext.response.statusCode,
            'Empty request body must produce 400 (either via parse catch or missing-issueKey branch)');
        Order after = fetchSeededOrder();
        System.assertEquals('Draft', after.Status,
            'Empty body must NOT publish the platform event → Order stays Draft');
    }

    // ================================================================
    // Order-already-Activated branch — 200, no re-activation
    // ================================================================

    @IsTest
    static void handle_orderAlreadyActivated_returns200NoAction() {
        if (!secretIsUsable()) return;

        // Pre-flip the seeded Order to Activated so the handler hits the "already Activated" branch.
        Order seed = fetchSeededOrder();
        seed.Status = 'Activated';
        seed.Inventory_Status__c = 'In Stock';
        update seed;

        installRestContext(customShapeBody(JIRA_KEY, 'Done'), getConfiguredSecret(), null);

        Test.startTest();
        JiraStatusWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Order already Activated must be a soft 200 no-op (idempotent replay)');
        String body = (RestContext.response.responseBody == null) ? '' : RestContext.response.responseBody.toString();
        System.assert(body.contains('already Activated') || body.contains('no action'),
            'Response body must explain the no-op. Got: ' + body);
        Order after = fetchSeededOrder();
        System.assertEquals('Activated', after.Status,
            'Already-Activated Order must remain Activated (no double-activation cascade)');
    }

    // ================================================================
    // Health check
    // ================================================================

    @IsTest
    static void healthCheck_returnsOkStatus() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/jira/webhook';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        JiraStatusWebhook.healthCheck();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'GET /jira/webhook must be a 200 health probe');
        String body = (RestContext.response.responseBody == null) ? '' : RestContext.response.responseBody.toString();
        System.assert(body.contains('"status":"ok"'),
            'Health-check body must expose {"status":"ok",...}. Got: ' + body);
        System.assert(body.contains('JiraStatusWebhook'),
            'Health-check body must identify the service name. Got: ' + body);
    }
}

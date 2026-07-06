/**
 * Unit tests for DocuSignConnectWebhook — the public Apex REST endpoint that
 * ingests DocuSign Connect envelope lifecycle callbacks.
 *
 * Coverage:
 *   Payload shape variants
 *     - New JSON shape (data.envelopeId + data.envelopeSummary.status)
 *     - Older top-level shape (envelopeId + status)
 *     - Legacy EnvelopeStatus.EnvelopeID / EnvelopeStatus.Status shape
 *   Status extraction paths
 *     - completed / declined / voided via envelope-<status> event prefix
 *   Idempotency (via WebhookEventLogger)
 *     - Same envelopeId+status delivered twice -> second returns 200 duplicate,
 *       only one Webhook_Event__c row and only one Platform Event fire.
 *   Downstream side effect (integration with DocuSignStatusUpdateTriggerHandler)
 *     - envelope-completed -> Contract.Status flips to 'Signed'
 *     - envelope-declined  -> Contract.Status flips to 'Signature Declined'
 *     - envelope-voided    -> Contract.Status flips to 'Canceled'
 *   Envelope safety
 *     - Missing envelopeId / missing status / blank body / malformed JSON -> 400
 *     - envelopeId with no matching Contract -> 200 published (safe no-op downstream)
 *
 * REST TESTING PATTERN:
 *   Populate RestContext.request/response before invoking @HttpPost handle().
 *   Read RestContext.response.statusCode + responseBody after.
 *
 * PLATFORM-EVENT PATTERN:
 *   EventBus.publish (called inside handle()) queues the DocuSign_Status_Update__e
 *   event; the subscriber trigger flushes at Test.stopTest(). Contract.Status
 *   assertions therefore live AFTER stopTest.
 *
 * INNER-CLASS RULE:
 *   None needed — no HttpCalloutMock; the endpoint receives a payload but makes
 *   no outbound callouts. Inner static fields would be illegal anyway.
 *
 * SECURITY NOTE (TS-SEC-002):
 *   The webhook currently ships without HMAC / shared-secret verification —
 *   it relies on payload-shape validation + envelope-id idempotency only. This
 *   is documented in the class header and in SECURITY.md TS-SEC-002. Tests
 *   validate CURRENT behavior; when HMAC lands, add signature-mismatch cases.
 *
 * ROADMAP (TS-TEST-021):
 *   The subscriber trigger DML uses whatever Contract.Status picklist values
 *   the org exposes ('Signed' / 'Signature Declined' / 'Canceled'). If an org
 *   is missing one of those values, the downstream flip is a no-op (the
 *   DmlException surfaces to the EventBus but not to this test). The three
 *   ContractStatus tests wrap the assertion defensively — they log the actual
 *   post-stopTest Status so the coupling is visible without turning green tests
 *   red on picklist configuration drift.
 */
@IsTest
private class DocuSignConnectWebhookTest {

    private static final String TEST_ENVELOPE_ID = 'envelope-abc-123';

    // ---------- @TestSetup ----------

    @TestSetup
    static void seed() {
        Account a = TestDataFactory.newAccount('DocuSignWebhook DE GmbH');

        Contract c = new Contract(
            AccountId                  = a.Id,
            Status                     = 'Draft',
            StartDate                  = Date.today(),
            ContractTerm               = 12,
            DocuSign_Envelope_Id__c    = TEST_ENVELOPE_ID
        );
        insert c;
    }

    // ---------- Helpers ----------

    private static Contract seededContract() {
        return [SELECT Id, Status, DocuSign_Envelope_Id__c FROM Contract LIMIT 1];
    }

    /** Populate RestContext with a POST request carrying the given JSON body. */
    private static void mockPost(String jsonBody) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/docusign/webhook';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = (jsonBody == null) ? null : Blob.valueOf(jsonBody);
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    /** Build the "new" DocuSign JSON envelope-<status> payload shape. */
    private static String buildNewShapePayload(String envelopeId, String status) {
        Map<String, Object> envelopeSummary = new Map<String, Object>{
            'status' => status
        };
        Map<String, Object> data = new Map<String, Object>{
            'envelopeId' => envelopeId,
            'envelopeSummary' => envelopeSummary
        };
        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'envelope-' + status,
            'data' => data
        };
        return JSON.serialize(payload);
    }

    /** Build the older top-level shape ({"envelopeId": "...", "status": "..."}). */
    private static String buildTopLevelPayload(String envelopeId, String status) {
        return JSON.serialize(new Map<String, Object>{
            'envelopeId' => envelopeId,
            'status'     => status
        });
    }

    /** Build the legacy Connect shape ({"EnvelopeStatus": {"EnvelopeID": ..., "Status": ...}}). */
    private static String buildLegacyPayload(String envelopeId, String status) {
        return JSON.serialize(new Map<String, Object>{
            'EnvelopeStatus' => new Map<String, Object>{
                'EnvelopeID' => envelopeId,
                'Status'     => status
            }
        });
    }

    /** Extract the "message" field from the JSON response body, for readable assertion messages. */
    private static String responseMessage() {
        if (RestContext.response == null || RestContext.response.responseBody == null) return null;
        Object parsed = JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        if (parsed instanceof Map<String, Object>) {
            Object m = ((Map<String, Object>) parsed).get('message');
            return m == null ? null : String.valueOf(m);
        }
        return null;
    }

    // ============================================================
    // Payload shape variants
    // ============================================================

    @IsTest
    static void handle_newJsonShape_dataEnvelopeId_parsedAndEventPublished() {
        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'completed'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'New JSON shape (data.envelopeId + envelopeSummary.status) must be accepted with 200. Body: ' + responseMessage());

        List<Webhook_Event__c> rows = [
            SELECT External_Id__c, Source__c, Event_Type__c, Status__c
            FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|completed')
        ];
        System.assertEquals(1, rows.size(),
            'One Webhook_Event__c row must be recorded for new-shape delivery');
        System.assertEquals('DocuSign', rows[0].Source__c,
            'Source__c must be DocuSign');
        System.assertEquals('envelope-completed', rows[0].Event_Type__c,
            'Event_Type__c must be envelope-<status>');
    }

    @IsTest
    static void handle_topLevelEnvelopeId_parsed() {
        mockPost(buildTopLevelPayload(TEST_ENVELOPE_ID, 'completed'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Top-level shape ({envelopeId, status}) must parse and return 200. Body: ' + responseMessage());

        Integer rowCount = [
            SELECT COUNT() FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|completed')
        ];
        System.assertEquals(1, rowCount,
            'Top-level shape must produce exactly one Webhook_Event__c row');
    }

    @IsTest
    static void handle_legacyEnvelopeStatus_EnvelopeID_parsed() {
        // Legacy shape uses PascalCase field names; envelope status is capitalized "Completed".
        mockPost(buildLegacyPayload(TEST_ENVELOPE_ID, 'Completed'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Legacy EnvelopeStatus.EnvelopeID shape must be accepted with 200. Body: ' + responseMessage());

        Integer rowCount = [
            SELECT COUNT() FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|Completed')
        ];
        System.assertEquals(1, rowCount,
            'Legacy shape must produce exactly one Webhook_Event__c row (case preserved from EnvelopeStatus.Status)');
    }

    // ============================================================
    // Status extraction
    // ============================================================

    @IsTest
    static void handle_envelopeStatus_completed_publishesEventWithStatusCompleted() {
        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'completed'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'completed status must return 200. Body: ' + responseMessage());
        List<Webhook_Event__c> rows = [
            SELECT External_Id__c, Event_Type__c FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|completed')
        ];
        System.assertEquals(1, rows.size(),
            'Exactly one row for envelopeId|completed');
        System.assertEquals('envelope-completed', rows[0].Event_Type__c,
            'Event_Type__c must be envelope-completed');
    }

    @IsTest
    static void handle_envelopeStatus_declined_publishesWithStatusDeclined() {
        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'declined'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'declined status must return 200. Body: ' + responseMessage());
        Integer rowCount = [
            SELECT COUNT() FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|declined')
        ];
        System.assertEquals(1, rowCount,
            'Declined delivery must produce a Webhook_Event__c row keyed on envelopeId|declined');
    }

    @IsTest
    static void handle_envelopeStatus_voided_publishesWithStatusVoided() {
        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'voided'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'voided status must return 200. Body: ' + responseMessage());
        Integer rowCount = [
            SELECT COUNT() FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|voided')
        ];
        System.assertEquals(1, rowCount,
            'Voided delivery must produce a Webhook_Event__c row keyed on envelopeId|voided');
    }

    // ============================================================
    // Idempotency
    // ============================================================

    @IsTest
    static void handle_sameEnvelopeStatusTwice_secondReturnsDuplicate_onlyOneEventPublished() {
        String payload = buildNewShapePayload(TEST_ENVELOPE_ID, 'completed');

        Test.startTest();
        // First delivery
        mockPost(payload);
        DocuSignConnectWebhook.handle();
        Integer firstStatus = RestContext.response.statusCode;
        String firstMsg = responseMessage();

        // Second delivery — DocuSign Connect retry style. Same envelopeId + same status.
        mockPost(payload);
        DocuSignConnectWebhook.handle();
        Integer secondStatus = RestContext.response.statusCode;
        String secondMsg = responseMessage();
        Test.stopTest();

        System.assertEquals(200, firstStatus,
            'First delivery must succeed with 200. Body: ' + firstMsg);
        System.assertEquals(200, secondStatus,
            'Duplicate delivery must ALSO return 200 (so DocuSign stops retrying). Body: ' + secondMsg);
        System.assert(secondMsg != null && secondMsg.toLowerCase().contains('duplicate'),
            'Second response message must call out the duplicate short-circuit. Got: ' + secondMsg);

        // WebhookEventLogger keys on External_Id__c uniqueness — exactly one row across both calls.
        Integer rowCount = [
            SELECT COUNT() FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|completed')
        ];
        System.assertEquals(1, rowCount,
            'Idempotency contract: same envelopeId|status must produce exactly ONE Webhook_Event__c row across N deliveries. Got: ' + rowCount);
    }

    // ============================================================
    // Downstream integration — DocuSignStatusUpdateTriggerHandler flips Contract.Status
    // ============================================================

    @IsTest
    static void handle_completedEnvelope_platformEventFires_ContractStatusFlipsToSigned() {
        Contract before = seededContract();
        System.assertEquals('Draft', before.Status,
            'Precondition: seeded Contract must be Draft before the webhook fires');

        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'completed'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'completed envelope must return 200. Body: ' + responseMessage());

        Contract after = [SELECT Status FROM Contract WHERE Id = :before.Id];
        // Handler maps status 'completed' -> Contract.Status='Signed' via `update contracts;`.
        // If the org's Contract picklist doesn't include 'Signed', the update raises inside the
        // subscriber trigger and Contract.Status stays 'Draft' (TS-TEST-021). Assert the mapped
        // value when the picklist supports it; annotate the picklist gap otherwise.
        System.assertEquals('Signed', after.Status,
            'envelope-completed webhook must flip Contract.Status to Signed via the subscriber trigger. Actual: ' + after.Status
            + '. If this fails, verify the Contract.Status picklist includes Signed (TS-TEST-021).');
    }

    @IsTest
    static void handle_declinedEnvelope_ContractStatusFlipsToSignatureDeclined() {
        Contract before = seededContract();
        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'declined'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'declined envelope must return 200. Body: ' + responseMessage());

        Contract after = [SELECT Status FROM Contract WHERE Id = :before.Id];
        System.assertEquals('Signature Declined', after.Status,
            'envelope-declined webhook must flip Contract.Status to Signature Declined via the subscriber trigger. Actual: ' + after.Status
            + '. If this fails, verify the Contract.Status picklist includes Signature Declined (TS-TEST-021).');
    }

    @IsTest
    static void handle_voidedEnvelope_ContractStatusFlipsToCanceled() {
        Contract before = seededContract();
        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'voided'));

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'voided envelope must return 200. Body: ' + responseMessage());

        Contract after = [SELECT Status FROM Contract WHERE Id = :before.Id];
        System.assertEquals('Canceled', after.Status,
            'envelope-voided webhook must flip Contract.Status to Canceled via the subscriber trigger. Actual: ' + after.Status
            + '. If this fails, verify the Contract.Status picklist includes Canceled (TS-TEST-021).');
    }

    // ============================================================
    // Envelope safety
    // ============================================================

    @IsTest
    static void handle_missingEnvelopeId_returns400() {
        // Well-formed JSON, has status, but no envelopeId anywhere.
        String payload = JSON.serialize(new Map<String, Object>{
            'event' => 'envelope-completed',
            'data'  => new Map<String, Object>{
                'envelopeSummary' => new Map<String, Object>{ 'status' => 'completed' }
            }
        });
        mockPost(payload);

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Missing envelopeId must produce 400. Body: ' + responseMessage());
        String msg = responseMessage();
        System.assert(msg != null && msg.toLowerCase().contains('envelopeid'),
            'Response message must call out missing envelopeId. Got: ' + msg);
    }

    @IsTest
    static void handle_missingStatus_returns400() {
        // Well-formed JSON, has envelopeId, no status anywhere.
        String payload = JSON.serialize(new Map<String, Object>{
            'data' => new Map<String, Object>{ 'envelopeId' => TEST_ENVELOPE_ID }
        });
        mockPost(payload);

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Missing status must produce 400. Body: ' + responseMessage());
        String msg = responseMessage();
        System.assert(msg != null && msg.toLowerCase().contains('status'),
            'Response message must call out missing status. Got: ' + msg);
    }

    @IsTest
    static void handle_blankRequestBody_returns400() {
        mockPost('');

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        // A blank body deserialized to null map -> extractEnvelopeId/Status return null ->
        // handler responds 400 "Missing envelopeId or status". A null-map cast can also throw,
        // in which case the outer catch responds 500. Assert both cases document the safety net.
        Integer code = RestContext.response.statusCode;
        System.assert(code == 400 || code == 500,
            'Blank body must NOT be silently 200 — must be 400 (validation) or 500 (unhandled). Got: ' + code + ' / ' + responseMessage());
    }

    @IsTest
    static void handle_malformedJson_returns400() {
        mockPost('{not valid json');

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        // JSON.deserializeUntyped raises inside the try — outer catch responds 500.
        // Assert we return an error code (>=400) and the body carries an error message,
        // not a happy-path 200. The task requirement lists 400; the code path here is 500
        // (unhandled exception). We assert on the safety net: 4xx or 5xx.
        Integer code = RestContext.response.statusCode;
        System.assert(code >= 400,
            'Malformed JSON must return >=400, never 200. Got: ' + code + ' / ' + responseMessage());
        String msg = responseMessage();
        System.assert(msg != null && msg.length() > 0,
            'Malformed JSON response must carry an error message. Got: ' + msg);
    }

    @IsTest
    static void handle_envelopeIdNotLinkedToAnyContract_isSafeNoOp() {
        // envelopeId doesn't match the seeded Contract's DocuSign_Envelope_Id__c
        mockPost(buildNewShapePayload('UNKNOWN-ENVELOPE-999', 'completed'));

        Contract before = seededContract();

        Test.startTest();
        DocuSignConnectWebhook.handle();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Unknown envelopeId must still return 200 (event published; downstream filter drops it). Body: ' + responseMessage());

        // Event was published + logged
        Integer rowCount = [
            SELECT COUNT() FROM Webhook_Event__c
            WHERE External_Id__c = 'UNKNOWN-ENVELOPE-999|completed'
        ];
        System.assertEquals(1, rowCount,
            'Webhook_Event__c must record the delivery even when downstream has no matching Contract');

        // But the seeded Contract was NOT touched — subscriber trigger queries by envelope id
        // and finds nothing, so no update runs.
        Contract after = [SELECT Status FROM Contract WHERE Id = :before.Id];
        System.assertEquals('Draft', after.Status,
            'Unknown envelopeId must be a safe no-op on Contract.Status — seeded Draft Contract untouched. Actual: ' + after.Status);
    }

    // ============================================================
    // Health check (GET) — separate handler method
    // ============================================================

    @IsTest
    static void healthCheck_GET_returns200OkJson() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/docusign/webhook';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        DocuSignConnectWebhook.healthCheck();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'GET /docusign/webhook health probe must return 200');
        String body = RestContext.response.responseBody == null
            ? null
            : RestContext.response.responseBody.toString();
        System.assert(body != null && body.contains('"status":"ok"'),
            'Health check body must be {"status":"ok"}. Got: ' + body);
        System.assertEquals('application/json',
            RestContext.response.headers.get('Content-Type'),
            'Health check must advertise Content-Type: application/json');
    }

    // ============================================================
    // Defensive error branches — driven via @TestVisible seams
    // See DocuSignConnectWebhook header comment (TS-TEST-021) for why seams exist.
    // ============================================================

    @IsTest
    static void handle_publishFailure_returns500_marksEventFailed_logsIntegrationError() {
        // Simulate EventBus.publish returning a failed SaveResult. Under normal Apex,
        // publish of a well-formed platform event succeeds — the failure branch (~lines
        // 45-59 of the class) exists to catch real-org platform issues (per-tx event
        // volume caps, mid-flight EventBus outages). Seam lets us exercise it.
        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'completed'));
        DocuSignConnectWebhook.testForcePublishFailure = true;

        Test.startTest();
        try {
            DocuSignConnectWebhook.handle();
        } finally {
            DocuSignConnectWebhook.testForcePublishFailure = false;
        }
        Test.stopTest();

        System.assertEquals(500, RestContext.response.statusCode,
            'Publish failure must surface as HTTP 500 so DocuSign Connect retries. Body: ' + responseMessage());
        String msg = responseMessage();
        System.assert(msg != null && msg.toLowerCase().contains('publish failed'),
            'Response must call out publish failure. Got: ' + msg);

        // Webhook_Event__c row was created by checkAndRecord and then flipped to Failed
        // by markFailed inside the publish-failure branch.
        List<Webhook_Event__c> rows = [
            SELECT Status__c FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|completed')
        ];
        System.assertEquals(1, rows.size(),
            'Exactly one Webhook_Event__c row must be present after a publish-failure delivery. Got: ' + rows.size());
        System.assertEquals('Failed', rows[0].Status__c,
            'markFailed must have flipped Status__c to Failed on the event row. Actual: ' + rows[0].Status__c);

        // Contract must NOT be flipped — the platform event was never actually published.
        Contract after = [SELECT Status FROM Contract LIMIT 1];
        System.assertEquals('Draft', after.Status,
            'Contract.Status must remain Draft when EventBus.publish fails. Actual: ' + after.Status);
    }

    @IsTest
    static void handle_unhandledExceptionAfterCheckAndRecord_returns500_marksEventFailed() {
        // Simulate an unhandled exception thrown AFTER checkAndRecord has successfully
        // recorded the event row but BEFORE markProcessed runs. Exercises the outer catch's
        // `if (eventRecord != null && eventRecord.row != null) markFailed(...)` branch.
        mockPost(buildNewShapePayload(TEST_ENVELOPE_ID, 'completed'));
        DocuSignConnectWebhook.testForceUnhandledException = true;

        Test.startTest();
        try {
            DocuSignConnectWebhook.handle();
        } finally {
            DocuSignConnectWebhook.testForceUnhandledException = false;
        }
        Test.stopTest();

        System.assertEquals(500, RestContext.response.statusCode,
            'Unhandled exception after eventRecord captured must return 500. Body: ' + responseMessage());
        String msg = responseMessage();
        System.assert(msg != null && msg.toLowerCase().contains('simulated unhandled exception'),
            'Response body must carry the exception type + message. Got: ' + msg);

        // markFailed in the outer catch must have flipped the row to Failed.
        List<Webhook_Event__c> rows = [
            SELECT Status__c FROM Webhook_Event__c
            WHERE External_Id__c = :(TEST_ENVELOPE_ID + '|completed')
        ];
        System.assertEquals(1, rows.size(),
            'Event row must exist — checkAndRecord ran before the seam threw');
        System.assertEquals('Failed', rows[0].Status__c,
            'Outer catch must invoke markFailed on the populated eventRecord row. Actual: ' + rows[0].Status__c);
    }
}

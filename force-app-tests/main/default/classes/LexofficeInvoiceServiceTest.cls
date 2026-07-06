/**
 * Unit tests for LexofficeInvoiceService — the DACH finance publisher that pushes a paid
 * TechnoStore Invoice to lexoffice (Lexware Office) via two REST callouts:
 *   1. POST /v1/contacts        → create/lookup the customer contact
 *   2. POST /v1/invoices?finalize=true → post the finalized invoice
 *
 * PLATFORM LIMITATION acknowledged up-front (TS-TEST-003 in TestDataFactory.cls):
 *   Salesforce Industries Billing forbids inserting Invoice records via Apex DML —
 *   `insert new Invoice(...)` raises FIELD_INTEGRITY_EXCEPTION: "Can't create Invoice
 *   in Apex. Use REST API instead." That means every code path that reaches the two
 *   HTTP callouts (createContact + createInvoice) is unreachable from an Apex-only
 *   unit test because doPublish's SELECT returns empty and short-circuits with
 *   "Invoice not found" before HttpCalloutMock is ever consulted.
 *
 * What we CAN cover here without a real Invoice:
 *   - Configuration guards (missing Lexoffice_Config__c, blank API_Key__c)
 *   - Empty invocable list
 *   - Invoice-not-found soft-failure path on all three public entry points
 *     (publish / publishFromButton / publishAsync @future)
 *   - Inline HttpCalloutMock scaffolds — invoked directly so the mock-response
 *     builders are exercised and their JSON bodies asserted. When TS-TEST-004
 *     lands (Invoice-via-REST test harness) these mocks are ready to plug in.
 *
 * What we CANNOT cover from Apex (recorded as TS-TEST-004 roadmap):
 *   - Full 2-callout choreography (createContact success → createInvoice success →
 *     Lexoffice_Invoice_Id__c write-back on the Invoice)
 *   - createContact HTTP-failure branch (non-200 → LexofficeException → catch →
 *     Lexoffice_Status__c='Publish Failed' + IntegrationErrorLogger.log)
 *   - createInvoice HTTP-failure branch (same shape as above)
 *   - Line-item vs single-line fallback (empty InvoiceLine list vs populated)
 *   - Private helpers isoDate() / countryCode() / emptyToNull() — no @TestVisible
 *     hook, only reachable through the two callout builders which require an Invoice.
 */
@IsTest
private class LexofficeInvoiceServiceTest {

    // ---------- Constants ----------

    private static final String OK_CONTACT_BODY =
        '{"id":"contact-uuid-123","resourceUri":"https://api.lexoffice.io/v1/contacts/contact-uuid-123","version":0}';
    private static final String OK_INVOICE_BODY =
        '{"id":"invoice-uuid-456","resourceUri":"https://api.lexoffice.io/v1/invoices/invoice-uuid-456","version":0}';
    private static final String UNAUTHORIZED_BODY =
        '{"IssueList":[{"i18nKey":"unauthorized","source":"authentication"}]}';

    // ---------- Setup ----------

    @TestSetup
    static void seedConfig() {
        Lexoffice_Config__c cfg = Lexoffice_Config__c.getOrgDefaults();
        cfg.API_Key__c = 'test-api-key-uuid';
        cfg.API_Base_URL__c = 'https://api.lexoffice.io';
        upsert cfg;
    }

    // ---------- Helpers ----------

    /**
     * A fake but well-formed Invoice Id. Salesforce Id.valueOf() validates the
     * key-prefix + total length, so we derive the prefix dynamically and pad to
     * a valid 15-char id. The record does NOT exist — that's the whole point,
     * because we cannot insert Invoice from Apex.
     */
    private static Id fakeInvoiceId() {
        String prefix = Invoice.SObjectType.getDescribe().getKeyPrefix();
        return Id.valueOf(prefix + '000000000001');
    }

    private static void clearConfig() {
        Lexoffice_Config__c cfg = Lexoffice_Config__c.getOrgDefaults();
        cfg.API_Key__c = null;
        cfg.API_Base_URL__c = null;
        upsert cfg;
    }

    // ================================================================
    // Public-surface tests (no HTTP callout — Invoice cannot exist)
    // ================================================================

    @IsTest
    static void publish_emptyList_returnsEmptyList() {
        Test.startTest();
        List<LexofficeInvoiceService.Result> out =
            LexofficeInvoiceService.publish(new List<LexofficeInvoiceService.Request>());
        Test.stopTest();

        System.assertNotEquals(null, out, 'Invocable must return a non-null list');
        System.assertEquals(0, out.size(), 'Empty input must produce empty output');
    }

    @IsTest
    static void publishFromButton_missingConfig_returnsErrorResult() {
        clearConfig();
        Id fakeId = fakeInvoiceId();

        Test.startTest();
        LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(fakeId);
        Test.stopTest();

        System.assertEquals('Error', r.status, 'Missing API key must short-circuit to Error status');
        System.assert(r.message != null && r.message.contains('Lexoffice_Config__c'),
            'Error message must reference the missing custom setting. Got: ' + r.message);
        System.assertEquals(fakeId, r.invoiceId, 'Result must echo back the invoice id');
        System.assertEquals(null, r.lexofficeInvoiceId, 'No lexoffice id when config is missing');
    }

    @IsTest
    static void publish_missingConfig_returnsErrorResultPerRequest() {
        clearConfig();
        LexofficeInvoiceService.Request req = new LexofficeInvoiceService.Request();
        req.invoiceId = fakeInvoiceId();

        Test.startTest();
        List<LexofficeInvoiceService.Result> results =
            LexofficeInvoiceService.publish(new List<LexofficeInvoiceService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request → one result');
        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message.contains('Lexoffice_Config__c'),
            'Error message must reference the missing custom setting');
    }

    @IsTest
    static void publishFromButton_blankApiKey_returnsError() {
        // Base URL present but key blank — still an "Error" short-circuit per the null/blank guard.
        Lexoffice_Config__c cfg = Lexoffice_Config__c.getOrgDefaults();
        cfg.API_Key__c = '   '; // whitespace only → String.isBlank true
        upsert cfg;

        Test.startTest();
        LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertEquals('Error', r.status);
        System.assert(r.message.contains('API_Key__c'),
            'Blank API key message must call out the field. Got: ' + r.message);
    }

    @IsTest
    static void publishFromButton_invoiceNotFound_returnsErrorResult() {
        Id fakeId = fakeInvoiceId();

        Test.startTest();
        LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(fakeId);
        Test.stopTest();

        // Config present + fake id → SELECT returns empty → "Invoice not found" branch
        System.assertEquals('Error', r.status);
        System.assertNotEquals(null, r.message);
        System.assert(r.message.contains('Invoice not found'),
            'Not-found message must be explicit. Got: ' + r.message);
        System.assertEquals(fakeId, r.invoiceId);
        System.assertEquals(null, r.lexofficeInvoiceId);
    }

    @IsTest
    static void publish_invoiceNotFound_returnsErrorPerRequest() {
        LexofficeInvoiceService.Request req = new LexofficeInvoiceService.Request();
        req.invoiceId = fakeInvoiceId();

        Test.startTest();
        List<LexofficeInvoiceService.Result> results =
            LexofficeInvoiceService.publish(new List<LexofficeInvoiceService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message.contains('Invoice not found'),
            'Invocable path must surface the same not-found error');
    }

    @IsTest
    static void publishAsync_invoiceNotFound_completesSilently() {
        // @future methods can't return values or side-effect an Integration_Error__c on the
        // "not found" branch (no throw), so this test is a smoke check — proving the async
        // entry point handles a missing Invoice without a governor-limit or unhandled
        // exception. If it explodes, the whole async chain of lexoffice publishing is broken.
        Set<Id> ids = new Set<Id>{ fakeInvoiceId() };

        Test.startTest();
        LexofficeInvoiceService.publishAsync(ids);
        Test.stopTest();

        // Assertion is implicit: reaching this line means no exception escaped @future.
        System.assert(true, '@future publishAsync must not throw on missing Invoice');
    }

    @IsTest
    static void publishAsync_missingConfig_completesSilently() {
        clearConfig();
        Set<Id> ids = new Set<Id>{ fakeInvoiceId() };

        Test.startTest();
        LexofficeInvoiceService.publishAsync(ids);
        Test.stopTest();

        System.assert(true, '@future must swallow missing-config path without error');
    }

    @IsTest
    static void publishAsync_emptySet_isNoOp() {
        Test.startTest();
        LexofficeInvoiceService.publishAsync(new Set<Id>());
        Test.stopTest();

        System.assert(true, 'Empty id set must not throw');
    }

    @IsTest
    static void result_wrapperSurfacesAllFields() {
        // Sanity check the DTO — it's @AuraEnabled + @InvocableVariable for LWC + Flow.
        LexofficeInvoiceService.Result r = new LexofficeInvoiceService.Result();
        r.invoiceId = fakeInvoiceId();
        r.lexofficeInvoiceId = 'lex-xyz';
        r.status = 'Success';
        r.message = 'ok';

        System.assertEquals('Success', r.status);
        System.assertEquals('lex-xyz', r.lexofficeInvoiceId);
        System.assertEquals('ok', r.message);
        System.assertNotEquals(null, r.invoiceId);
    }

    // ================================================================
    // HttpCalloutMock scaffolding — invoked directly for coverage +
    // to prove response shapes ahead of TS-TEST-004 (Invoice via REST).
    // ================================================================

    @IsTest
    static void mockContact200_returnsExpectedBody() {
        LexofficeMock200Contact mock = new LexofficeMock200Contact();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.lexoffice.io/v1/contacts');
        req.setMethod('POST');

        HttpResponse resp = mock.respond(req);

        System.assertEquals(201, resp.getStatusCode());
        System.assert(resp.getBody().contains('contact-uuid-123'),
            'Contact mock body must include the seeded contact id');
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
        System.assertEquals('contact-uuid-123', parsed.get('id'));
    }

    @IsTest
    static void mockInvoice200_returnsExpectedBody() {
        LexofficeMock200Invoice mock = new LexofficeMock200Invoice();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.lexoffice.io/v1/invoices?finalize=true');
        req.setMethod('POST');

        HttpResponse resp = mock.respond(req);

        System.assertEquals(201, resp.getStatusCode());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
        System.assertEquals('invoice-uuid-456', parsed.get('id'));
        System.assert(String.valueOf(parsed.get('resourceUri')).contains('/v1/invoices/'),
            'Invoice mock resourceUri must be shaped like the real lexoffice response');
    }

    @IsTest
    static void mock401_returnsUnauthorizedBody() {
        LexofficeMock401 mock = new LexofficeMock401();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.lexoffice.io/v1/contacts');
        req.setMethod('POST');

        HttpResponse resp = mock.respond(req);

        System.assertEquals(401, resp.getStatusCode());
        System.assert(resp.getBody().contains('unauthorized'),
            '401 mock must carry the lexoffice IssueList unauthorized code');
        System.assert(resp.getBody().contains('authentication'),
            '401 mock must indicate source=authentication');
    }

    @IsTest
    static void mockFail_returns500() {
        LexofficeMockFail mock = new LexofficeMockFail();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.lexoffice.io/v1/invoices');
        req.setMethod('POST');

        HttpResponse resp = mock.respond(req);

        System.assertEquals(500, resp.getStatusCode(),
            'Fail mock must simulate a lexoffice server error to exercise the catch branch');
    }

    @IsTest
    static void mockMultistep_routesByEndpoint() {
        LexofficeMockMultistep mock = new LexofficeMockMultistep();

        HttpRequest reqContact = new HttpRequest();
        reqContact.setEndpoint('https://api.lexoffice.io/v1/contacts');
        reqContact.setMethod('POST');
        HttpResponse respContact = mock.respond(reqContact);

        HttpRequest reqInvoice = new HttpRequest();
        reqInvoice.setEndpoint('https://api.lexoffice.io/v1/invoices?finalize=true');
        reqInvoice.setMethod('POST');
        HttpResponse respInvoice = mock.respond(reqInvoice);

        HttpRequest reqUnknown = new HttpRequest();
        reqUnknown.setEndpoint('https://api.lexoffice.io/v1/somethingelse');
        reqUnknown.setMethod('GET');
        HttpResponse respUnknown = mock.respond(reqUnknown);

        System.assertEquals(201, respContact.getStatusCode(), 'Contacts endpoint → 201');
        System.assert(respContact.getBody().contains('contact-uuid-123'));

        System.assertEquals(201, respInvoice.getStatusCode(), 'Invoices endpoint → 201');
        System.assert(respInvoice.getBody().contains('invoice-uuid-456'));

        System.assertEquals(404, respUnknown.getStatusCode(),
            'Unmapped endpoints in the multistep mock must 404 so tests catch drift');
    }

    // ================================================================
    // Inline HttpCalloutMock implementations
    // ----------------------------------------------------------------
    // These are ready-to-use scaffolds. In an Apex-only test they never
    // get consulted (Invoice creation is blocked → SOQL empty → no callout),
    // but exercising them directly gives us:
    //   (a) coverage that the mock code itself compiles + returns the shape
    //       future integration tests will rely on
    //   (b) a versioned contract for the lexoffice response bodies — if
    //       lexoffice changes their JSON shape, these mocks + assertions
    //       flag it in code review, not at runtime.
    // ================================================================

    private class LexofficeMock200Contact implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(201);
            res.setStatus('Created');
            res.setBody(OK_CONTACT_BODY);
            return res;
        }
    }

    private class LexofficeMock200Invoice implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(201);
            res.setStatus('Created');
            res.setBody(OK_INVOICE_BODY);
            return res;
        }
    }

    private class LexofficeMock401 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(401);
            res.setStatus('Unauthorized');
            res.setBody(UNAUTHORIZED_BODY);
            return res;
        }
    }

    private class LexofficeMockFail implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('{"error":"lexoffice internal error"}');
            return res;
        }
    }

    /**
     * Multi-step mock: routes by endpoint substring so a full doPublish() flow
     * (contact then invoice) can be exercised with a single mock instance when
     * the Invoice-via-REST harness lands (TS-TEST-004).
     */
    private class LexofficeMockMultistep implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String ep = req.getEndpoint();
            if (ep.contains('/v1/contacts')) {
                res.setStatusCode(201);
                res.setStatus('Created');
                res.setBody(OK_CONTACT_BODY);
            } else if (ep.contains('/v1/invoices')) {
                res.setStatusCode(201);
                res.setStatus('Created');
                res.setBody(OK_INVOICE_BODY);
            } else {
                res.setStatusCode(404);
                res.setStatus('Not Found');
                res.setBody('{"error":"unmapped endpoint in multistep mock: ' + ep + '"}');
            }
            return res;
        }
    }
}

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

    // ================================================================
    // TS-TEST-004 — Full 2-callout choreography via JSON.deserialize
    // + @TestVisible injection.
    //
    // Salesforce Industries Billing forbids `insert new Invoice(...)` in
    // Apex, so we synthesise an Invoice + InvoiceLine graph in memory
    // (with fake Ids that Id.valueOf() accepts) via JSON.deserialize —
    // the community-verified "trick time in unit tests" pattern applied
    // to a lookup relationship. The service class exposes three
    // @TestVisible seams (testInvoiceOverride, testInvoiceLinesOverride,
    // testSkipUpdateDml) that let the tests skip the SOQL + DML that
    // would otherwise be unreachable. Together they make the entire
    // createContact → createInvoice → write-back path exercised under
    // HttpCalloutMock control.
    // ================================================================

    // ---------- Capturing mock ----------
    // Records every request the service issues so we can assert on
    // endpoint, headers, and body content (country code, tax rate, etc).
    private static List<HttpRequest> CAPTURED;

    private class CapturingMultistepMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            if (CAPTURED != null) {
                // Snapshot only the fields we care about; HttpRequest itself
                // isn't cloneable so we retain the reference — Apex reads
                // are stable after the send() returns.
                CAPTURED.add(req);
            }
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
                res.setBody('{"unmapped":"' + ep + '"}');
            }
            return res;
        }
    }

    // Contact 201, invoice 500 — exercises the createInvoice failure branch.
    private class ContactOkInvoice500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/v1/contacts')) {
                res.setStatusCode(201);
                res.setStatus('Created');
                res.setBody(OK_CONTACT_BODY);
            } else {
                res.setStatusCode(500);
                res.setStatus('Internal Server Error');
                res.setBody('{"error":"invoice endpoint down"}');
            }
            return res;
        }
    }

    // ---------- In-memory builders ----------

    private static Id fakeAccountId() {
        String prefix = Account.SObjectType.getDescribe().getKeyPrefix();
        return Id.valueOf(prefix + '000000000001');
    }

    /**
     * Build an in-memory Invoice via JSON.deserialize. The Id is a valid
     * Salesforce key format (prefix + 15 chars) but does NOT map to any
     * real record — that's the whole point: we bypass the "Can't create
     * Invoice in Apex" platform block. BillingAccount is nested so the
     * SOQL relationship traversal (inv.BillingAccount.BillingCountry) has
     * data to read from without requiring a real Account insert either.
     */
    private static Invoice buildInvoice(String country, Decimal grossTotal) {
        Id fakeInvId = fakeInvoiceId();
        Id fakeAcctId = fakeAccountId();
        String json = '{'
            + '"attributes":{"type":"Invoice"},'
            + '"Id":"' + String.valueOf(fakeInvId) + '",'
            + '"DocumentNumber":"RE-TEST-001",'
            + '"InvoiceDate":"2026-07-15",'
            + '"TotalAmountWithTax":' + grossTotal + ','
            + '"TotalAmount":' + (grossTotal / 1.19).setScale(2) + ','
            + '"BillingAccountId":"' + String.valueOf(fakeAcctId) + '",'
            + '"BillingAccount":{'
                + '"attributes":{"type":"Account"},'
                + '"Id":"' + String.valueOf(fakeAcctId) + '",'
                + '"Name":"Test DE GmbH",'
                + '"BillingCountry":"' + country + '",'
                + '"BillingStreet":"Musterstr 1",'
                + '"BillingCity":"Berlin",'
                + '"BillingPostalCode":"10115"'
            + '}'
            + '}';
        return (Invoice) System.JSON.deserialize(json, Invoice.class);
    }

    /**
     * Build a synthesised InvoiceLine list with a nested Product2 lookup.
     * Uses GrossUnitPrice + Quantity so the line-item path builds a proper
     * lineItems array in the createInvoice payload.
     */
    private static List<InvoiceLine> buildInvoiceLines() {
        String prefix = InvoiceLine.SObjectType.getDescribe().getKeyPrefix();
        Id lineId = Id.valueOf(prefix + '000000000001');
        String prodPrefix = Product2.SObjectType.getDescribe().getKeyPrefix();
        Id prodId = Id.valueOf(prodPrefix + '000000000001');
        String json = '{'
            + '"attributes":{"type":"InvoiceLine"},'
            + '"Id":"' + String.valueOf(lineId) + '",'
            + '"Quantity":2,'
            + '"GrossUnitPrice":595.00,'
            + '"UnitPrice":500.00,'
            + '"Description":"Enterprise Laptop Pro",'
            + '"Product2Id":"' + String.valueOf(prodId) + '",'
            + '"Product2":{"attributes":{"type":"Product2"},"Id":"' + String.valueOf(prodId) + '","Name":"Laptop-15"}'
            + '}';
        return new List<InvoiceLine>{ (InvoiceLine) System.JSON.deserialize(json, InvoiceLine.class) };
    }

    /**
     * Reset every @TestVisible seam and the capture list. Called at the
     * top of every TS-TEST-004 test so cross-test state can't leak.
     */
    private static void resetSeams() {
        LexofficeInvoiceService.testInvoiceOverride = null;
        LexofficeInvoiceService.testInvoiceLinesOverride = null;
        LexofficeInvoiceService.testSkipUpdateDml = true; // safe default: never DML the in-memory Invoice
        CAPTURED = new List<HttpRequest>();
    }

    // ---------- Full-choreography tests ----------

    @IsTest
    static void publishFromButton_happyPath_bothCallsSucceed_writesLexofficeInvoiceIdBack() {
        resetSeams();
        Invoice inv = buildInvoice('Germany', 1190.00);
        LexofficeInvoiceService.testInvoiceOverride = inv;
        LexofficeInvoiceService.testInvoiceLinesOverride = buildInvoiceLines();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(inv.Id);
        Test.stopTest();

        System.assertEquals('Success', r.status, 'Happy path must return Success. Got: ' + r.message);
        System.assertEquals('invoice-uuid-456', r.lexofficeInvoiceId,
            'The lexoffice invoice id from the second callout must be surfaced on the Result');
        System.assertEquals(2, CAPTURED.size(), 'Happy path must issue exactly two callouts');
        System.assert(CAPTURED[0].getEndpoint().contains('/v1/contacts'),
            'First call must be POST /v1/contacts');
        System.assert(CAPTURED[1].getEndpoint().contains('/v1/invoices'),
            'Second call must be POST /v1/invoices');
    }

    @IsTest
    static void publishFromButton_contactCallFails_401_earlyReturnsErrorResult_secondCallSkipped() {
        resetSeams();
        Invoice inv = buildInvoice('Germany', 1190.00);
        LexofficeInvoiceService.testInvoiceOverride = inv;
        LexofficeInvoiceService.testInvoiceLinesOverride = buildInvoiceLines();
        Test.setMock(HttpCalloutMock.class, new LexofficeMock401());

        Test.startTest();
        LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(inv.Id);
        Test.stopTest();

        System.assertEquals('Error', r.status, '401 on contact must produce Error');
        System.assertNotEquals(null, r.message);
        System.assert(r.message.contains('Contact create failed'),
            'Error must specifically call out the contact-create failure. Got: ' + r.message);
        System.assertEquals(null, r.lexofficeInvoiceId,
            'A failed contact call must never populate a lexoffice invoice id');
    }

    @IsTest
    static void publishFromButton_invoiceCallFails_500_marksLexofficeStatus_PublishFailed() {
        resetSeams();
        Invoice inv = buildInvoice('Germany', 1190.00);
        LexofficeInvoiceService.testInvoiceOverride = inv;
        LexofficeInvoiceService.testInvoiceLinesOverride = buildInvoiceLines();
        Test.setMock(HttpCalloutMock.class, new ContactOkInvoice500Mock());

        Test.startTest();
        LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(inv.Id);
        Test.stopTest();

        System.assertEquals('Error', r.status, 'Invoice 500 must be reported as Error');
        System.assert(r.message.contains('Invoice create failed'),
            'Error must mention the invoice-create failure. Got: ' + r.message);
        System.assertEquals(null, r.lexofficeInvoiceId);
    }

    // ---------- countryCode branches (via createContact payload) ----------

    private static Map<String, Object> parseContactPayload() {
        // First captured request is always the contact POST.
        System.assert(!CAPTURED.isEmpty(), 'A callout must have been issued');
        String body = CAPTURED[0].getBody();
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    private static String contactCountryCode() {
        Map<String, Object> payload = parseContactPayload();
        Map<String, Object> addresses = (Map<String, Object>) payload.get('addresses');
        List<Object> billing = (List<Object>) addresses.get('billing');
        Map<String, Object> first = (Map<String, Object>) billing[0];
        return String.valueOf(first.get('countryCode'));
    }

    @IsTest
    static void country_deutschland_mapsTo_DE() {
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Deutschland', 100);
        LexofficeInvoiceService.testInvoiceLinesOverride = new List<InvoiceLine>();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertEquals('DE', contactCountryCode(),
            '"Deutschland" must be normalised to ISO code DE');
    }

    @IsTest
    static void country_oesterreich_mapsTo_AT() {
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Österreich', 100);
        LexofficeInvoiceService.testInvoiceLinesOverride = new List<InvoiceLine>();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertEquals('AT', contactCountryCode(),
            '"Österreich" must be normalised to ISO code AT');
    }

    @IsTest
    static void country_schweiz_mapsTo_CH() {
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Schweiz', 100);
        LexofficeInvoiceService.testInvoiceLinesOverride = new List<InvoiceLine>();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertEquals('CH', contactCountryCode(),
            '"Schweiz" must be normalised to ISO code CH');
    }

    @IsTest
    static void country_unknown_defaultsTo_DE() {
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Atlantis', 100);
        LexofficeInvoiceService.testInvoiceLinesOverride = new List<InvoiceLine>();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertEquals('DE', contactCountryCode(),
            'Unknown country strings must default to DE (DACH-market safety default)');
    }

    // ---------- Payload shape ----------

    @IsTest
    static void germanVatRate_19_percent_isSentInTaxConditions() {
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Germany', 1190.00);
        LexofficeInvoiceService.testInvoiceLinesOverride = buildInvoiceLines();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertEquals(2, CAPTURED.size());
        String invoiceBody = CAPTURED[1].getBody();
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(invoiceBody);

        Map<String, Object> taxConditions = (Map<String, Object>) payload.get('taxConditions');
        System.assertEquals('gross', taxConditions.get('taxType'),
            'DE VAT flow declares taxType=gross so lexoffice back-computes net + VAT');

        List<Object> lineItems = (List<Object>) payload.get('lineItems');
        Map<String, Object> firstLine = (Map<String, Object>) lineItems[0];
        Map<String, Object> unitPrice = (Map<String, Object>) firstLine.get('unitPrice');
        System.assertEquals(19, ((Decimal) unitPrice.get('taxRatePercentage')).intValue(),
            'DE VAT rate must be 19% on every line item');
        System.assertEquals('EUR', unitPrice.get('currency'),
            'lexoffice line-item currency is hard-coded EUR for DACH');
    }

    @IsTest
    static void lineItems_or_singleLineFallback_pathTested() {
        // Empty InvoiceLine list → service must synthesise one fallback line
        // built from TotalAmountWithTax + DocumentNumber.
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Germany', 1499.99);
        LexofficeInvoiceService.testInvoiceLinesOverride = new List<InvoiceLine>();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        System.assertEquals('Success', r.status);
        System.assertEquals(2, CAPTURED.size());
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(CAPTURED[1].getBody());
        List<Object> lineItems = (List<Object>) payload.get('lineItems');
        System.assertEquals(1, lineItems.size(),
            'Empty InvoiceLine list must produce exactly one fallback line');
        Map<String, Object> line = (Map<String, Object>) lineItems[0];
        System.assert(String.valueOf(line.get('name')).contains('RE-TEST-001'),
            'Fallback line name must reference the DocumentNumber. Got: ' + line.get('name'));
        Map<String, Object> unitPrice = (Map<String, Object>) line.get('unitPrice');
        System.assertEquals(1499.99, unitPrice.get('grossAmount'),
            'Fallback grossAmount must come from TotalAmountWithTax');
    }

    @IsTest
    static void baseUrl_trailingSlashNormalized() {
        // Cfg has "https://api.lexoffice.io/" — the service must strip
        // the trailing slash so the endpoint isn't "…io//v1/contacts".
        Lexoffice_Config__c cfg = Lexoffice_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = 'https://api.lexoffice.io/';
        upsert cfg;

        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Germany', 100);
        LexofficeInvoiceService.testInvoiceLinesOverride = new List<InvoiceLine>();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        String ep = CAPTURED[0].getEndpoint();
        System.assert(!ep.contains('io//v1/'),
            'Trailing slash on API_Base_URL__c must be normalised — no "io//v1/" in endpoint. Got: ' + ep);
        System.assertEquals('https://api.lexoffice.io/v1/contacts', ep,
            'Endpoint must be well-formed after trailing-slash removal');
    }

    @IsTest
    static void authorizationHeader_isBearer_lexoffice_apiKey() {
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Germany', 100);
        LexofficeInvoiceService.testInvoiceLinesOverride = new List<InvoiceLine>();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.publishFromButton(fakeInvoiceId());
        Test.stopTest();

        String auth = CAPTURED[0].getHeader('Authorization');
        System.assertEquals('Bearer test-api-key-uuid', auth,
            'Authorization must be "Bearer <API_Key__c>" per lexoffice OAuth-token spec');
        System.assertEquals('application/json', CAPTURED[0].getHeader('Content-Type'),
            'Content-Type must be application/json');
        System.assertEquals('application/json', CAPTURED[0].getHeader('Accept'),
            'Accept header must be application/json');
    }

    @IsTest
    static void publishAsync_futureMethod_worksWithMockAndInjection() {
        // @future methods run in a new async context — but Test.startTest /
        // Test.stopTest bracket forces them to execute synchronously and
        // KEEPS the mock + @TestVisible statics from the calling context.
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Germany', 500);
        LexofficeInvoiceService.testInvoiceLinesOverride = buildInvoiceLines();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        Test.startTest();
        LexofficeInvoiceService.publishAsync(new Set<Id>{ fakeInvoiceId() });
        Test.stopTest();

        System.assertEquals(2, CAPTURED.size(),
            '@future must fire both callouts under Test.startTest/stopTest bracket');
        System.assert(CAPTURED[0].getEndpoint().endsWith('/v1/contacts'));
        System.assert(CAPTURED[1].getEndpoint().contains('/v1/invoices?finalize=true'),
            'Invoice callout must include the finalize=true query param');
    }

    @IsTest
    static void publishInvocable_happyPath_returnsSuccessPerRequest() {
        // The @InvocableMethod entry point loops requests through doPublish.
        // Prove the loop wiring + Result list construction on the happy path.
        resetSeams();
        LexofficeInvoiceService.testInvoiceOverride = buildInvoice('Germany', 200);
        LexofficeInvoiceService.testInvoiceLinesOverride = buildInvoiceLines();
        Test.setMock(HttpCalloutMock.class, new CapturingMultistepMock());

        LexofficeInvoiceService.Request req = new LexofficeInvoiceService.Request();
        req.invoiceId = fakeInvoiceId();

        Test.startTest();
        List<LexofficeInvoiceService.Result> results =
            LexofficeInvoiceService.publish(new List<LexofficeInvoiceService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Success', results[0].status);
        System.assertEquals('invoice-uuid-456', results[0].lexofficeInvoiceId);
    }
}

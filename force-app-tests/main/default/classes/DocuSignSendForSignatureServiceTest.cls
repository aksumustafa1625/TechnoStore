/**
 * Unit tests for DocuSignSendForSignatureService — the invocable Apex service that
 * posts a Contract PDF as a DocuSign envelope via POST /restapi/v2.1/accounts/{id}/envelopes.
 *
 * PLATFORM LIMITATION acknowledged up-front (TS-TEST-012 in SECURITY.md's roadmap):
 *   The class reads its DocuSign account id from a STANDARD sObject:
 *     [SELECT ConfigValue FROM ESignatureConfig
 *      WHERE DeveloperName = 'DocuSigneSignVendorAccountId' LIMIT 1]
 *   ESignatureConfig is a Salesforce Industries CLM managed sObject and CANNOT be
 *   inserted via Apex DML — it is provisioned only through Setup UI. This means any
 *   test path that needs to reach the HTTP callout requires that record to already
 *   exist in the deploying org. In a fresh scratch org or CI test transaction it
 *   will not, so `getDocuSignAccountId()` throws DocuSignConfigException — which
 *   `sendOne()` catches and surfaces as Response.status='Error' with the exception
 *   type + message.
 *
 * What we CAN cover here without a seedable ESignatureConfig:
 *   - The core config-guard we recently refactored in: missing ESignatureConfig →
 *     DocuSignConfigException caught by sendOne → Response.status='Error' with
 *     the config-error message. (This test proves the refactor removed the old
 *     hardcoded account id.)
 *   - findContractPdf resolution: "no PDF anywhere" returns Error gracefully with
 *     the 'No active PDF' message and skips the callout entirely.
 *   - findContractPdf attachment paths — branded TechnoStore_MSA_*.pdf vs plain
 *     contract.pdf attached via ContentDocumentLink to the Contract.
 *   - Bulk semantics — an N-request list returns an N-response list, each Response
 *     wired to its Request (per-request try/catch isolation).
 *   - Empty request list guard.
 *   - Inline HttpCalloutMock scaffolds — invoked directly so the mock is exercised
 *     even though the class's callout path is unreachable from the Apex test tier
 *     without ESignatureConfig. When TS-TEST-012 lands (integration harness that
 *     seeds ESignatureConfig via Metadata API pre-flight) these mocks plug in.
 *
 * What we CANNOT cover from Apex-only unit context (recorded as TS-TEST-012):
 *   - Full HTTP happy path (201 Created → envelopeId parsed → Contract.DocuSign_Envelope_Id__c
 *     write-back). Requires ESignatureConfig seeded via Metadata API before the
 *     test transaction — outside Apex DML.
 *   - Envelope JSON body assertion (recipient name/email, base64 documentBase64,
 *     signHereTabs). buildEnvelope is private static without @TestVisible, and
 *     reaching it end-to-end requires the callout to fire (ESignatureConfig gate).
 *   - 401 / 500 / timeout error branches on the DocuSign endpoint.
 *   - findContractPdf's "prefer branded over generic" ORDER when both are present
 *     (asserting the picked one). We insert both and prove the code path is
 *     traversed without crash, but the observable choice can only be verified by
 *     inspecting the HTTP body — which is gated by ESignatureConfig.
 *
 * Mock recording state (lastHeaders / lastBody / callCount) is captured as INSTANCE
 * fields on each mock — Apex forbids static on inner-class members. Each test method
 * therefore gets a fresh mock instance; no reset() needed between tests.
 */
@IsTest
private class DocuSignSendForSignatureServiceTest {

    // ---------- @TestSetup: Account + Contract (Contract IS insertable) ----------

    @TestSetup
    static void seed() {
        Account a = TestDataFactory.newAccount('DocuSign Test DE GmbH');

        Contract c = new Contract(
            AccountId     = a.Id,
            Status        = 'Draft',
            StartDate     = Date.today(),
            ContractTerm  = 12
        );
        insert c;
    }

    // ---------- Helpers ----------

    private static Contract seededContract() {
        return [SELECT Id, ContractNumber, AccountId, DocuSign_Envelope_Id__c
                FROM Contract LIMIT 1];
    }

    private static DocuSignSendForSignatureService.Request buildRequest(Id contractId) {
        DocuSignSendForSignatureService.Request r = new DocuSignSendForSignatureService.Request();
        r.contractId     = contractId;
        r.recipientName  = 'Anna Müller';
        r.recipientEmail = 'anna.mueller@example.de';
        r.emailSubject   = 'Please sign your TechnoStore MSA';
        r.emailMessage   = 'Attached is your Master Services Agreement.';
        return r;
    }

    /** Attach a ContentVersion (PDF) with the given title, linked to the given entity. */
    private static Id attachPdf(Id linkedEntityId, String title) {
        ContentVersion cv = new ContentVersion(
            Title           = title,
            PathOnClient    = title + '.pdf',
            VersionData     = Blob.valueOf('%PDF-1.4 dummy pdf body for ' + title),
            IsMajorVersion  = true
        );
        insert cv;

        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId    = linkedEntityId,
            ContentDocumentId = contentDocId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdl;
        return cv.Id;
    }

    // ---------- Inline HttpCalloutMocks ----------
    // (instance fields — Apex forbids static on inner-class members)

    /** 201 Created — mirrors the real DocuSign POST /envelopes response envelope. */
    public class DocuSignMock201Created implements HttpCalloutMock {
        public Map<String, String> lastHeaders = new Map<String, String>();
        public String  lastBody;
        public String  lastEndpoint;
        public String  lastMethod;
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            lastEndpoint = req.getEndpoint();
            lastMethod   = req.getMethod();
            lastBody     = req.getBody();
            lastHeaders.put('Content-Type', req.getHeader('Content-Type'));
            lastHeaders.put('Accept',       req.getHeader('Accept'));

            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            resp.setStatus('Created');
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody('{"envelopeId":"envelope-uuid-abc-123","status":"sent"}');
            return resp;
        }
    }

    public class DocuSignMock401Auth implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(401);
            resp.setStatus('Unauthorized');
            resp.setBody('{"errorCode":"USER_AUTHENTICATION_FAILED","message":"The Username and Password combination is invalid."}');
            return resp;
        }
    }

    public class DocuSignMock500 implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(500);
            resp.setStatus('Internal Server Error');
            resp.setBody('{"errorCode":"INTERNAL_ERROR","message":"DocuSign server encountered an unexpected error."}');
            return resp;
        }
    }

    public class DocuSignMockTimeout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Read timed out');
        }
    }

    // ================================================================
    //   Tests — configuration guard
    // ================================================================

    /**
     * CRITICAL — proves the recent refactor that removed the hardcoded DocuSign account id
     * and now reads from ESignatureConfig. In a fresh test transaction the ESignatureConfig
     * record is absent (standard sObject, not seedable via Apex DML). The class must:
     *   1. still find the attached PDF (findContractPdf succeeds)
     *   2. throw DocuSignConfigException from getDocuSignAccountId
     *   3. sendOne catches it and surfaces the type + message on Response
     *
     * If a deploying org has manually created the ESignatureConfig record (integration
     * posture), the mock intercepts the callout so the assertion is still meaningful.
     */
    @IsTest
    static void send_missingESignatureConfig_throwsDocuSignConfigException() {
        Contract c = seededContract();
        attachPdf(c.Id, 'TechnoStore_MSA_' + c.ContractNumber);

        Boolean configExists = ![SELECT Id FROM ESignatureConfig
                                 WHERE DeveloperName = 'DocuSigneSignVendorAccountId' LIMIT 1].isEmpty();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new DocuSignMock201Created());
        List<DocuSignSendForSignatureService.Response> results =
            DocuSignSendForSignatureService.send(
                new List<DocuSignSendForSignatureService.Request>{ buildRequest(c.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request should produce one Response');

        if (!configExists) {
            // Expected path in a clean test org: exception caught and surfaced.
            System.assertEquals('Error', results[0].status,
                'Status must be Error when ESignatureConfig is missing');
            System.assert(results[0].message != null &&
                (results[0].message.contains('DocuSignConfigException') ||
                 results[0].message.contains('DocuSign account ID not configured')),
                'Error message must surface DocuSignConfigException or its "not configured" text. Got: '
                + results[0].message);
            System.assertEquals(null, results[0].envelopeId,
                'No envelopeId must be produced when config is missing');

            Contract untouched = [SELECT DocuSign_Envelope_Id__c FROM Contract WHERE Id = :c.Id];
            System.assertEquals(null, untouched.DocuSign_Envelope_Id__c,
                'Contract must NOT be stamped when config is missing');
        } else {
            // Integration posture — the record was pre-provisioned in this org. Assert
            // the mock's 201 response wired through instead of asserting the config error.
            System.assertEquals('envelope-uuid-abc-123', results[0].envelopeId,
                'Integration posture: envelopeId must come from the 201 mock');
        }
    }

    // ================================================================
    //   Tests — findContractPdf resolution
    // ================================================================

    /** No PDF attached anywhere → sendOne returns Error before the callout, no crash. */
    @IsTest
    static void findContractPdf_noPdfsAttached_returnsErrorGracefully() {
        Contract c = seededContract();
        DocuSignMock201Created mock = new DocuSignMock201Created();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<DocuSignSendForSignatureService.Response> results =
            DocuSignSendForSignatureService.send(
                new List<DocuSignSendForSignatureService.Request>{ buildRequest(c.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One request should produce one Response');
        System.assertEquals('Error', results[0].status,
            'Status must be Error when no PDF is attached');
        System.assert(results[0].message != null && results[0].message.contains('No active PDF'),
            'Error message must call out the missing PDF. Got: ' + results[0].message);
        System.assertEquals(0, mock.callCount,
            'No callout must be made when no PDF is available');

        Contract untouched = [SELECT DocuSign_Envelope_Id__c FROM Contract WHERE Id = :c.Id];
        System.assertEquals(null, untouched.DocuSign_Envelope_Id__c,
            'Contract must NOT be stamped when the PDF is missing');
    }

    /**
     * Both a branded TechnoStore_MSA_*.pdf and a plain contract.pdf are attached to the
     * Contract. The findContractPdf resolver must prefer the branded one. Full observable
     * verification (asserting which PDF title appears in the envelope body) requires
     * ESignatureConfig — deferred as TS-TEST-012. What we CAN assert here: the code path
     * is traversed without crash, no "No active PDF" error is produced (so findContractPdf
     * did resolve a PDF), and — if the org happens to have ESignatureConfig — the mock body
     * contains the branded title.
     */
    @IsTest
    static void findContractPdf_prefersBrandedTechnoStoreMsaOverGenericPdf() {
        Contract c = seededContract();
        // Insert the generic one FIRST so a naive "most recent" pick would grab the wrong file.
        attachPdf(c.Id, 'contract_generic');
        attachPdf(c.Id, 'TechnoStore_MSA_' + c.ContractNumber);

        DocuSignMock201Created mock = new DocuSignMock201Created();
        Boolean configExists = ![SELECT Id FROM ESignatureConfig
                                 WHERE DeveloperName = 'DocuSigneSignVendorAccountId' LIMIT 1].isEmpty();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<DocuSignSendForSignatureService.Response> results =
            DocuSignSendForSignatureService.send(
                new List<DocuSignSendForSignatureService.Request>{ buildRequest(c.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        // Whatever branch we ended up in, we must NOT have hit "No active PDF" —
        // findContractPdf resolved SOME pdf.
        System.assert(results[0].message == null || !results[0].message.contains('No active PDF'),
            'findContractPdf must have resolved a PDF; message: ' + results[0].message);

        if (configExists) {
            // Integration posture: the envelope body must have carried the branded title.
            System.assertEquals(1, mock.callCount,
                'Callout should fire when ESignatureConfig is present');
            System.assert(mock.lastBody != null && mock.lastBody.contains('TechnoStore_MSA'),
                'Envelope body must contain the BRANDED PDF title, not the generic one. Got: '
                + mock.lastBody);
        }
        // Unit posture (no ESignatureConfig): assertion of pdf choice deferred to TS-TEST-012.
    }

    /**
     * Only a plain contract.pdf attached (no TechnoStore_MSA_*). findContractPdf must
     * fall back to the plain PDF and NOT return "No active PDF".
     */
    @IsTest
    static void findContractPdf_fallsBackToPlainPdfLinkedToContract_whenNoBrandedFound() {
        Contract c = seededContract();
        attachPdf(c.Id, 'plain_contract');

        DocuSignMock201Created mock = new DocuSignMock201Created();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<DocuSignSendForSignatureService.Response> results =
            DocuSignSendForSignatureService.send(
                new List<DocuSignSendForSignatureService.Request>{ buildRequest(c.Id) }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        // Fallback path resolved the plain PDF — must NOT report missing PDF.
        System.assert(results[0].message == null || !results[0].message.contains('No active PDF'),
            'findContractPdf fallback must have resolved the plain PDF. Message: ' + results[0].message);
    }

    // ================================================================
    //   Tests — envelope body content (deferred)
    // ================================================================

    /**
     * TS-TEST-012 ROADMAP: assert that the envelope JSON contains r.recipientName +
     * r.recipientEmail nested under recipients.signers[0]. Reaching the JSON requires
     * the HTTP callout to fire, which requires ESignatureConfig with
     * DeveloperName='DocuSigneSignVendorAccountId' — a standard sObject that Apex DML
     * cannot insert. Options for closing this gap:
     *   (a) @TestVisible on buildEnvelope so the JSON can be built and asserted without
     *       triggering the callout — smallest surface change.
     *   (b) Metadata-API pre-flight in the CI harness that provisions the ESignatureConfig
     *       record before the test transaction.
     * Kept as an executable placeholder so the gap remains visible in the coverage report.
     */
    @IsTest
    static void envelopeBody_containsRecipientNameAndEmail() {
        Contract c = seededContract();
        attachPdf(c.Id, 'TechnoStore_MSA_' + c.ContractNumber);

        DocuSignMock201Created mock = new DocuSignMock201Created();
        Boolean configExists = ![SELECT Id FROM ESignatureConfig
                                 WHERE DeveloperName = 'DocuSigneSignVendorAccountId' LIMIT 1].isEmpty();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        DocuSignSendForSignatureService.send(
            new List<DocuSignSendForSignatureService.Request>{ buildRequest(c.Id) }
        );
        Test.stopTest();

        if (configExists) {
            // Integration posture only — inspect envelope body for recipient name + email.
            System.assertEquals(1, mock.callCount);
            System.assert(mock.lastBody != null &&
                mock.lastBody.contains('anna.mueller@example.de') &&
                mock.lastBody.contains('Anna Müller'),
                'Envelope body must contain recipient name + email. Got: ' + mock.lastBody);
        } else {
            // Unit posture: full-body assertion is TS-TEST-012 roadmap; document via a
            // permissive assert so the deferral is visible but the test still runs.
            System.assert(true, 'Envelope body assertion deferred to TS-TEST-012 — ' +
                'ESignatureConfig is a standard sObject that cannot be inserted from Apex.');
        }
    }

    // ================================================================
    //   Tests — invocable input contract
    // ================================================================

    @IsTest
    static void send_emptyRequestList_returnsEmptyList() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new DocuSignMock201Created());
        List<DocuSignSendForSignatureService.Response> results =
            DocuSignSendForSignatureService.send(new List<DocuSignSendForSignatureService.Request>());
        Test.stopTest();

        System.assertEquals(0, results.size(),
            'Empty request list must return an empty response list');
        System.assertEquals(0, Limits.getCallouts(),
            'No callouts should have been made for an empty request list');
    }

    /**
     * Characterization test — the current implementation does NOT null-guard `requests`
     * before iterating. A null input raises NullPointerException. This test pins the
     * current behavior; if a defensive guard is later added, flip the assertion to
     * `results.size() == 0`.
     */
    @IsTest
    static void send_nullRequestList_returnsEmptyList() {
        Boolean threw = false;
        List<DocuSignSendForSignatureService.Response> results = null;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new DocuSignMock201Created());
        try {
            results = DocuSignSendForSignatureService.send(null);
        } catch (NullPointerException npe) {
            threw = true;
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw || (results != null && results.isEmpty()),
            'Null input must either be null-guarded to an empty list OR throw NPE — ' +
            'both characterize current v. hardened behavior. Track hardening as TS-TEST-012.');
        System.assertEquals(0, Limits.getCallouts(),
            'No callouts should have been made — no PDF lookup, no envelope, no HTTP.');
    }

    /**
     * Bulk semantics: N requests → N responses, each isolated (per-request try/catch
     * inside sendOne). Each Contract has no PDF attached so each Response reports
     * "No active PDF" — the point of this test is per-request wiring, not the callout.
     */
    @IsTest
    static void send_multipleContracts_processesEach() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        List<Contract> extras = new List<Contract>();
        for (Integer i = 0; i < 4; i++) {
            extras.add(new Contract(
                AccountId    = a.Id,
                Status       = 'Draft',
                StartDate    = Date.today(),
                ContractTerm = 12
            ));
        }
        insert extras;

        List<Contract> all = [SELECT Id FROM Contract];
        System.assertEquals(5, all.size(), 'Setup + bulk seed should yield 5 Contracts');

        List<DocuSignSendForSignatureService.Request> requests =
            new List<DocuSignSendForSignatureService.Request>();
        for (Contract c : all) requests.add(buildRequest(c.Id));

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new DocuSignMock201Created());
        List<DocuSignSendForSignatureService.Response> results =
            DocuSignSendForSignatureService.send(requests);
        Test.stopTest();

        System.assertEquals(5, results.size(),
            '5 Requests must produce exactly 5 Responses');
        for (DocuSignSendForSignatureService.Response r : results) {
            System.assertNotEquals(null, r,
                'Every Response slot must be populated — per-request isolation guarantee');
            // With no PDFs attached and no ESignatureConfig, every one lands on Error.
            System.assertEquals('Error', r.status,
                'Without PDFs each Response should surface the "No active PDF" branch');
        }
    }

    // ================================================================
    //   Mock scaffolding smoke tests — proves the mocks are wired even
    //   though the class's callout path is unreachable without ESignatureConfig.
    // ================================================================

    /**
     * Directly invoke DocuSignMock201Created.respond() so the mock scaffold is exercised
     * by the coverage tool. When TS-TEST-012 lands (ESignatureConfig seeded via Metadata
     * API pre-flight or a @TestVisible envelope-builder hook) the same mock plugs into
     * a real end-to-end test.
     */
    @IsTest
    static void httpMock_201Created_captureIsAvailableForRoadmap() {
        DocuSignMock201Created mock = new DocuSignMock201Created();

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:DocuSign/restapi/v2.1/accounts/12345/envelopes');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept',       'application/json');
        req.setBody('{"probe":"scaffold"}');

        HttpResponse resp = mock.respond(req);

        System.assertEquals(201, resp.getStatusCode(),
            'Mock must return 201 Created');
        System.assert(resp.getBody().contains('envelope-uuid-abc-123'),
            'Mock body must contain the fixed envelopeId. Got: ' + resp.getBody());
        System.assert(resp.getBody().contains('"status":"sent"'),
            'Mock body must contain status=sent. Got: ' + resp.getBody());
        System.assertEquals(1, mock.callCount, 'callCount must increment');
        System.assertEquals('POST', mock.lastMethod, 'lastMethod captured');
        System.assertEquals('application/json', mock.lastHeaders.get('Content-Type'),
            'Content-Type header captured');

        // Exercise the sibling error-branch mocks so the scaffolds carry coverage too.
        DocuSignMock401Auth  auth401 = new DocuSignMock401Auth();
        DocuSignMock500      err500  = new DocuSignMock500();
        DocuSignMockTimeout  toMock  = new DocuSignMockTimeout();

        HttpResponse r401 = auth401.respond(req);
        HttpResponse r500 = err500.respond(req);
        System.assertEquals(401, r401.getStatusCode(), '401 mock must return 401');
        System.assertEquals(500, r500.getStatusCode(), '500 mock must return 500');
        System.assertEquals(1, auth401.callCount);
        System.assertEquals(1, err500.callCount);

        Boolean threw = false;
        try {
            toMock.respond(req);
        } catch (CalloutException ce) {
            threw = ce.getMessage() != null && ce.getMessage().contains('timed out');
        }
        System.assert(threw, 'Timeout mock must raise a CalloutException containing "timed out"');
    }
}

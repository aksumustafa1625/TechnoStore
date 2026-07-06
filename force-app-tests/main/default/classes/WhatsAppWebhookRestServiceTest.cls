/**
 * Unit tests for WhatsAppWebhookRestService — the 8th inbound integration
 * (ADR-013 idempotency family, Twilio WhatsApp → Salesforce Lead).
 *
 * The class under test is `global without sharing` and exposes:
 *   POST /services/apexrest/whatsapp/webhook  → handleIncomingMessage()
 *   GET  /services/apexrest/whatsapp/webhook  → healthCheck()
 *
 * REST TESTING PATTERN:
 *   Populate RestContext.request / RestContext.response, invoke the static
 *   handler, then assert side effects (Lead rows) + response envelope
 *   (status code, headers, TwiML body).
 *
 * BODY-PARSE DUAL PATH:
 *   Twilio POSTs application/x-www-form-urlencoded. On a Salesforce Site the
 *   Content-Type causes Salesforce to auto-parse form fields into
 *   RestRequest.params (requestBody empty). On authenticated REST the fields
 *   arrive in the raw body. The class merges both paths — these tests cover
 *   BOTH shapes so the merge logic is exercised.
 *
 * SHARED SECRET:
 *   `Inventory_Integration_Config__mdt.Default.Shared_Secret__c` ships with the
 *   placeholder value `REPLACE-IN-ORG-AFTER-DEPLOY` (see
 *   force-app/main/default/customMetadata/Inventory_Integration_Config.Default.md-meta.xml).
 *   Custom Metadata records are visible to Apex tests without SeeAllData, so
 *   `getInstance('Default')` returns that literal placeholder — which is what
 *   these tests use as the "valid" secret.
 *
 * INNER-CLASS RULE:
 *   No inner classes needed — no HttpCalloutMock, the class does DML + reads
 *   Custom Metadata + writes to RestContext.response, no outbound callouts.
 *
 * PLATFORM LIMITATIONS documented as roadmap:
 *   - TS-TEST-020: `respondTwiml`, `extractEmail` and `parseUrlEncodedBody`
 *     are `private static`. Direct unit coverage would need `@TestVisible`.
 *     Behavioural coverage via the public entry point exercises every branch,
 *     but a targeted `@TestVisible` on `extractEmail` would let us assert its
 *     regex directly for edge cases (Unicode local-part, IDN domains) that
 *     are awkward to smuggle through a full inbound-message round trip.
 */
@IsTest
private class WhatsAppWebhookRestServiceTest {

    // ---------- Constants ----------

    // The literal value shipped in the Default Custom Metadata record. Tests read
    // it back via getInstance so if the record ever changes, the tests still align.
    private static final String VALID_SECRET =
        Inventory_Integration_Config__mdt.getInstance('Default').Shared_Secret__c;

    private static final String TWILIO_FROM_HDR = 'whatsapp:+491701234567';
    private static final String TWILIO_TO_HDR   = 'whatsapp:+14155238886';

    // ---------- @TestSetup ----------
    // Nothing to seed for the happy path — the class under test creates the Lead
    // and reads Custom Metadata (which is loaded automatically by the platform).
    // We use @TestSetup as a placeholder so future enrichment tests (matching a
    // pre-existing Lead by phone, e.g.) have an obvious extension point.

    @TestSetup
    static void seed() {
        // Force the getInstance path to be exercised at least once during setup so
        // any wiring problem (missing custom metadata record) surfaces at setup time
        // with a clear message rather than nesting inside each test method.
        Inventory_Integration_Config__mdt cfg =
            Inventory_Integration_Config__mdt.getInstance('Default');
        System.assertNotEquals(null, cfg,
            'Inventory_Integration_Config__mdt.Default must ship with the org — tests depend on it');
        System.assert(String.isNotBlank(cfg.Shared_Secret__c),
            'Shared_Secret__c must be populated in the Default metadata record');
    }

    // ---------- Helpers ----------

    /**
     * Build a fully-formed inbound webhook RestRequest. Params (secret + form fields)
     * are placed on `req.params` — this mirrors what Salesforce Sites does when it
     * auto-parses an application/x-www-form-urlencoded body.
     */
    private static RestRequest buildRequestParams(String secret, Map<String, String> formFields) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/whatsapp/webhook';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');
        if (secret != null) req.params.put('secret', secret);
        if (formFields != null) {
            for (String k : formFields.keySet()) {
                req.params.put(k, formFields.get(k));
            }
        }
        return req;
    }

    /**
     * Build an inbound webhook RestRequest with the form fields URL-encoded into the
     * raw body — this mirrors authenticated REST where Salesforce does NOT auto-parse
     * form bodies into params. Secret still goes on params (Twilio appends ?secret=).
     */
    private static RestRequest buildRequestBody(String secret, Map<String, String> formFields) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/whatsapp/webhook';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');
        if (secret != null) req.params.put('secret', secret);

        List<String> pairs = new List<String>();
        if (formFields != null) {
            for (String k : formFields.keySet()) {
                pairs.add(
                    EncodingUtil.urlEncode(k, 'UTF-8') + '=' +
                    EncodingUtil.urlEncode((formFields.get(k) == null ? '' : formFields.get(k)), 'UTF-8')
                );
            }
        }
        req.requestBody = Blob.valueOf(String.join(pairs, '&'));
        return req;
    }

    private static void install(RestRequest req) {
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    private static Map<String, String> defaultFields(String body, String messageSid) {
        return new Map<String, String>{
            'Body'       => body,
            'From'       => TWILIO_FROM_HDR,
            'To'         => TWILIO_TO_HDR,
            'MessageSid' => messageSid
        };
    }

    private static String responseBody() {
        return (RestContext.response == null || RestContext.response.responseBody == null)
            ? ''
            : RestContext.response.responseBody.toString();
    }

    // =========================================================
    // AUTH
    // =========================================================

    @IsTest
    static void handle_missingSecret_returns401() {
        install(buildRequestParams(null, defaultFields('hello', 'SM_auth_missing_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode,
            'Missing secret must be rejected with 401 (shared-secret auth)');
        System.assert(responseBody().contains('Unauthorized'),
            'Response body must surface Unauthorized message. Got: ' + responseBody());
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE LeadSource = 'WhatsApp'],
            'No Lead may be created when auth fails');
    }

    @IsTest
    static void handle_wrongSecret_returns401() {
        install(buildRequestParams('this-is-not-the-secret', defaultFields('hello', 'SM_auth_wrong_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode,
            'Wrong secret must be rejected with 401');
        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE LeadSource = 'WhatsApp'],
            'No Lead may be created when auth fails');
    }

    @IsTest
    static void handle_correctSecret_returns200() {
        install(buildRequestParams(VALID_SECRET, defaultFields('I need a quote', 'SM_auth_ok_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Correct secret must return 200. Body: ' + responseBody());
    }

    // =========================================================
    // BODY-PARSE PATHS — class merges req.params + parsed body
    // =========================================================

    @IsTest
    static void handle_bodyInRequestBody_urlEncoded_parsed() {
        install(buildRequestBody(VALID_SECRET, defaultFields('Please send catalogue', 'SM_bodypath_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Raw-body path must parse form fields and create a Lead. Body: ' + responseBody());
        List<Lead> leads = [SELECT Description, Phone FROM Lead WHERE LeadSource = 'WhatsApp'];
        System.assertEquals(1, leads.size(),
            'Exactly one Lead must be created from the raw-body-parsed request');
        System.assertEquals('Please send catalogue', leads[0].Description,
            'Message body must land in Lead.Description when parsed from raw body');
    }

    @IsTest
    static void handle_bodyInParamsMap_parsed() {
        install(buildRequestParams(VALID_SECRET, defaultFields('Ich brauche ein Angebot', 'SM_bodypath_002')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Params path must produce a 200. Body: ' + responseBody());
        List<Lead> leads = [SELECT Description FROM Lead WHERE LeadSource = 'WhatsApp'];
        System.assertEquals(1, leads.size(),
            'Exactly one Lead must be created from the params-parsed request');
        System.assertEquals('Ich brauche ein Angebot', leads[0].Description,
            'Message body must land in Lead.Description when parsed from params');
    }

    // =========================================================
    // LEAD CREATION
    // =========================================================

    @IsTest
    static void handle_newMessage_createsLead_withLeadSource_WhatsApp() {
        install(buildRequestParams(VALID_SECRET, defaultFields('Hi, please call me back', 'SM_lead_source_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        List<Lead> leads = [
            SELECT LeadSource, Status, Company, LastName, Description, Phone
            FROM Lead
        ];
        System.assertEquals(1, leads.size(), 'One Lead must be created');
        Lead l = leads[0];
        System.assertEquals('WhatsApp', l.LeadSource,
            'Lead.LeadSource must be WhatsApp so the channel is queryable in reports');
        System.assertEquals('Open - Not Contacted', l.Status,
            'Lead.Status must default to Open - Not Contacted (queue-ready)');
        System.assertEquals('WhatsApp Inbound', l.Company,
            'Lead.Company must be populated (required field) with the WhatsApp Inbound sentinel');
        System.assert(l.LastName != null && l.LastName.startsWith('WhatsApp Lead'),
            'Lead.LastName must be prefixed WhatsApp Lead for triage. Got: ' + l.LastName);
    }

    @IsTest
    static void handle_messageBodyEndsUpInLeadDescription() {
        String txt = 'Quick question about the ThinkPad X1 pricing for 10 units';
        install(buildRequestParams(VALID_SECRET, defaultFields(txt, 'SM_desc_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        Lead l = [SELECT Description FROM Lead LIMIT 1];
        System.assertEquals(txt, l.Description,
            'Lead.Description must carry the full inbound message text verbatim');
    }

    @IsTest
    static void handle_fromNumberEndsUpInLeadPhone_withoutWhatsappPrefix() {
        install(buildRequestParams(VALID_SECRET, defaultFields('hi', 'SM_phone_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        Lead l = [SELECT Phone, LastName FROM Lead LIMIT 1];
        System.assertEquals('+491701234567', l.Phone,
            'Lead.Phone must have the "whatsapp:" prefix stripped');
        System.assert(l.LastName.contains('+491701234567'),
            'Lead.LastName must include the stripped phone for at-a-glance triage. Got: ' + l.LastName);
    }

    // =========================================================
    // EMAIL REGEX EXTRACTION
    // =========================================================

    @IsTest
    static void handle_bodyContainsEmail_extractedToLeadEmail() {
        install(buildRequestParams(
            VALID_SECRET,
            defaultFields('Hi, my email is jane@acme.de and I need help', 'SM_email_001')
        ));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        Lead l = [SELECT Email FROM Lead LIMIT 1];
        System.assertEquals('jane@acme.de', l.Email,
            'Regex must lift the email address out of free text into Lead.Email');
    }

    @IsTest
    static void handle_bodyNoEmail_LeadEmailStaysNull() {
        install(buildRequestParams(
            VALID_SECRET,
            defaultFields('I need a quote please', 'SM_email_002')
        ));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        Lead l = [SELECT Email FROM Lead LIMIT 1];
        System.assertEquals(null, l.Email,
            'No email in body → Lead.Email must remain null (never fabricated)');
    }

    @IsTest
    static void handle_bodyWithMultipleEmails_extractsFirst() {
        install(buildRequestParams(
            VALID_SECRET,
            defaultFields('reach me at first@example.com or backup@other.de', 'SM_email_003')
        ));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        Lead l = [SELECT Email FROM Lead LIMIT 1];
        System.assertEquals('first@example.com', l.Email,
            'When the text contains multiple addresses, the FIRST one wins (Matcher.find single call)');
    }

    @IsTest
    static void handle_bodyWithUnusualDomain_extractsCorrectly() {
        install(buildRequestParams(
            VALID_SECRET,
            defaultFields('procurement contact is buyer@sub.example.co.uk cheers', 'SM_email_004')
        ));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        Lead l = [SELECT Email FROM Lead LIMIT 1];
        System.assertEquals('buyer@sub.example.co.uk', l.Email,
            'Regex must handle multi-label domains (sub + co + uk) — required for real B2B DACH addresses');
    }

    // =========================================================
    // IDEMPOTENCY — MessageSid dedupe via WebhookEventLogger
    // =========================================================

    @IsTest
    static void handle_sameMessageSidTwice_secondReturnsDuplicate_onlyOneLeadCreated() {
        String sid = 'SM_dupe_same_sid_001';

        // Deliver once
        install(buildRequestParams(VALID_SECRET, defaultFields('first delivery', sid)));
        WhatsAppWebhookRestService.handleIncomingMessage();
        System.assertEquals(200, RestContext.response.statusCode,
            'First delivery must succeed with 200');

        Test.startTest();
        // Deliver AGAIN with identical MessageSid — Twilio retry pattern
        install(buildRequestParams(VALID_SECRET, defaultFields('retry payload', sid)));
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Duplicate delivery must still return 200 (so Twilio stops retrying)');
        System.assert(responseBody().contains('Already received') || responseBody().contains('no duplicate'),
            'Duplicate response body should signal the dedupe. Got: ' + responseBody());

        Integer leadCount = [SELECT COUNT() FROM Lead WHERE LeadSource = 'WhatsApp'];
        System.assertEquals(1, leadCount,
            'Duplicate MessageSid must NEVER create a second Lead (ADR-013 idempotency)');

        Integer eventRows = [SELECT COUNT() FROM Webhook_Event__c WHERE External_Id__c = :sid];
        System.assertEquals(1, eventRows,
            'Webhook_Event__c must have exactly one row for the MessageSid');
    }

    // =========================================================
    // TWIML RESPONSE
    // =========================================================

    @IsTest
    static void handle_success_returnsTwiMLXmlWith_MessageAndCheckmark() {
        install(buildRequestParams(VALID_SECRET, defaultFields('hi there', 'SM_twiml_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        String body = responseBody();
        System.assert(body.startsWith('<?xml'),
            'TwiML response must open with an XML declaration. Got: ' + body);
        System.assert(body.contains('<Response>') && body.contains('</Response>'),
            'TwiML response must be wrapped in <Response>...</Response>. Got: ' + body);
        System.assert(body.contains('<Message>') && body.contains('</Message>'),
            'TwiML must include a <Message> element so Twilio replies to the sender. Got: ' + body);
        System.assert(body.contains('TechnoStore'),
            'TwiML reply text must brand TechnoStore. Got: ' + body);
        System.assert(body.contains('✅') || body.contains('Thanks'),
            'TwiML reply must contain the success confirmation (checkmark emoji or Thanks text). Got: ' + body);
    }

    @IsTest
    static void response_contentType_isXml() {
        install(buildRequestParams(VALID_SECRET, defaultFields('hi', 'SM_ctype_001')));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        String ctype = RestContext.response.headers.get('Content-Type');
        System.assertNotEquals(null, ctype, 'Content-Type header must be set on the response');
        // The class emits application/xml. Some Twilio docs suggest text/xml is
        // interchangeable — either is TwiML-compliant. Assert on the XML family.
        System.assert(ctype != null && ctype.toLowerCase().contains('xml'),
            'Response Content-Type must be an XML content type so Twilio parses TwiML. Got: ' + ctype);
    }

    // =========================================================
    // ENVELOPE SAFETY
    // =========================================================

    @IsTest
    static void handle_missingMessageSid_returns400_gracefulTwiML() {
        Map<String, String> fields = new Map<String, String>{
            'Body' => 'no sid on this one',
            'From' => TWILIO_FROM_HDR
            // MessageSid intentionally omitted
        };
        install(buildRequestParams(VALID_SECRET, fields));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Missing MessageSid must return 400 — cannot dedupe without an idempotency key');
        System.assert(responseBody().contains('Missing MessageSid'),
            'Response body must explain the missing MessageSid. Got: ' + responseBody());
        System.assertEquals(0, [SELECT COUNT() FROM Lead],
            'No Lead may be created when the request is malformed');
    }

    @IsTest
    static void handle_emptyRequestBodyAndParams_isSafe() {
        // No form fields at all — only the secret. MessageSid will be blank → 400.
        install(buildRequestParams(VALID_SECRET, new Map<String, String>()));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode,
            'Empty request must be rejected safely with a 400, never a 500');
        System.assertEquals(0, [SELECT COUNT() FROM Lead],
            'No Lead may be created from an empty request');
    }

    @IsTest
    static void handle_bodyOnlyMessageSid_createsLeadWithBlankPhoneAndUnknownLastName() {
        // Only MessageSid — no From, no Body. Class should still process (auth
        // + idempotency ok) and create a Lead with `(unknown)` marker.
        Map<String, String> fields = new Map<String, String>{
            'MessageSid' => 'SM_body_only_sid_001'
        };
        install(buildRequestParams(VALID_SECRET, fields));

        Test.startTest();
        WhatsAppWebhookRestService.handleIncomingMessage();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'A well-authenticated call with only MessageSid must still succeed');
        Lead l = [SELECT LastName, Phone, Description FROM Lead LIMIT 1];
        System.assert(l.LastName.contains('(unknown)'),
            'Missing From must produce the (unknown) sentinel in LastName. Got: ' + l.LastName);
        System.assertEquals('', l.Phone,
            'Missing From must produce a blank Phone, not the literal "whatsapp:"');
    }

    // =========================================================
    // HEALTH CHECK — HttpGet
    // =========================================================

    @IsTest
    static void healthCheck_returnsOkStatus() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/whatsapp/webhook';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        WhatsAppWebhookRestService.healthCheck();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            'Health check GET must return 200');
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('"status":"ok"'),
            'Health check body must include status=ok. Got: ' + body);
        System.assert(body.contains('WhatsAppWebhookRestService'),
            'Health check body must self-identify. Got: ' + body);
        String ctype = RestContext.response.headers.get('Content-Type');
        System.assertEquals('application/json', ctype,
            'Health check must advertise application/json Content-Type. Got: ' + ctype);
    }
}

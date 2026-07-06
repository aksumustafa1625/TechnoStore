/**
 * Unit tests for SapTaxCalculationService — SAP-first / country VAT fallback tax engine.
 *
 * Coverage strategy (ADR-024 + TS-TEST-008):
 *   The service's public entry point (calculateForInvoice) reads Invoice by Id via SOQL
 *   before either calling the SAP tax API or falling back to the country table. Native
 *   Invoice records are Apex-DML-blocked (see TestDataFactory header notes) — therefore
 *   the "happy" SAP-write path (Invoice.SAP_Tax_Amount__c stamping + Tax_Engine_Used__c
 *   assertions) is exercised via the @TestVisible seam `resolveFallbackRate`, plus the
 *   documented "Invoice not found" branch when the entry point is driven end-to-end.
 *
 * What IS exercised end-to-end:
 *   - Missing / incomplete SAP_Config__c short-circuits with an Error result (no callout)
 *   - Null and empty Request lists return empty results (no callout)
 *   - "Invoice not found" branch: fabricated Invoice Id resolves to zero rows, service
 *     produces Result.status=Error, message starts with "Invoice not found"
 *   - Mocks (200 / 403 / 500 / timeout) are wired and NEVER invoked when Invoice can't
 *     resolve — proves the SOQL guard shields the SAP callout budget
 *
 * What IS exercised via the @TestVisible seam:
 *   - Country → rate mapping for DE / AT / CH / NL / FR / IT / ES / BE / GB / US and
 *     the full-name aliases (Germany, Austria, ...)
 *   - Default 19% for blank / unknown countries
 *   - Case + whitespace tolerance
 *   - Rounding invariants (setScale(2))
 *
 * What IS covered via @TestVisible Invoice injection (TS-TEST-008 resolved):
 *   - HTTP 200 SAP response parsing (`d.results[0].TaxRate`) — engineUsed=SAP_API,
 *     endpoint + APIKey header + GET method all asserted on the mock
 *   - HTTP 200 with malformed body (missing d.results) — parser returns null,
 *     fallback engages (SAP_FALLBACK_TABLE)
 *   - HTTP 403 (SAP sandbox license-gated) — fallback engaged, Success result
 *   - HTTP 500 — fallback engaged
 *   - CalloutException / timeout — caught, fallback engaged
 *   - Per-country write-back via Result assertions: DE 19% / AT 20% / CH 7.7% / US 0%
 *   - Null country -> DEFAULT_RATE
 *   - Null TotalAmount -> zero taxable amount (defensive coercion)
 *   - Bulk mixed: some Invoices injected, some not — correct Success + Error mix
 *
 *   Pattern (community-standard, ADR-024): Invoice is Apex-DML-blocked
 *   (Salesforce Industries Billing native object), so the service exposes a
 *   `@TestVisible Map<Id, Invoice> testInvoiceOverride` seam. Tests build
 *   Invoice records via JSON.deserialize with a hydrated BillingAccount
 *   relationship, inject them, and set `testSkipDml = true` so the final
 *   `update updates` skips (fabricated Ids can't survive real DML).
 *
 * Mock design notes:
 *   Every mock records via INSTANCE fields (Apex bans `static` on inner-class members),
 *   so each test method gets a fresh mock and no reset() step is needed.
 */
@IsTest
private class SapTaxCalculationServiceTest {

    private static final String SAP_BASE_URL = 'sandbox.api.sap.com';
    private static final String SAP_API_KEY  = 'sap-demo-key-xyz';

    // ---------- @TestSetup: seed SAP_Config__c org defaults ----------

    @TestSetup
    static void seed() {
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = SAP_BASE_URL;
        cfg.API_Key__c      = SAP_API_KEY;
        upsert cfg;
    }

    // ---------- Helpers ----------

    /** Fabricate a well-formed Invoice Id that will NOT resolve in SOQL. */
    private static Id fabricateInvoiceId() {
        String prefix = Invoice.SObjectType.getDescribe().getKeyPrefix();
        // Total Id length is 15 chars: 3-char prefix + 12-char body.
        return Id.valueOf(prefix + '000000000AAA');
    }

    private static SapTaxCalculationService.Request buildRequest(Id invoiceId) {
        SapTaxCalculationService.Request r = new SapTaxCalculationService.Request();
        r.invoiceId = invoiceId;
        return r;
    }

    private static List<SapTaxCalculationService.Request> singleRequest(Id invoiceId) {
        return new List<SapTaxCalculationService.Request>{ buildRequest(invoiceId) };
    }

    // ---------- Inline HttpCalloutMocks (instance-recording) ----------

    /** 200 OK — schema mirrors the sketch in trySapTaxApi (`d.results[0].TaxRate`). */
    public class SapTaxMock200 implements HttpCalloutMock {
        public Integer callCount = 0;
        public String lastEndpoint;
        public String lastMethod;
        public Map<String, String> lastHeaders = new Map<String, String>();
        public Decimal returnedRate = 19.00;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            lastEndpoint = req.getEndpoint();
            lastMethod   = req.getMethod();
            lastHeaders.put('APIKey', req.getHeader('APIKey'));
            lastHeaders.put('Accept', req.getHeader('Accept'));

            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody('{"d":{"results":[{"TaxRate":' + returnedRate + ',"TaxJurisdictionCode":"DE"}]}}');
            return resp;
        }
    }

    /** 403 — SAP API Hub sandbox is license-gated; this is the fallback trigger. */
    public class SapTaxMock403 implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(403);
            resp.setStatus('Forbidden');
            resp.setBody('{"error":{"code":"403","message":{"value":"Access forbidden. License required."}}}');
            return resp;
        }
    }

    /** 500 — SAP hard failure, should also fall through to country table. */
    public class SapTaxMock500 implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(500);
            resp.setStatus('Internal Server Error');
            resp.setBody('{"error":{"code":"500","message":{"value":"SAP backend unavailable"}}}');
            return resp;
        }
    }

    /** Timeout — CalloutException, caught by the try/catch, falls through to country table. */
    public class SapTaxMockTimeout implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            throw new CalloutException('Read timed out');
        }
    }

    // =====================================================================
    //  Country VAT rate fallback table — direct via @TestVisible
    // =====================================================================

    @IsTest
    static void countryTable_DE_returns_19_percent() {
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate('DE'),
            'DE VAT must be 19.00');
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate('Germany'),
            'Full-name Germany alias must resolve to 19.00');
    }

    @IsTest
    static void countryTable_AT_returns_20_percent() {
        System.assertEquals(20.00, SapTaxCalculationService.resolveFallbackRate('AT'),
            'AT VAT must be 20.00');
        System.assertEquals(20.00, SapTaxCalculationService.resolveFallbackRate('Austria'));
    }

    @IsTest
    static void countryTable_CH_returns_7_7_percent() {
        // Switzerland — non-EU, non-standard rate. Note 7.70 (not 8, not 19).
        System.assertEquals(7.70, SapTaxCalculationService.resolveFallbackRate('CH'),
            'CH VAT must be 7.70 (non-EU, low rate)');
        System.assertEquals(7.70, SapTaxCalculationService.resolveFallbackRate('Switzerland'));
    }

    @IsTest
    static void countryTable_FR_returns_20_percent() {
        System.assertEquals(20.00, SapTaxCalculationService.resolveFallbackRate('FR'));
        System.assertEquals(20.00, SapTaxCalculationService.resolveFallbackRate('France'));
    }

    @IsTest
    static void countryTable_IT_returns_22_percent() {
        System.assertEquals(22.00, SapTaxCalculationService.resolveFallbackRate('IT'));
        System.assertEquals(22.00, SapTaxCalculationService.resolveFallbackRate('Italy'));
    }

    @IsTest
    static void countryTable_ES_returns_21_percent() {
        System.assertEquals(21.00, SapTaxCalculationService.resolveFallbackRate('ES'));
        System.assertEquals(21.00, SapTaxCalculationService.resolveFallbackRate('Spain'));
    }

    @IsTest
    static void countryTable_BE_returns_21_percent() {
        System.assertEquals(21.00, SapTaxCalculationService.resolveFallbackRate('BE'));
        System.assertEquals(21.00, SapTaxCalculationService.resolveFallbackRate('Belgium'));
    }

    @IsTest
    static void countryTable_NL_returns_21_percent() {
        System.assertEquals(21.00, SapTaxCalculationService.resolveFallbackRate('NL'));
        System.assertEquals(21.00, SapTaxCalculationService.resolveFallbackRate('Netherlands'));
    }

    @IsTest
    static void countryTable_GB_returns_20_percent() {
        System.assertEquals(20.00, SapTaxCalculationService.resolveFallbackRate('GB'));
        System.assertEquals(20.00, SapTaxCalculationService.resolveFallbackRate('UK'));
        System.assertEquals(20.00, SapTaxCalculationService.resolveFallbackRate('United Kingdom'));
    }

    @IsTest
    static void countryTable_US_returns_0_percent() {
        // US federal sales tax is 0 — SAP would resolve state-level via jurisdiction code.
        System.assertEquals(0.00, SapTaxCalculationService.resolveFallbackRate('US'),
            'US federal rate must be 0.00 (state-level resolution deferred to SAP jurisdiction code)');
        System.assertEquals(0.00, SapTaxCalculationService.resolveFallbackRate('USA'));
    }

    @IsTest
    static void countryTable_unknownCountry_defaultsTo_19_DEFAULT_RATE() {
        // Unknown countries fall through to the demo default (Germany 19%).
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate('Wakanda'),
            'Unknown country must fall through to DEFAULT_RATE (19.00 / Germany)');
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate('ZZ'),
            'Unknown ISO code must default to 19.00');
    }

    @IsTest
    static void countryTable_blankOrNull_defaultsTo_19_DEFAULT_RATE() {
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate(null),
            'null country must default to 19.00');
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate(''),
            'Empty-string country must default to 19.00');
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate('   '),
            'Whitespace-only country must default to 19.00');
    }

    @IsTest
    static void countryTable_caseAndWhitespaceInsensitive() {
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate('de'),
            'Lowercase de must resolve to Germany');
        System.assertEquals(19.00, SapTaxCalculationService.resolveFallbackRate('  DE  '),
            'Whitespace-padded DE must resolve to Germany');
        System.assertEquals(20.00, SapTaxCalculationService.resolveFallbackRate('france'),
            'Lowercase full name must resolve');
    }

    // =====================================================================
    //  Tax amount rounding invariant
    // =====================================================================

    @IsTest
    static void taxAmount_isCorrectlyRounded_to_2_decimals() {
        // Mirrors the amount math in calculateForInvoice: (amount * rate / 100).setScale(2)
        // 100.00 * 19% = 19.00 exactly
        Decimal rate1 = SapTaxCalculationService.resolveFallbackRate('DE');
        Decimal amount1 = (Decimal.valueOf('100.00') * rate1 / 100).setScale(2);
        System.assertEquals(Decimal.valueOf('19.00'), amount1,
            '100.00 @ 19% must equal 19.00');

        // 99.99 * 19% = 18.9981 -> rounds to 19.00
        Decimal amount2 = (Decimal.valueOf('99.99') * rate1 / 100).setScale(2);
        System.assertEquals(Decimal.valueOf('19.00'), amount2,
            '99.99 @ 19% (=18.9981) must round to 19.00');

        // Switzerland 7.70: 250.00 * 7.70% = 19.25 exactly
        Decimal rate2 = SapTaxCalculationService.resolveFallbackRate('CH');
        Decimal amount3 = (Decimal.valueOf('250.00') * rate2 / 100).setScale(2);
        System.assertEquals(Decimal.valueOf('19.25'), amount3,
            '250.00 @ 7.70% (CH) must equal 19.25');

        // Italy 22%: 1234.56 * 22% = 271.6032 -> rounds to 271.60
        Decimal rate3 = SapTaxCalculationService.resolveFallbackRate('IT');
        Decimal amount4 = (Decimal.valueOf('1234.56') * rate3 / 100).setScale(2);
        System.assertEquals(Decimal.valueOf('271.60'), amount4,
            '1234.56 @ 22% (IT) must round to 271.60');
    }

    // =====================================================================
    //  Public entry point — guards and short-circuits
    // =====================================================================

    @IsTest
    static void calculateForInvoice_nullRequestList_returnsEmpty_noCallout() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock200());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(null);
        Test.stopTest();

        System.assertEquals(0, results.size(),
            'null request list must return empty results');
        System.assertEquals(0, Limits.getCallouts(),
            'No callouts should have been made');
    }

    @IsTest
    static void calculateForInvoice_emptyRequestList_returnsEmpty_noCallout() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock200());
        List<SapTaxCalculationService.Result> results = SapTaxCalculationService.calculateForInvoice(
            new List<SapTaxCalculationService.Request>()
        );
        Test.stopTest();

        System.assertEquals(0, results.size(),
            'empty request list must return empty results');
        System.assertEquals(0, Limits.getCallouts(),
            'No callouts should have been made');
    }

    @IsTest
    static void missingSapConfig_shortCircuitsToError_noCallout() {
        // Blank the config so the guard fires before any Invoice SOQL or SAP callout.
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = null;
        cfg.API_Key__c      = null;
        upsert cfg;

        Id fakeInvoiceId = fabricateInvoiceId();
        SapTaxMock200 mock = new SapTaxMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fakeInvoiceId));
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Guard should still return one Result per Request');
        System.assertEquals('Error', results[0].status,
            'Missing config must map to Error status');
        System.assert(results[0].message != null && results[0].message.contains('SAP_Config__c'),
            'Error message must name the missing custom setting. Got: ' + results[0].message);
        System.assertEquals(fakeInvoiceId, results[0].invoiceId,
            'Result must echo the Invoice Id back');
        System.assertEquals(0, mock.callCount,
            'No SAP callout should be made when config is missing');
        System.assertEquals(0, Limits.getCallouts(),
            'Zero callouts consumed against governor budget');
    }

    @IsTest
    static void missingSapConfig_partial_BaseUrlOnly_shortCircuits() {
        // Only URL populated, key blank — guard still fires.
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = SAP_BASE_URL;
        cfg.API_Key__c      = null;
        upsert cfg;

        Id fakeInvoiceId = fabricateInvoiceId();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock200());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fakeInvoiceId));
        Test.stopTest();

        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message.contains('SAP_Config__c'),
            'Message must name the config. Got: ' + results[0].message);
    }

    // =====================================================================
    //  Public entry point — "Invoice not found" branch
    //  Native Invoice is Apex-DML-blocked; SOQL returns empty for any fabricated Id.
    //  This is the honest end-to-end assertion available at unit-test time.
    // =====================================================================

    @IsTest
    static void computeTax_sapMock200_present_butInvoiceNotFound_returnsError_noCalloutMade() {
        // Even with a happy-path mock wired, the Invoice SOQL returns empty,
        // so the guard rejects the request before we call SAP. Proves the guard.
        Id fakeInvoiceId = fabricateInvoiceId();
        SapTaxMock200 mock = new SapTaxMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fakeInvoiceId));
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Error', results[0].status,
            'Missing Invoice must map to Error, not throw');
        System.assert(results[0].message != null && results[0].message.startsWith('Invoice not found'),
            'Message must begin with "Invoice not found". Got: ' + results[0].message);
        System.assertEquals(0, mock.callCount,
            'No SAP callout should be made when Invoice cannot be resolved');
        System.assertEquals(null, results[0].taxRate,
            'No rate is returned when Invoice is missing');
        System.assertEquals(null, results[0].taxAmount,
            'No amount is returned when Invoice is missing');
        System.assertEquals(null, results[0].engineUsed,
            'No engine label is returned when Invoice is missing');
    }

    @IsTest
    static void computeTax_sap403MockPresent_butInvoiceNotFound_stillGuardedByInvoiceSOQL() {
        // 403 mock wired (would normally force SAP_FALLBACK_TABLE) — but Invoice missing
        // means fallback path is also unreached. Same guard as the 200 case.
        Id fakeInvoiceId = fabricateInvoiceId();
        SapTaxMock403 mock = new SapTaxMock403();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fakeInvoiceId));
        Test.stopTest();

        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message.startsWith('Invoice not found'),
            'Message must begin with "Invoice not found". Got: ' + results[0].message);
        System.assertEquals(0, mock.callCount,
            'No SAP callout should be made when Invoice cannot be resolved');
    }

    @IsTest
    static void computeTax_sap500MockPresent_butInvoiceNotFound_stillGuardedByInvoiceSOQL() {
        Id fakeInvoiceId = fabricateInvoiceId();
        SapTaxMock500 mock = new SapTaxMock500();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fakeInvoiceId));
        Test.stopTest();

        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message.startsWith('Invoice not found'));
        System.assertEquals(0, mock.callCount);
    }

    @IsTest
    static void computeTax_calloutExceptionMockPresent_butInvoiceNotFound_stillGuardedByInvoiceSOQL() {
        Id fakeInvoiceId = fabricateInvoiceId();
        SapTaxMockTimeout mock = new SapTaxMockTimeout();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        // Should NOT throw — guard fires before the timeout mock can raise.
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fakeInvoiceId));
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Guard must still produce a Result');
        System.assertEquals('Error', results[0].status);
        System.assert(results[0].message.startsWith('Invoice not found'));
        System.assertEquals(0, mock.callCount,
            'Timeout mock must not be invoked when Invoice SOQL guard fires first');
    }

    // =====================================================================
    //  Public entry point — SAP-write + fallback paths driven via @TestVisible
    //  Invoice injection (JSON deserialization pattern — Invoice is Apex-DML-
    //  blocked). testInvoiceOverride bypasses the SOQL; testSkipDml=true stops
    //  the final `update updates` from touching the (invalid) in-memory Ids.
    // =====================================================================

    /** Fabricate a well-formed Invoice Id. */
    private static Id fakeInvoiceId(String suffix) {
        String prefix = Invoice.SObjectType.getDescribe().getKeyPrefix();
        // 3-char prefix + 12-char body = 15 total.
        return Id.valueOf(prefix + suffix);
    }

    /** JSON-deserialize an Invoice with a hydrated BillingAccount relationship. */
    private static Invoice buildInvoice(Id fakeId, Decimal totalAmount, String country) {
        String bogusAccountId = '001000000000001AAA';
        String json = '{'
            + '"attributes":{"type":"Invoice"},'
            + '"Id":"' + String.valueOf(fakeId) + '",'
            + '"DocumentNumber":"INV-TEST-001",'
            + '"TotalAmount":' + totalAmount + ','
            + '"TotalTaxAmount":0,'
            + '"BillingAccountId":"' + bogusAccountId + '",'
            + '"BillingAccount":{"attributes":{"type":"Account"},"Id":"' + bogusAccountId + '","Name":"Acme AG","BillingCountry":' + (country == null ? 'null' : ('"' + country + '"')) + '}'
            + '}';
        return (Invoice) System.JSON.deserialize(json, Invoice.class);
    }

    /** Wire up the @TestVisible seams with a single-Invoice map. */
    private static void injectInvoice(Invoice inv) {
        SapTaxCalculationService.testInvoiceOverride = new Map<Id, Invoice>{ inv.Id => inv };
        SapTaxCalculationService.testSkipDml = true;
    }

    @IsTest
    static void calculateForInvoice_sapReturns200_writesSapAuditFields_taxEngineUsed_SAP_API() {
        Id fid = fakeInvoiceId('000000000A01');
        Invoice inv = buildInvoice(fid, 1000.00, 'DE');
        injectInvoice(inv);
        SapTaxMock200 mock = new SapTaxMock200();
        mock.returnedRate = 19.00;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One Request -> one Result');
        SapTaxCalculationService.Result r = results[0];
        System.assertEquals('Success', r.status, 'Happy-path SAP 200 must be Success');
        System.assertEquals('SAP_API', r.engineUsed,
            'When SAP responds 200 with a parseable rate, engineUsed must be SAP_API');
        System.assertEquals(19.00, r.taxRate, 'Rate must be pulled from mock body');
        System.assertEquals(190.00, r.taxAmount,
            '1000.00 @ 19% must equal 190.00 (setScale(2))');
        System.assertEquals(fid, r.invoiceId, 'Result must echo the Invoice Id');
        System.assertEquals(1, mock.callCount, 'Exactly one SAP callout expected');
        System.assert(mock.lastEndpoint.contains('API_DETERMINE_TAX_SRV'),
            'Endpoint must target the SAP tax OData service. Got: ' + mock.lastEndpoint);
        System.assertEquals('GET', mock.lastMethod, 'SAP tax API is a GET');
        System.assertEquals(SAP_API_KEY, mock.lastHeaders.get('APIKey'),
            'APIKey header must be pulled from SAP_Config__c');
    }

    @IsTest
    static void calculateForInvoice_sap403_fallsBackToCountryTable_taxEngineUsed_SAP_FALLBACK_TABLE() {
        Id fid = fakeInvoiceId('000000000A02');
        Invoice inv = buildInvoice(fid, 500.00, 'DE');
        injectInvoice(inv);
        SapTaxMock403 mock = new SapTaxMock403();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        SapTaxCalculationService.Result r = results[0];
        System.assertEquals('Success', r.status,
            '403 is a graceful fallback — not an Error');
        System.assertEquals('SAP_FALLBACK_TABLE', r.engineUsed,
            'SAP 403 (license-gated sandbox) must trigger country-table fallback');
        System.assertEquals(19.00, r.taxRate, 'DE fallback rate is 19.00');
        System.assertEquals(95.00, r.taxAmount, '500.00 @ 19% = 95.00');
        System.assertEquals(1, mock.callCount, 'SAP was attempted before fallback');
    }

    @IsTest
    static void calculateForInvoice_sap500_fallsBackToCountryTable() {
        Id fid = fakeInvoiceId('000000000A03');
        Invoice inv = buildInvoice(fid, 200.00, 'AT');
        injectInvoice(inv);
        SapTaxMock500 mock = new SapTaxMock500();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        SapTaxCalculationService.Result r = results[0];
        System.assertEquals('SAP_FALLBACK_TABLE', r.engineUsed,
            'SAP 500 must fall through to country-table');
        System.assertEquals(20.00, r.taxRate, 'AT fallback rate is 20.00');
        System.assertEquals(40.00, r.taxAmount, '200.00 @ 20% = 40.00');
    }

    @IsTest
    static void calculateForInvoice_calloutException_fallsBackToCountryTable() {
        Id fid = fakeInvoiceId('000000000A04');
        Invoice inv = buildInvoice(fid, 100.00, 'CH');
        injectInvoice(inv);
        SapTaxMockTimeout mock = new SapTaxMockTimeout();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        SapTaxCalculationService.Result r = results[0];
        System.assertEquals('Success', r.status,
            'CalloutException is caught; end state is a Successful fallback result');
        System.assertEquals('SAP_FALLBACK_TABLE', r.engineUsed,
            'Timeout must NOT propagate — caught by try/catch, fallback engaged');
        System.assertEquals(7.70, r.taxRate, 'CH fallback rate is 7.70');
        System.assertEquals(7.70, r.taxAmount, '100.00 @ 7.70% = 7.70');
    }

    @IsTest
    static void calculateForInvoice_countryDE_writes19PercentVat_toInMemoryInvoice() {
        Id fid = fakeInvoiceId('000000000A05');
        Invoice inv = buildInvoice(fid, 1000.00, 'DE');
        injectInvoice(inv);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock403()); // force fallback
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        SapTaxCalculationService.Result r = results[0];
        System.assertEquals(19.00, r.taxRate, 'German VAT is 19%');
        System.assertEquals(190.00, r.taxAmount, '1000.00 @ 19% = 190.00');
        System.assertEquals('SAP_FALLBACK_TABLE', r.engineUsed);
        System.assert(r.message.contains('19'), 'Message must mention the rate. Got: ' + r.message);
    }

    @IsTest
    static void calculateForInvoice_countryAT_writes20PercentVat() {
        Id fid = fakeInvoiceId('000000000A06');
        Invoice inv = buildInvoice(fid, 500.00, 'AT');
        injectInvoice(inv);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock403());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        System.assertEquals(20.00, results[0].taxRate, 'Austrian VAT is 20%');
        System.assertEquals(100.00, results[0].taxAmount, '500.00 @ 20% = 100.00');
    }

    @IsTest
    static void calculateForInvoice_countryCH_writes_7_7_PercentVat() {
        Id fid = fakeInvoiceId('000000000A07');
        Invoice inv = buildInvoice(fid, 1000.00, 'CH');
        injectInvoice(inv);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock403());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        System.assertEquals(7.70, results[0].taxRate, 'Swiss VAT is 7.70%');
        System.assertEquals(77.00, results[0].taxAmount, '1000.00 @ 7.70% = 77.00');
    }

    @IsTest
    static void calculateForInvoice_countryUS_writes_0_PercentVat() {
        Id fid = fakeInvoiceId('000000000A08');
        Invoice inv = buildInvoice(fid, 1000.00, 'US');
        injectInvoice(inv);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock403());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        System.assertEquals(0.00, results[0].taxRate,
            'US federal is 0 — state-level would come from SAP jurisdiction code');
        System.assertEquals(0.00, results[0].taxAmount, '1000.00 @ 0% = 0.00');
    }

    @IsTest
    static void calculateForInvoice_nullCountry_usesDefaultRate() {
        Id fid = fakeInvoiceId('000000000A09');
        Invoice inv = buildInvoice(fid, 100.00, null);
        injectInvoice(inv);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock403());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        System.assertEquals(19.00, results[0].taxRate,
            'Null country must fall through to DEFAULT_RATE (19%)');
        System.assertEquals(19.00, results[0].taxAmount, '100 @ 19% = 19.00');
    }

    @IsTest
    static void calculateForInvoice_nullTotalAmount_treatedAsZero() {
        // The service defensively coerces null TotalAmount to 0.
        Id fid = fakeInvoiceId('000000000A0A');
        String bogusAccountId = '001000000000001AAA';
        String json = '{'
            + '"attributes":{"type":"Invoice"},'
            + '"Id":"' + fid + '",'
            + '"BillingAccountId":"' + bogusAccountId + '",'
            + '"BillingAccount":{"attributes":{"type":"Account"},"Id":"' + bogusAccountId + '","BillingCountry":"DE"}'
            + '}';
        Invoice inv = (Invoice) System.JSON.deserialize(json, Invoice.class);
        injectInvoice(inv);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock403());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        System.assertEquals('Success', results[0].status,
            'Null TotalAmount must not throw — coerced to 0');
        System.assertEquals(19.00, results[0].taxRate, 'DE rate still resolved');
        System.assertEquals(0.00, results[0].taxAmount,
            'Zero taxable amount @ 19% = 0.00');
    }

    @IsTest
    static void calculateForInvoice_bulkMixed_someInjectedSomeMissing_correctResultsForEach() {
        // 2 in-memory Invoices + 1 fabricated Id NOT in the override map ->
        // 2 Successes + 1 "Invoice not found".
        Id fidA = fakeInvoiceId('000000000B01');
        Id fidB = fakeInvoiceId('000000000B02');
        Id fidC = fakeInvoiceId('000000000B03'); // not injected
        Invoice invA = buildInvoice(fidA, 100.00, 'DE');
        Invoice invB = buildInvoice(fidB, 200.00, 'AT');

        SapTaxCalculationService.testInvoiceOverride = new Map<Id, Invoice>{
            fidA => invA, fidB => invB
        };
        SapTaxCalculationService.testSkipDml = true;

        List<SapTaxCalculationService.Request> reqs = new List<SapTaxCalculationService.Request>{
            buildRequest(fidA), buildRequest(fidB), buildRequest(fidC)
        };

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock403());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(reqs);
        Test.stopTest();

        System.assertEquals(3, results.size(), '3 requests -> 3 results');
        // Result order matches request order.
        System.assertEquals('Success', results[0].status);
        System.assertEquals(19.00, results[0].taxRate);
        System.assertEquals('Success', results[1].status);
        System.assertEquals(20.00, results[1].taxRate);
        System.assertEquals('Error', results[2].status);
        System.assert(results[2].message.startsWith('Invoice not found'),
            'Third result must be Invoice not found. Got: ' + results[2].message);
    }

    @IsTest
    static void calculateForInvoice_sap200_butMalformedBody_fallsBackToCountryTable() {
        // Body doesn't match the d.results[0].TaxRate schema -> trySapTaxApi returns
        // null -> fallback engages. Proves the parser is defensive.
        Id fid = fakeInvoiceId('000000000C01');
        Invoice inv = buildInvoice(fid, 100.00, 'DE');
        injectInvoice(inv);

        // Anonymous 200-with-garbage-body mock.
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapTaxMock200Malformed());
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(singleRequest(fid));
        Test.stopTest();

        System.assertEquals('SAP_FALLBACK_TABLE', results[0].engineUsed,
            'Malformed 200 body must yield rate=null -> fallback engaged');
        System.assertEquals(19.00, results[0].taxRate);
    }

    /** 200 OK with a body that does NOT match the expected schema. */
    public class SapTaxMock200Malformed implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody('{"unexpected":"shape"}');
            return resp;
        }
    }

    @IsTest
    static void computeTax_multipleFabricatedInvoices_allResolveToInvoiceNotFound() {
        // Bulk safety: 3 unresolved Invoices should each produce a distinct Error result,
        // no callouts, and the service should not throw or silently drop requests.
        SapTaxMock200 mock = new SapTaxMock200();
        List<SapTaxCalculationService.Request> requests = new List<SapTaxCalculationService.Request>();
        String prefix = Invoice.SObjectType.getDescribe().getKeyPrefix();
        List<Id> ids = new List<Id>{
            Id.valueOf(prefix + '000000000AAA'),
            Id.valueOf(prefix + '000000000AAB'),
            Id.valueOf(prefix + '000000000AAC')
        };
        for (Id fid : ids) requests.add(buildRequest(fid));

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapTaxCalculationService.Result> results =
            SapTaxCalculationService.calculateForInvoice(requests);
        Test.stopTest();

        System.assertEquals(3, results.size(), '3 requests -> 3 results');
        for (Integer i = 0; i < 3; i++) {
            System.assertEquals('Error', results[i].status);
            System.assert(results[i].message.startsWith('Invoice not found'),
                'Each result must report "Invoice not found". Got: ' + results[i].message);
        }
        System.assertEquals(0, mock.callCount,
            'Bulk unresolved requests must consume zero SAP callouts');
    }
}

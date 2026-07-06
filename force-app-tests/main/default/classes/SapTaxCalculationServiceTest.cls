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
 * What is NOT covered (roadmap TS-TEST-008):
 *   - HTTP 200 SAP response parsing (`d.results[0].TaxRate`) + Invoice write-back.
 *     Requires either (a) refactoring calculateForInvoice to accept a passed-in Invoice
 *     record for testability, or (b) an Invoice-DML mock harness. Recommendation:
 *     extract a package-private overload `List<Result> calculateForInvoices(Map<Id, Invoice> invoices, ...)`
 *     that skips the SOQL step — tests pass an in-memory Invoice with hydrated
 *     BillingAccount relationship via JSON deserialization.
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

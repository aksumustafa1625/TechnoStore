/**
 * Unit tests for SapCustomerMasterSyncService (ADR-027 — SAP Customer Master → SF Account).
 *
 * Covers the outbound SAP OData v2 GET /A_BusinessPartner callout and the
 * Account upsert-by-external-id contract:
 *   - 200 body with { d: { results: [...] } } upserts by SAP_BP_Number__c
 *     (external id) → new Accounts created, existing Accounts updated in place
 *   - Scope boundary (ADR-021): the sync only touches Name (create only) and
 *     the SAP audit fields (SAP_Customer_Category__c / SAP_Customer_Group__c /
 *     SAP_Last_Synced_At__c). Commercial config on existing Accounts
 *     (Industry, AnnualRevenue) must not be clobbered.
 *   - Name-picking cascade: BusinessPartnerFullName → BusinessPartnerName →
 *     FirstName+LastName (exercised through the @TestVisible pickName helper).
 *   - Endpoint construction: base URL, OData $filter=BusinessPartnerCategory
 *     eq '2' (URL-encoded), $format=json, $top clamped to [1..200].
 *   - Error branches: 401 / 500 / CalloutException → Result.status='Error',
 *     no Account writes.
 *   - Missing SAP_Config__c short-circuits with an Error result.
 *   - Empty results list returns Success with zero writes.
 *
 * Mock recording state (lastEndpoint / lastHeaders / callCount) is captured as
 * INSTANCE fields on the inner HttpCalloutMock classes — Apex forbids static
 * on inner-class members, so tests get a fresh mock instance per method and
 * no reset() dance is needed.
 *
 * Custom_Pricing_Tier__c is NOT asserted (not present on Account in this org);
 * the "audit-fields-only" test uses Industry + AnnualRevenue instead.
 */
@IsTest
private class SapCustomerMasterSyncServiceTest {

    private static final String SAP_BASE = 'https://test.sap.example';
    private static final String SAP_KEY  = 'test-sap-key';

    // ---------- @TestSetup ----------

    @TestSetup
    static void seed() {
        // Org-default hierarchy custom setting — the service reads via getOrgDefaults().
        insert new SAP_Config__c(
            SetupOwnerId   = UserInfo.getOrganizationId(),
            API_Base_URL__c = SAP_BASE,
            API_Key__c      = SAP_KEY
        );

        // One existing Account already carrying an SAP BP number (matches BP-100 in the
        // 200-mock body — will be updated in place). Populate commercial fields that
        // the sync must NOT touch.
        Account existing = new Account(
            Name             = 'Acme DE GmbH (existing)',
            BillingCountry   = 'Germany',
            SAP_BP_Number__c = 'BP-100',
            Industry         = 'Technology',
            AnnualRevenue    = 5000000
        );

        // One SF-native Account with no SAP linkage — must not be disturbed.
        Account sfOnly = new Account(
            Name           = 'SF-Only Legacy AG',
            BillingCountry = 'Germany',
            Industry       = 'Retail',
            AnnualRevenue  = 1000000
        );

        insert new List<Account>{ existing, sfOnly };
    }

    // ---------- Helpers ----------

    private static SapCustomerMasterSyncService.Request buildReq(Integer maxFetch) {
        SapCustomerMasterSyncService.Request r = new SapCustomerMasterSyncService.Request();
        r.maxFetch = maxFetch;
        return r;
    }

    // ---------- Inline HttpCalloutMocks (INSTANCE recording fields) ----------

    /** 200 OK — two Organization BPs. BP-100 already exists (will update), BP-200 is new. */
    public class SapCustMasterMock200 implements HttpCalloutMock {
        public String  lastEndpoint;
        public String  lastMethod;
        public Map<String, String> lastHeaders = new Map<String, String>();
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            lastEndpoint = req.getEndpoint();
            lastMethod   = req.getMethod();
            lastHeaders.put('APIKey',          req.getHeader('APIKey'));
            lastHeaders.put('Accept',          req.getHeader('Accept'));
            lastHeaders.put('Accept-Encoding', req.getHeader('Accept-Encoding'));

            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody(
                '{"d":{"results":[' +
                    '{"BusinessPartner":"BP-100","BusinessPartnerFullName":"Acme DE GmbH",' +
                        '"BusinessPartnerCategory":"2","BusinessPartnerGrouping":"BP01"},' +
                    '{"BusinessPartner":"BP-200","BusinessPartnerFullName":"Beta AG"}' +
                ']}}'
            );
            return resp;
        }
    }

    /** 200 OK with zero results — Success + zero writes. */
    public class SapCustMasterMock200Empty implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody('{"d":{"results":[]}}');
            return resp;
        }
    }

    /** 200 OK with FullName absent so the name-picking cascade falls through. */
    public class SapCustMasterMock200MissingFullName implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            // BP-300 uses BusinessPartnerName; BP-400 uses FirstName+LastName.
            resp.setBody(
                '{"d":{"results":[' +
                    '{"BusinessPartner":"BP-300","BusinessPartnerName":"Gamma GmbH",' +
                        '"BusinessPartnerCategory":"2","BusinessPartnerGrouping":"BP02"},' +
                    '{"BusinessPartner":"BP-400","FirstName":"Max","LastName":"Mustermann",' +
                        '"BusinessPartnerCategory":"1","BusinessPartnerGrouping":"BP03"}' +
                ']}}'
            );
            return resp;
        }
    }

    public class SapCustMasterMock401 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(401);
            resp.setStatus('Unauthorized');
            resp.setBody('{"error":{"code":"401","message":{"value":"Unauthorized"}}}');
            return resp;
        }
    }

    public class SapCustMasterMock500 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(500);
            resp.setStatus('Internal Server Error');
            resp.setBody('{"error":{"code":"500","message":{"value":"SAP backend unavailable"}}}');
            return resp;
        }
    }

    public class SapCustMasterMockTimeout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Read timed out');
        }
    }

    // ---------- Tests ----------

    @IsTest
    static void sync_200Response_upsertsAccountsByExternalId_new() {
        SapCustMasterMock200 mock = new SapCustMasterMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapCustomerMasterSyncService.Result> results =
            SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One Result expected');
        SapCustomerMasterSyncService.Result r = results[0];
        System.assertEquals('Success', r.status, 'Status must be Success on 200. Message: ' + r.message);
        System.assertEquals(2, r.totalFetched, 'totalFetched must reflect the mock body');
        System.assertEquals(1, r.createdCount, 'BP-200 is new → 1 created');
        System.assertEquals(1, r.updatedCount, 'BP-100 pre-existed → 1 updated');
        System.assertEquals(0, r.failedCount,  'No failed upserts expected');
        System.assertEquals(1, mock.callCount, 'Exactly one SAP callout expected');

        // BP-200 was newly created (with [SAP] prefix).
        List<Account> created = [
            SELECT Id, Name, SAP_BP_Number__c, SAP_Customer_Category__c,
                   SAP_Customer_Group__c, SAP_Last_Synced_At__c
            FROM Account WHERE SAP_BP_Number__c = 'BP-200'
        ];
        System.assertEquals(1, created.size(), 'BP-200 must be inserted');
        System.assertEquals('[SAP] Beta AG', created[0].Name,
            'New Account Name must be prefixed with [SAP] and use BusinessPartnerFullName');
        System.assertNotEquals(null, created[0].SAP_Last_Synced_At__c,
            'SAP_Last_Synced_At__c must be stamped on create');
    }

    @IsTest
    static void sync_200Response_upsertsExistingAccount_updatesSapAuditFields_only() {
        SapCustMasterMock200 mock = new SapCustMasterMock200();

        // Snapshot BEFORE state of the pre-existing Account (BP-100).
        Account beforeAccount = [
            SELECT Id, Name, Industry, AnnualRevenue,
                   SAP_Customer_Category__c, SAP_Customer_Group__c, SAP_Last_Synced_At__c
            FROM Account WHERE SAP_BP_Number__c = 'BP-100'
        ];
        System.assertEquals('Acme DE GmbH (existing)', beforeAccount.Name);
        System.assertEquals('Technology',              beforeAccount.Industry);
        System.assertEquals(5000000,                    beforeAccount.AnnualRevenue);
        System.assertEquals(null, beforeAccount.SAP_Customer_Category__c,
            'Precondition: no SAP audit fields yet');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        Account afterAccount = [
            SELECT Id, Name, Industry, AnnualRevenue,
                   SAP_Customer_Category__c, SAP_Customer_Group__c, SAP_Last_Synced_At__c
            FROM Account WHERE SAP_BP_Number__c = 'BP-100'
        ];

        // SAP audit fields ARE updated.
        System.assertEquals('2',    afterAccount.SAP_Customer_Category__c,
            'Category must be pulled from BusinessPartnerCategory');
        System.assertEquals('BP01', afterAccount.SAP_Customer_Group__c,
            'Group must be pulled from BusinessPartnerGrouping');
        System.assertNotEquals(null, afterAccount.SAP_Last_Synced_At__c,
            'SAP_Last_Synced_At__c must be stamped on the existing record');

        // Commercial config fields on the existing Account are NOT touched (scope boundary ADR-021).
        System.assertEquals(beforeAccount.Name,          afterAccount.Name,
            'Existing Account Name must not be renamed by the sync');
        System.assertEquals(beforeAccount.Industry,      afterAccount.Industry,
            'Industry must be left alone — commercial config owned by sales ops');
        System.assertEquals(beforeAccount.AnnualRevenue, afterAccount.AnnualRevenue,
            'AnnualRevenue must be left alone — commercial config owned by sales ops');
    }

    @IsTest
    static void sync_pickName_prefers_BusinessPartnerFullName() {
        // Exercises the @TestVisible pickName helper directly, isolating the cascade rule.
        Map<String, Object> sp = new Map<String, Object>{
            'BusinessPartnerFullName' => 'Full Name Wins',
            'BusinessPartnerName'     => 'Fallback Name',
            'FirstName'               => 'Max',
            'LastName'                => 'Mustermann'
        };
        System.assertEquals('Full Name Wins',
            SapCustomerMasterSyncService.pickName(sp),
            'FullName must win when present and non-blank');
    }

    @IsTest
    static void sync_pickName_fallsBackTo_BusinessPartnerName() {
        // FullName blank → fall back to BusinessPartnerName.
        Map<String, Object> sp = new Map<String, Object>{
            'BusinessPartnerFullName' => '',
            'BusinessPartnerName'     => 'Gamma GmbH',
            'FirstName'               => 'Max',
            'LastName'                => 'Mustermann'
        };
        System.assertEquals('Gamma GmbH',
            SapCustomerMasterSyncService.pickName(sp),
            'Blank FullName must fall through to BusinessPartnerName');

        // FullName absent entirely → same fallback.
        Map<String, Object> sp2 = new Map<String, Object>{
            'BusinessPartnerName' => 'Delta AG'
        };
        System.assertEquals('Delta AG',
            SapCustomerMasterSyncService.pickName(sp2),
            'Absent FullName key must fall through to BusinessPartnerName');
    }

    @IsTest
    static void sync_pickName_fallsBackTo_FirstNamePlusLastName() {
        Map<String, Object> sp = new Map<String, Object>{
            'FirstName' => 'Max',
            'LastName'  => 'Mustermann'
        };
        System.assertEquals('Max Mustermann',
            SapCustomerMasterSyncService.pickName(sp),
            'When only First+Last are present, they must be concatenated');

        // Both blank → trimmed empty string (documented behavior).
        Map<String, Object> sp2 = new Map<String, Object>{};
        System.assertEquals('',
            SapCustomerMasterSyncService.pickName(sp2),
            'Absent keys must return trimmed empty string, not throw');
    }

    @IsTest
    static void sync_odataFilter_containsOrganizationCategory_2() {
        SapCustMasterMock200 mock = new SapCustMasterMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assertNotEquals(null, mock.lastEndpoint, 'Endpoint must have been captured');
        System.assert(mock.lastEndpoint.contains('$filter=BusinessPartnerCategory'),
            'Endpoint must OData-filter on BusinessPartnerCategory. Got: ' + mock.lastEndpoint);
        // URL-encoded "eq '2'" is "eq%20%272%27" — assert the exact wire form.
        System.assert(mock.lastEndpoint.contains('eq%20%272%27'),
            'Filter must equal Category 2 (organizations) URL-encoded. Got: ' + mock.lastEndpoint);
        System.assertEquals('GET', mock.lastMethod, 'Method must be GET');
        System.assertEquals(SAP_KEY, mock.lastHeaders.get('APIKey'),
            'APIKey header must be the value from SAP_Config__c');
        System.assertEquals('application/json', mock.lastHeaders.get('Accept'),
            'Accept header must be application/json');
        System.assertEquals('identity', mock.lastHeaders.get('Accept-Encoding'),
            'Accept-Encoding must be identity (SAP OData quirk)');
    }

    @IsTest
    static void sync_default_topN_and_cap() {
        // Null Request list → service uses default $top=25.
        SapCustMasterMock200 mock = new SapCustMasterMock200();
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapCustomerMasterSyncService.sync(null);
        Test.stopTest();

        System.assertEquals(1, mock.callCount, 'One callout expected even for null request');
        System.assert(mock.lastEndpoint.contains('$top=25'),
            'Null Request must use the default top=25. Got: ' + mock.lastEndpoint);
    }

    @IsTest
    static void sync_customTopN() {
        SapCustMasterMock200 mock = new SapCustMasterMock200();
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(50) });
        Test.stopTest();

        System.assert(mock.lastEndpoint.contains('$top=50'),
            'Custom maxFetch=50 must flow through to the URL. Got: ' + mock.lastEndpoint);
    }

    @IsTest
    static void sync_topNAbove200_isClampedTo200() {
        SapCustMasterMock200 mock = new SapCustMasterMock200();
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(5000) });
        Test.stopTest();

        System.assert(mock.lastEndpoint.contains('$top=200'),
            'maxFetch above 200 must be clamped to 200 (production-safe upper bound). Got: '
            + mock.lastEndpoint);
        System.assert(!mock.lastEndpoint.contains('$top=5000'),
            'Raw 5000 must never reach the wire');
    }

    @IsTest
    static void sync_401_logs_and_noChanges() {
        // Snapshot BP-100 audit fields before the failing call.
        Account beforeAccount = [
            SELECT SAP_Customer_Category__c, SAP_Last_Synced_At__c
            FROM Account WHERE SAP_BP_Number__c = 'BP-100'
        ];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapCustMasterMock401());
        List<SapCustomerMasterSyncService.Result> results =
            SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assertEquals('Error', results[0].status, 'Status must be Error on 401');
        System.assert(results[0].message != null && results[0].message.contains('401'),
            'Error message must call out the HTTP status. Got: ' + results[0].message);

        Account afterAccount = [
            SELECT SAP_Customer_Category__c, SAP_Last_Synced_At__c
            FROM Account WHERE SAP_BP_Number__c = 'BP-100'
        ];
        System.assertEquals(beforeAccount.SAP_Customer_Category__c, afterAccount.SAP_Customer_Category__c,
            'Existing Account audit fields must be unchanged on auth failure');
        System.assertEquals(beforeAccount.SAP_Last_Synced_At__c, afterAccount.SAP_Last_Synced_At__c,
            'SAP_Last_Synced_At__c must not be stamped on error');

        System.assertEquals(0,
            [SELECT COUNT() FROM Account WHERE SAP_BP_Number__c = 'BP-200'],
            'No new Accounts must be created on error');
    }

    @IsTest
    static void sync_500_logs_and_noChanges() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapCustMasterMock500());
        List<SapCustomerMasterSyncService.Result> results =
            SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assertEquals('Error', results[0].status, 'Status must be Error on 500');
        System.assert(results[0].message != null && results[0].message.contains('500'),
            'Error message must call out the HTTP status. Got: ' + results[0].message);

        System.assertEquals(0,
            [SELECT COUNT() FROM Account WHERE SAP_BP_Number__c = 'BP-200'],
            'No new Accounts must be created on 500');
    }

    @IsTest
    static void sync_calloutException_isHandledGracefully() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapCustMasterMockTimeout());
        List<SapCustomerMasterSyncService.Result> results =
            SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Exception must not abort — one Result still returned');
        System.assertEquals('Error', results[0].status,
            'Timeout must map to Error status');
        System.assert(results[0].message != null && results[0].message.contains('CalloutException'),
            'Error message must surface the exception type. Got: ' + results[0].message);

        System.assertEquals(0,
            [SELECT COUNT() FROM Account WHERE SAP_BP_Number__c = 'BP-200'],
            'No Accounts must be created when the callout throws');
    }

    @IsTest
    static void sync_missingSapConfig_shortCircuits() {
        // Blank the org-default SAP_Config__c so the guard clause fires.
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = null;
        cfg.API_Key__c      = null;
        upsert cfg;

        Test.startTest();
        // No mock — guard must fire before any HTTP work.
        List<SapCustomerMasterSyncService.Result> results =
            SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Guard should still return a Result');
        System.assertEquals('Error', results[0].status,
            'Missing config must map to Error status');
        System.assert(results[0].message != null && results[0].message.contains('SAP_Config__c'),
            'Error message must call out the missing custom setting. Got: ' + results[0].message);
        System.assertEquals(0, Limits.getCallouts(),
            'No callout must be consumed when config is missing');
    }

    @IsTest
    static void sync_emptyResults_noAccountsCreated() {
        SapCustMasterMock200Empty mock = new SapCustMasterMock200Empty();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapCustomerMasterSyncService.Result> results =
            SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assertEquals(1, mock.callCount, 'Callout must have happened');
        SapCustomerMasterSyncService.Result r = results[0];
        System.assertEquals('Success', r.status,
            'Empty results is a benign Success, not an Error');
        System.assertEquals(0, r.totalFetched, 'totalFetched must be 0 on empty response');
        System.assertEquals(0, r.createdCount, 'No creates on empty response');
        System.assertEquals(0, r.updatedCount, 'No updates on empty response');
        System.assert(r.message != null && r.message.contains('0 business partners'),
            'Empty-body message must be explicit. Got: ' + r.message);

        // Setup Accounts still exactly 2 — nothing added.
        Integer totalAccounts = [SELECT COUNT() FROM Account];
        System.assertEquals(2, totalAccounts,
            'Setup created 2 Accounts; empty sync must not add any');
    }

    @IsTest
    static void sync_endpointConstruction_containsBaseUrl_and_ODataFormat_json() {
        SapCustMasterMock200 mock = new SapCustMasterMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assert(mock.lastEndpoint.startsWith(SAP_BASE),
            'Endpoint must start with SAP_Config__c.API_Base_URL__c. Got: ' + mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('/s4hanacloud/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner'),
            'Endpoint must target A_BusinessPartner entity set. Got: ' + mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('$format=json'),
            'OData $format=json must be requested. Got: ' + mock.lastEndpoint);
    }

    @IsTest
    static void sync_pickName_fallbackCascade_endToEnd_viaCallout() {
        // Wire-level exercise of the pickName cascade: mock returns BP-300 (BusinessPartnerName)
        // and BP-400 (First+Last). Assert the two new Accounts are created with the correct Name.
        SapCustMasterMock200MissingFullName mock = new SapCustMasterMock200MissingFullName();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapCustomerMasterSyncService.Result> results =
            SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ buildReq(null) });
        Test.stopTest();

        System.assertEquals('Success', results[0].status,
            'Fallback-name payload must still Success. Message: ' + results[0].message);
        System.assertEquals(2, results[0].createdCount, 'Both BPs are new → 2 created');

        Account gamma = [
            SELECT Name FROM Account WHERE SAP_BP_Number__c = 'BP-300' LIMIT 1
        ];
        System.assertEquals('[SAP] Gamma GmbH', gamma.Name,
            'BP-300 must fall back to BusinessPartnerName');

        Account person = [
            SELECT Name FROM Account WHERE SAP_BP_Number__c = 'BP-400' LIMIT 1
        ];
        System.assertEquals('[SAP] Max Mustermann', person.Name,
            'BP-400 must fall back to FirstName + LastName');
    }
}

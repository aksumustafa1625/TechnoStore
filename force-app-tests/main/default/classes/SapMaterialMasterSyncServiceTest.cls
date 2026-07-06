/**
 * Unit tests for SapMaterialMasterSyncService (ADR-026).
 *
 * Covers the outbound Apex REST callout to SAP API_PRODUCT_SRV
 * (OData v2 GET /A_Product?$top=N&$format=json):
 *
 *   - 200 success — new SAP materials arrive, upsert-by-external-id
 *     (SAP_Material_Number__c) creates fresh Product2 rows with the
 *     '[SAP] ' name prefix, ProductDescription copied to
 *     SAP_Product_Description__c and SAP_Last_Synced_At__c stamped.
 *   - 200 success on a Product2 that ALREADY carries the external id
 *     refreshes the SAP audit fields (SAP_Product_Description__c +
 *     SAP_Last_Synced_At__c) WITHOUT overwriting commercial fields
 *     (Name, IsActive) — this is the whole point of a delta-safe
 *     material master sync per ADR-026.
 *   - Empty OData results set → safe no-op, 0 Product2 rows written.
 *   - maxFetch: default is 25, requests > 200 are clamped to 200,
 *     a request value in range flows into the endpoint verbatim.
 *   - Non-200 responses (401 auth, 500 downstream) produce
 *     Result.status='Error', do NOT touch Product2.
 *   - CalloutException (timeout / DNS) is caught, mapped to
 *     Result.status='Error' with the type name in the message.
 *   - Missing / blank SAP_Config__c short-circuits — no callout.
 *   - Endpoint shape includes the base URL, the OData path, and
 *     both $top and $format=json query params.
 *   - Auth header is APIKey (SAP API Hub convention), not Bearer.
 *   - Name resolution chain: ProductDescription → ProductOldID →
 *     material number, all captured via the '[SAP] ' name prefix.
 *
 * NOTES:
 *   - Mock recording state (lastEndpoint / lastHeaders / callCount)
 *     is captured as INSTANCE fields on each mock (Apex forbids
 *     static on inner-class members), so tests get a fresh mock
 *     instance per method — no reset() needed.
 *   - SAP_Config__c is a Hierarchy custom setting: seed with an
 *     explicit SetupOwnerId=UserInfo.getOrganizationId() insert
 *     so getOrgDefaults() returns a populated record.
 */
@IsTest
private class SapMaterialMasterSyncServiceTest {

    private static final String BASE_URL = 'https://test.sap.example';
    private static final String API_KEY  = 'test-key-abc';

    // ---------- @TestSetup: SAP_Config + Product2 seed ----------

    @TestSetup
    static void seed() {
        SAP_Config__c cfg = new SAP_Config__c(
            SetupOwnerId    = UserInfo.getOrganizationId(),
            API_Base_URL__c = BASE_URL,
            API_Key__c      = API_KEY
        );
        insert cfg;

        // Existing Product2 whose external id already matches SAP MAT-100 —
        // upsert path should refresh audit fields, keep commercial fields.
        Product2 existingMatched = new Product2(
            Name = 'Legacy SF Name — DO NOT OVERWRITE',
            IsActive = true,
            SAP_Material_Number__c = 'MAT-100',
            SAP_Product_Description__c = 'Stale description'
        );

        // Existing Product2 with no SAP link at all — must be left untouched.
        Product2 unrelated = new Product2(
            Name = 'Non-SAP Product',
            IsActive = true
        );

        insert new List<Product2>{ existingMatched, unrelated };
    }

    // ---------- Helpers ----------

    private static SapMaterialMasterSyncService.Request req(Integer maxFetch) {
        SapMaterialMasterSyncService.Request r = new SapMaterialMasterSyncService.Request();
        r.maxFetch = maxFetch;
        return r;
    }

    private static List<SapMaterialMasterSyncService.Request> reqList(Integer maxFetch) {
        return new List<SapMaterialMasterSyncService.Request>{ req(maxFetch) };
    }

    // ---------- Inline HttpCalloutMocks ----------

    /**
     * Realistic OData v2 body — two materials, MAT-100 already exists in SF
     * (matched-existing branch) and MAT-200 does not (new-Product2 branch).
     */
    public class SapMatMasterMock200 implements HttpCalloutMock {
        public Map<String, String> lastHeaders = new Map<String, String>();
        public String  lastEndpoint;
        public String  lastMethod;
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest request) {
            callCount++;
            lastEndpoint = request.getEndpoint();
            lastMethod   = request.getMethod();
            lastHeaders.put('APIKey',          request.getHeader('APIKey'));
            lastHeaders.put('Accept',          request.getHeader('Accept'));
            lastHeaders.put('Accept-Encoding', request.getHeader('Accept-Encoding'));

            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody(
                '{"d":{"results":[' +
                    '{"Product":"MAT-100","ProductDescription":"Laptop Pro 15","ProductOldID":"OLD-100"},' +
                    '{"Product":"MAT-200","ProductDescription":"External SSD 1TB"}' +
                ']}}'
            );
            return resp;
        }
    }

    /** Fallback-chain fixture — MAT-300 has no description (falls back to
     *  ProductOldID='OLD-300'); MAT-400 has neither (falls back to material). */
    public class SapMatMasterMockFallbacks implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest request) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody(
                '{"d":{"results":[' +
                    '{"Product":"MAT-300","ProductOldID":"OLD-300"},' +
                    '{"Product":"MAT-400"}' +
                ']}}'
            );
            return resp;
        }
    }

    public class SapMatMasterMock200Empty implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest request) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody('{"d":{"results":[]}}');
            return resp;
        }
    }

    public class SapMatMasterMock401 implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest request) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(401);
            resp.setStatus('Unauthorized');
            resp.setBody('{"error":{"code":"401","message":{"value":"Missing APIKey."}}}');
            return resp;
        }
    }

    public class SapMatMasterMock500 implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest request) {
            callCount++;
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(500);
            resp.setStatus('Internal Server Error');
            resp.setBody('{"error":{"code":"500","message":{"value":"SAP downstream error"}}}');
            return resp;
        }
    }

    public class SapMatMasterMockTimeout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Read timed out');
        }
    }

    /** Endpoint-capture only — used by "endpoint / topN" tests. Returns empty. */
    public class SapMatMasterMockEndpointCapture implements HttpCalloutMock {
        public String  lastEndpoint;
        public Integer callCount = 0;
        public HttpResponse respond(HttpRequest request) {
            callCount++;
            lastEndpoint = request.getEndpoint();
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setStatus('OK');
            resp.setBody('{"d":{"results":[]}}');
            return resp;
        }
    }

    // ---------- Tests ----------

    @IsTest
    static void sync_200Response_upsertsProductsByExternalId_new() {
        SapMatMasterMock200 mock = new SapMatMasterMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapMaterialMasterSyncService.Result> results =
            SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        System.assertEquals(1, results.size());
        SapMaterialMasterSyncService.Result r = results[0];
        System.assertEquals('Success', r.status, 'Status must be Success on 200');
        System.assertEquals(2, r.totalFetched, 'Two SAP products in the mock body');
        System.assertEquals(1, r.createdCount, 'Only MAT-200 is new');
        System.assertEquals(1, r.updatedCount, 'MAT-100 already exists in seed');
        System.assertEquals(0, r.failedCount, 'No upsert failures expected');
        System.assertEquals(1, mock.callCount, 'Exactly one HTTP call to SAP');

        // MAT-200 was created with the SAP name prefix and description.
        Product2 mat200 = [
            SELECT Name, IsActive, SAP_Material_Number__c, SAP_Product_Description__c,
                   SAP_Last_Synced_At__c
            FROM Product2
            WHERE SAP_Material_Number__c = 'MAT-200'
            LIMIT 1
        ];
        System.assertEquals('[SAP] External SSD 1TB', mat200.Name,
            'New Product2.Name must carry the "[SAP] " prefix + description');
        System.assertEquals('External SSD 1TB', mat200.SAP_Product_Description__c,
            'ProductDescription must land in SAP_Product_Description__c');
        System.assertEquals(true, mat200.IsActive, 'New Product2 must be active');
        System.assertNotEquals(null, mat200.SAP_Last_Synced_At__c,
            'SAP_Last_Synced_At__c must be stamped on create');
    }

    @IsTest
    static void sync_200Response_upsertsExistingProduct_updatesSapAuditFields_only() {
        SapMatMasterMock200 mock = new SapMatMasterMock200();

        // Snapshot the pre-sync state of the existing MAT-100 Product2.
        Product2 before = [
            SELECT Id, Name, IsActive, SAP_Product_Description__c
            FROM Product2
            WHERE SAP_Material_Number__c = 'MAT-100'
            LIMIT 1
        ];
        System.assertEquals('Legacy SF Name — DO NOT OVERWRITE', before.Name,
            'Sanity: seed data intact');
        System.assertEquals('Stale description', before.SAP_Product_Description__c);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        Product2 after1 = [
            SELECT Name, IsActive, SAP_Material_Number__c, SAP_Product_Description__c,
                   SAP_Last_Synced_At__c
            FROM Product2
            WHERE SAP_Material_Number__c = 'MAT-100'
            LIMIT 1
        ];
        System.assertEquals('Legacy SF Name — DO NOT OVERWRITE', after1.Name,
            'Existing Product2.Name MUST NOT be overwritten by SAP sync');
        System.assertEquals(true, after1.IsActive, 'IsActive must not flip on sync');
        System.assertEquals('Laptop Pro 15', after1.SAP_Product_Description__c,
            'SAP_Product_Description__c must be refreshed from SAP');
        System.assertNotEquals(null, after1.SAP_Last_Synced_At__c,
            'SAP_Last_Synced_At__c must be stamped on update');
    }

    @IsTest
    static void sync_emptyResults_noProductsCreated() {
        SapMatMasterMock200Empty mock = new SapMatMasterMock200Empty();

        Integer productsBefore = [SELECT COUNT() FROM Product2];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapMaterialMasterSyncService.Result> results =
            SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        System.assertEquals('Success', results[0].status, 'Empty results is still a success');
        System.assertEquals(0, results[0].totalFetched, 'No products fetched');
        System.assertEquals(0, results[0].createdCount);
        System.assertEquals(0, results[0].updatedCount);
        System.assert(results[0].message != null && results[0].message.contains('0 products'),
            'Message must call out the empty result set. Got: ' + results[0].message);

        Integer productsAfter = [SELECT COUNT() FROM Product2];
        System.assertEquals(productsBefore, productsAfter,
            'No Product2 rows must be created on an empty SAP payload');
    }

    @IsTest
    static void sync_default_topN_is_25_whenNoMaxFetchProvided() {
        SapMatMasterMockEndpointCapture mock = new SapMatMasterMockEndpointCapture();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        // Null request list — service should still callout with defaults.
        SapMaterialMasterSyncService.sync(null);
        Test.stopTest();

        System.assertEquals(1, mock.callCount,
            'Even with null Request list, service must callout with defaults');
        System.assert(mock.lastEndpoint != null && mock.lastEndpoint.contains('$top=25'),
            'Default maxFetch must be 25. Endpoint: ' + mock.lastEndpoint);
    }

    @IsTest
    static void sync_customTopN_isApplied() {
        SapMatMasterMockEndpointCapture mock = new SapMatMasterMockEndpointCapture();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapMaterialMasterSyncService.sync(reqList(50));
        Test.stopTest();

        System.assert(mock.lastEndpoint != null && mock.lastEndpoint.contains('$top=50'),
            'Custom maxFetch=50 must land in $top query param. Endpoint: ' + mock.lastEndpoint);
    }

    @IsTest
    static void sync_topNAbove200_isClampedTo200() {
        SapMatMasterMockEndpointCapture mock = new SapMatMasterMockEndpointCapture();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapMaterialMasterSyncService.sync(reqList(500));
        Test.stopTest();

        System.assert(mock.lastEndpoint != null && mock.lastEndpoint.contains('$top=200'),
            'maxFetch>200 must be clamped to 200 to protect callout budget. Endpoint: '
            + mock.lastEndpoint);
        System.assert(!mock.lastEndpoint.contains('$top=500'),
            'Endpoint must NOT echo the original 500 value');
    }

    @IsTest
    static void sync_401_isLoggedAsAuthError_noProductsChanged() {
        SapMatMasterMock401 mock = new SapMatMasterMock401();
        Integer productsBefore = [SELECT COUNT() FROM Product2];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapMaterialMasterSyncService.Result> results =
            SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Error', results[0].status, '401 must map to Error');
        System.assert(results[0].message != null && results[0].message.contains('401'),
            'Error message must include HTTP status. Got: ' + results[0].message);

        Integer productsAfter = [SELECT COUNT() FROM Product2];
        System.assertEquals(productsBefore, productsAfter,
            'No Product2 rows must be created / deleted on auth failure');
    }

    @IsTest
    static void sync_500_isLoggedAsDownstreamCritical() {
        SapMatMasterMock500 mock = new SapMatMasterMock500();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapMaterialMasterSyncService.Result> results =
            SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        System.assertEquals('Error', results[0].status, '500 must map to Error');
        System.assert(results[0].message.contains('500'),
            'Error message must include the 500 status code. Got: ' + results[0].message);
        System.assert(results[0].message.contains('SAP downstream'),
            'Message must surface the SAP body so operators can triage. Got: '
            + results[0].message);
        System.assertEquals(0, results[0].createdCount);
        System.assertEquals(0, results[0].updatedCount);
    }

    @IsTest
    static void sync_calloutException_isHandledGracefully_noException() {
        // Assert-by-not-throwing: the service must catch and translate to Error.
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SapMatMasterMockTimeout());
        List<SapMaterialMasterSyncService.Result> results =
            SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Exception must not abort — one Result still returned');
        System.assertEquals('Error', results[0].status, 'Timeout must map to Error');
        System.assert(results[0].message != null
            && results[0].message.containsIgnoreCase('CalloutException'),
            'Error message must include the exception type name. Got: ' + results[0].message);
    }

    @IsTest
    static void sync_missingSapConfig_throwsOrLogsCleanly() {
        // Blank the Base URL — guard should fire before any HTTP work.
        SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
        cfg.API_Base_URL__c = null;
        cfg.API_Key__c      = null;
        upsert cfg;

        SapMatMasterMock200 mock = new SapMatMasterMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapMaterialMasterSyncService.Result> results =
            SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Guard should still produce one Result');
        System.assertEquals('Error', results[0].status,
            'Missing config must map to Error');
        System.assert(results[0].message != null
            && results[0].message.contains('SAP_Config__c'),
            'Error message must call out the missing custom setting. Got: '
            + results[0].message);
        System.assertEquals(0, mock.callCount,
            'Guard must fire BEFORE the HTTP callout');
    }

    @IsTest
    static void sync_pickName_fallsBackFrom_FullName_to_OldID_to_MaterialNumber() {
        // MAT-300 has ProductOldID='OLD-300' (no description).
        // MAT-400 has neither (fall back all the way to material number).
        SapMatMasterMockFallbacks mock = new SapMatMasterMockFallbacks();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        List<SapMaterialMasterSyncService.Result> results =
            SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        System.assertEquals('Success', results[0].status);
        System.assertEquals(2, results[0].createdCount, 'Both fallback rows are new');

        Product2 mat300 = [
            SELECT Name, SAP_Product_Description__c
            FROM Product2
            WHERE SAP_Material_Number__c = 'MAT-300'
            LIMIT 1
        ];
        System.assertEquals('[SAP] OLD-300', mat300.Name,
            'When ProductDescription blank, Name must fall back to ProductOldID');
        System.assertEquals('OLD-300', mat300.SAP_Product_Description__c,
            'SAP_Product_Description__c must also fall back to ProductOldID');

        Product2 mat400 = [
            SELECT Name, SAP_Product_Description__c
            FROM Product2
            WHERE SAP_Material_Number__c = 'MAT-400'
            LIMIT 1
        ];
        System.assertEquals('[SAP] MAT-400', mat400.Name,
            'When neither description nor OldID, Name must fall back to material number');
        System.assertEquals('MAT-400', mat400.SAP_Product_Description__c,
            'SAP_Product_Description__c must also fall back to material number');
    }

    @IsTest
    static void sync_productDescription_extraction() {
        SapMatMasterMock200 mock = new SapMatMasterMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        // MAT-100 (updated) — description refreshed.
        Product2 mat100 = [
            SELECT SAP_Product_Description__c
            FROM Product2
            WHERE SAP_Material_Number__c = 'MAT-100' LIMIT 1
        ];
        System.assertEquals('Laptop Pro 15', mat100.SAP_Product_Description__c,
            'MAT-100 description must be refreshed from SAP payload');

        // MAT-200 (created) — description populated from SAP payload.
        Product2 mat200 = [
            SELECT SAP_Product_Description__c
            FROM Product2
            WHERE SAP_Material_Number__c = 'MAT-200' LIMIT 1
        ];
        System.assertEquals('External SSD 1TB', mat200.SAP_Product_Description__c,
            'MAT-200 description must be populated on create');
    }

    @IsTest
    static void sync_endpointConstruction_containsBaseUrl_and_ODataFormat_json() {
        SapMatMasterMock200 mock = new SapMatMasterMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapMaterialMasterSyncService.sync(reqList(25));
        Test.stopTest();

        System.assertNotEquals(null, mock.lastEndpoint, 'Endpoint must have been captured');
        System.assert(mock.lastEndpoint.startsWith(BASE_URL),
            'Endpoint must start with SAP_Config__c.API_Base_URL__c. Got: ' + mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('/s4hanacloud/sap/opu/odata/sap/API_PRODUCT_SRV/A_Product'),
            'Endpoint must include the OData v2 API_PRODUCT_SRV path. Got: ' + mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('$format=json'),
            'Endpoint must request JSON format. Got: ' + mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('$top=25'),
            'Endpoint must carry the $top query param. Got: ' + mock.lastEndpoint);
        System.assertEquals('GET', mock.lastMethod, 'Method must be GET');
    }

    @IsTest
    static void sync_authHeader_APIKey_isSet() {
        SapMatMasterMock200 mock = new SapMatMasterMock200();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, mock);
        SapMaterialMasterSyncService.sync(reqList(null));
        Test.stopTest();

        System.assertEquals(API_KEY, mock.lastHeaders.get('APIKey'),
            'APIKey header must be set to SAP_Config__c.API_Key__c (SAP API Hub convention — NOT Bearer)');
        System.assertEquals('application/json', mock.lastHeaders.get('Accept'),
            'Accept must be application/json');
        System.assertEquals('identity', mock.lastHeaders.get('Accept-Encoding'),
            'Accept-Encoding must be identity to avoid gzip decompression issues on Apex Http');
    }
}

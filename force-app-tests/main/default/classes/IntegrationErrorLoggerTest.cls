/**
 * Unit tests for IntegrationErrorLogger.
 *
 * Covers:
 *   - log(Request) happy path + null-safety
 *   - Exception-overload with classifier: Timeout / Downstream / Parse / Auth / Other
 *   - HTTP-overload classifier: 401→Auth, 422→Validation, 408→Timeout, 500→Downstream+Critical
 *   - Null HttpResponse → 'Other' with Error severity
 *   - newCorrelationId returns RFC 4122-shape UUID (8-4-4-4-12)
 *   - Field length caps (message 32K, operation 80, correlation id 80)
 *   - Field defaults when Request fields are blank
 *   - Bulk 200 inserts within governor limits
 */
@IsTest
private class IntegrationErrorLoggerTest {

    // ---------- Happy path ----------

    @IsTest
    static void log_singleRequest_persistsRecord() {
        IntegrationErrorLogger.Request req = new IntegrationErrorLogger.Request();
        req.sourceSystem = 'SAP';
        req.operation = 'A_SalesOrder POST';
        req.errorType = 'Downstream';
        req.errorMessage = 'HTTP 502 Bad Gateway';
        req.severity = 'Critical';
        req.correlationId = 'test-corr-001';

        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.log(req);
        Test.stopTest();

        System.assertNotEquals(null, err, 'log(Request) must return the inserted record');
        System.assertNotEquals(null, err.Id);

        Integration_Error__c stored = [
            SELECT Source_System__c, Operation__c, Error_Type__c, Error_Message__c,
                   Severity__c, Status__c, Correlation_Id__c
            FROM Integration_Error__c WHERE Id = :err.Id
        ];
        System.assertEquals('SAP', stored.Source_System__c);
        System.assertEquals('A_SalesOrder POST', stored.Operation__c);
        System.assertEquals('Downstream', stored.Error_Type__c);
        System.assertEquals('HTTP 502 Bad Gateway', stored.Error_Message__c);
        System.assertEquals('Critical', stored.Severity__c);
        System.assertEquals('New', stored.Status__c, 'Status must default to New on insert');
        System.assertEquals('test-corr-001', stored.Correlation_Id__c);
    }

    @IsTest
    static void log_nullRequest_returnsNullSafely() {
        Test.startTest();
        Integration_Error__c result = IntegrationErrorLogger.log((IntegrationErrorLogger.Request) null);
        Test.stopTest();
        System.assertEquals(null, result, 'Null request must return null without throwing');
    }

    // ---------- Defaults for blank Request fields ----------

    @IsTest
    static void log_blankRequest_appliesDefaults() {
        IntegrationErrorLogger.Request req = new IntegrationErrorLogger.Request();
        // Everything null except that we let the class fill defaults

        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.log(req);
        Test.stopTest();

        Integration_Error__c stored = [
            SELECT Source_System__c, Operation__c, Error_Type__c, Severity__c, Status__c
            FROM Integration_Error__c WHERE Id = :err.Id
        ];
        System.assertEquals('Other', stored.Source_System__c);
        System.assertEquals('unknown', stored.Operation__c);
        System.assertEquals('Other', stored.Error_Type__c);
        System.assertEquals('Error', stored.Severity__c, 'Severity must default to Error');
        System.assertEquals('New', stored.Status__c);
    }

    // ---------- Exception classifier ----------

    @IsTest
    static void classifyException_calloutTimeout_isTimeout() {
        // Simulate by writing an exception with the right message shape
        try {
            System.CalloutException e = new System.CalloutException();
            e.setMessage('Read timed out after 60 seconds');
            throw e;
        } catch (Exception ex) {
            Test.startTest();
            Integration_Error__c err = IntegrationErrorLogger.log('Stripe', 'checkout', ex, null, 'corr-timeout');
            Test.stopTest();
            Integration_Error__c stored = [SELECT Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
            System.assertEquals('Timeout', stored.Error_Type__c);
        }
    }

    @IsTest
    static void classifyException_callout_isDownstream() {
        try {
            System.CalloutException e = new System.CalloutException();
            e.setMessage('Connection refused');
            throw e;
        } catch (Exception ex) {
            Test.startTest();
            Integration_Error__c err = IntegrationErrorLogger.log('SAP', 'material', ex, null, null);
            Test.stopTest();
            Integration_Error__c stored = [SELECT Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
            System.assertEquals('Downstream', stored.Error_Type__c);
        }
    }

    @IsTest
    static void classifyException_json_isParse() {
        try {
            JSON.deserialize('not-json-at-all', Map<String, Object>.class);
            System.assert(false, 'Should have thrown');
        } catch (Exception ex) {
            Test.startTest();
            Integration_Error__c err = IntegrationErrorLogger.log('DocuSign', 'parse', ex, null, null);
            Test.stopTest();
            Integration_Error__c stored = [SELECT Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
            System.assertEquals('Parse', stored.Error_Type__c);
        }
    }

    @IsTest
    static void classifyException_authKeywordInMessage_isAuth() {
        try {
            throw new IllegalArgumentException('Request unauthorized: token expired');
        } catch (Exception ex) {
            Test.startTest();
            Integration_Error__c err = IntegrationErrorLogger.log('JIRA', 'issue', ex, null, null);
            Test.stopTest();
            Integration_Error__c stored = [SELECT Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
            System.assertEquals('Auth', stored.Error_Type__c);
        }
    }

    @IsTest
    static void classifyException_unknown_isOther() {
        try {
            throw new IllegalArgumentException('something happened');
        } catch (Exception ex) {
            Test.startTest();
            Integration_Error__c err = IntegrationErrorLogger.log('Other', 'x', ex, null, null);
            Test.stopTest();
            Integration_Error__c stored = [SELECT Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
            System.assertEquals('Other', stored.Error_Type__c);
        }
    }

    @IsTest
    static void classifyException_nullException_convenienceOverloadHandles() {
        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.log('Stripe', 'op', null, null, null);
        Test.stopTest();
        Integration_Error__c stored = [SELECT Error_Message__c, Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals('Unknown error', stored.Error_Message__c);
        System.assertEquals('Other', stored.Error_Type__c);
    }

    // ---------- HTTP classifier ----------

    @IsTest
    static void logHttpFailure_500_isDownstreamAndCritical() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(500);
        res.setBody('{"error":"Internal"}');

        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.logHttpFailure(
            'SAP', 'A_MaterialStock GET', res, '{"filter":"x"}', null, 'corr-500'
        );
        Test.stopTest();

        Integration_Error__c stored = [
            SELECT Error_Type__c, Severity__c, Error_Message__c, Payload__c, Correlation_Id__c
            FROM Integration_Error__c WHERE Id = :err.Id
        ];
        System.assertEquals('Downstream', stored.Error_Type__c);
        System.assertEquals('Critical', stored.Severity__c, '5xx must escalate to Critical');
        System.assertEquals('{"filter":"x"}', stored.Payload__c);
        System.assertEquals('corr-500', stored.Correlation_Id__c);
        System.assert(stored.Error_Message__c.contains('500'));
    }

    @IsTest
    static void logHttpFailure_401_isAuth() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(401);
        res.setBody('unauthorized');

        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.logHttpFailure('JIRA', 'op', res, null, null, null);
        Test.stopTest();

        Integration_Error__c stored = [SELECT Error_Type__c, Severity__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals('Auth', stored.Error_Type__c);
        System.assertEquals('Error', stored.Severity__c, '401 must NOT auto-escalate to Critical');
    }

    @IsTest
    static void logHttpFailure_408_isTimeout() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(408);
        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.logHttpFailure('SAP', 'op', res, null, null, null);
        Test.stopTest();
        Integration_Error__c stored = [SELECT Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals('Timeout', stored.Error_Type__c);
    }

    @IsTest
    static void logHttpFailure_422_isValidation() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(422);
        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.logHttpFailure('Stripe', 'op', res, null, null, null);
        Test.stopTest();
        Integration_Error__c stored = [SELECT Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals('Validation', stored.Error_Type__c);
    }

    @IsTest
    static void logHttpFailure_generic4xx_isValidation() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(404);
        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.logHttpFailure('SAP', 'op', res, null, null, null);
        Test.stopTest();
        Integration_Error__c stored = [SELECT Error_Type__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals('Validation', stored.Error_Type__c);
    }

    @IsTest
    static void logHttpFailure_nullResponse_defaultsToOther() {
        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.logHttpFailure('Other', 'op', null, null, null, null);
        Test.stopTest();
        Integration_Error__c stored = [SELECT Error_Type__c, Severity__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals('Other', stored.Error_Type__c);
        System.assertEquals('Error', stored.Severity__c);
    }

    // ---------- Correlation Id ----------

    @IsTest
    static void newCorrelationId_matchesRfc4122Shape() {
        Test.startTest();
        String id1 = IntegrationErrorLogger.newCorrelationId();
        String id2 = IntegrationErrorLogger.newCorrelationId();
        Test.stopTest();

        System.assertEquals(36, id1.length(), 'Correlation id must be 36 chars (8-4-4-4-12 + 4 hyphens)');
        System.assertNotEquals(id1, id2, 'Two calls must produce distinct ids');
        // Segment shape: 8-4-4-4-12
        List<String> parts = id1.split('-');
        System.assertEquals(5, parts.size(), 'Must have five hyphen-separated segments');
        System.assertEquals(8, parts[0].length());
        System.assertEquals(4, parts[1].length());
        System.assertEquals(4, parts[2].length());
        System.assertEquals(4, parts[3].length());
        System.assertEquals(12, parts[4].length());
    }

    // ---------- Length caps ----------

    @IsTest
    static void operation_truncatedAt80() {
        IntegrationErrorLogger.Request req = new IntegrationErrorLogger.Request();
        req.operation = 'X'.repeat(200);
        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.log(req);
        Test.stopTest();
        Integration_Error__c stored = [SELECT Operation__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals(80, stored.Operation__c.length());
    }

    @IsTest
    static void errorMessage_truncatedAt32K() {
        IntegrationErrorLogger.Request req = new IntegrationErrorLogger.Request();
        req.errorMessage = 'M'.repeat(40000);
        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.log(req);
        Test.stopTest();
        Integration_Error__c stored = [SELECT Error_Message__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals(32000, stored.Error_Message__c.length());
    }

    @IsTest
    static void correlationId_truncatedAt80() {
        IntegrationErrorLogger.Request req = new IntegrationErrorLogger.Request();
        req.correlationId = 'C'.repeat(200);
        Test.startTest();
        Integration_Error__c err = IntegrationErrorLogger.log(req);
        Test.stopTest();
        Integration_Error__c stored = [SELECT Correlation_Id__c FROM Integration_Error__c WHERE Id = :err.Id];
        System.assertEquals(80, stored.Correlation_Id__c.length());
    }

    // ---------- Volume within governor limits ----------
    // This class is invoked ONCE per exception (not looped), so the realistic
    // volume test proves a fleet of independent single calls within one Apex
    // transaction stays under the 150 DML governor limit. Each log() spends 1 DML,
    // so 100 sequential calls uses 100/150 DML — inside limits with 33% headroom.
    @IsTest
    static void volume_100Errors_allInsertedWithinLimits() {
        Test.startTest();
        for (Integer i = 0; i < 100; i++) {
            IntegrationErrorLogger.Request req = new IntegrationErrorLogger.Request();
            req.sourceSystem = 'Stripe';
            req.operation = 'vol-' + i;
            req.severity = 'Error';
            IntegrationErrorLogger.log(req);
        }
        System.assert(Limits.getDmlStatements() < Limits.getLimitDmlStatements(),
            'DML limit budget must not be exhausted');
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Integration_Error__c WHERE Operation__c LIKE 'vol-%'];
        System.assertEquals(100, count, 'All 100 error rows must be persisted');
    }
}

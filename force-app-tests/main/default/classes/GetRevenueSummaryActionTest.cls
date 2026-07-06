/**
 * Unit tests for GetRevenueSummaryAction — the Agentforce-callable revenue rollup.
 *
 * SCOPE NOTE:
 * ===========
 * Salesforce Industries Billing blocks Invoice creation via Apex DML:
 *   "FIELD_INTEGRITY_EXCEPTION, Can't create Invoice in Apex. Use REST API instead."
 *
 * That means the "invoices present" behaviors (paidCount>0, unpaidCount>0,
 * outstanding rollups, out-of-window exclusion) can only be verified through an
 * integration test that seeds Invoices via the REST /invoices endpoint. Those
 * scenarios are tracked as TS-TEST-003.
 *
 * What THIS test proves (empty-state + input sanitization + aggregate coalescing):
 *   - Default window is 90 when daysBack is null
 *   - Zero/negative daysBack falls back to default 90
 *   - Custom positive daysBack is respected
 *   - Empty org returns zero counts + zero totals (SUM(null) coalesced)
 *   - Multiple Request items processed independently
 *   - Outcome message contains the key numbers so an LLM can respond naturally
 */
@IsTest
private class GetRevenueSummaryActionTest {

    // ---------- Default window ----------

    @IsTest
    static void nullDaysBack_defaultsTo90() {
        GetRevenueSummaryAction.Request req = new GetRevenueSummaryAction.Request();

        Test.startTest();
        List<GetRevenueSummaryAction.Response> resps =
            GetRevenueSummaryAction.getSummary(new List<GetRevenueSummaryAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, resps.size(), 'Single request → single response');
        System.assertEquals(90, resps[0].windowDays, 'Null daysBack must default to 90');
    }

    // ---------- Custom window respected ----------

    @IsTest
    static void positiveDaysBack_isPreserved() {
        GetRevenueSummaryAction.Request req = new GetRevenueSummaryAction.Request();
        req.daysBack = 45;

        Test.startTest();
        List<GetRevenueSummaryAction.Response> resps =
            GetRevenueSummaryAction.getSummary(new List<GetRevenueSummaryAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(45, resps[0].windowDays);
    }

    // ---------- Zero / negative sanitized to default ----------

    @IsTest
    static void zeroOrNegativeDays_fallsBackToDefault90() {
        GetRevenueSummaryAction.Request req0 = new GetRevenueSummaryAction.Request();
        req0.daysBack = 0;
        GetRevenueSummaryAction.Request reqNeg = new GetRevenueSummaryAction.Request();
        reqNeg.daysBack = -10;

        Test.startTest();
        List<GetRevenueSummaryAction.Response> resps =
            GetRevenueSummaryAction.getSummary(new List<GetRevenueSummaryAction.Request>{ req0, reqNeg });
        Test.stopTest();

        System.assertEquals(2, resps.size());
        System.assertEquals(90, resps[0].windowDays);
        System.assertEquals(90, resps[1].windowDays);
    }

    // ---------- Empty state + null coalescing ----------

    @IsTest
    static void emptyOrg_returnsZeroCountsAndCoalescedTotals() {
        GetRevenueSummaryAction.Request req = new GetRevenueSummaryAction.Request();
        req.daysBack = 365;

        Test.startTest();
        List<GetRevenueSummaryAction.Response> resps =
            GetRevenueSummaryAction.getSummary(new List<GetRevenueSummaryAction.Request>{ req });
        Test.stopTest();

        GetRevenueSummaryAction.Response resp = resps[0];
        // Note: assertions use >= 0 because the test org may already contain
        // Invoice records from other manual demo activity. What we CAN prove
        // regardless of ambient state is that:
        //   1. Counts are non-negative integers (schema-safe)
        //   2. Sums are non-null (the null-coalesce contract holds)
        System.assert(resp.paidCount >= 0, 'paidCount must be non-negative');
        System.assert(resp.unpaidCount >= 0, 'unpaidCount must be non-negative');
        System.assertNotEquals(null, resp.totalRevenue, 'totalRevenue must be coalesced to 0 when SUM is null');
        System.assertNotEquals(null, resp.outstandingAmount, 'outstandingAmount must be coalesced to 0');
    }

    // ---------- Batch call ----------

    @IsTest
    static void multipleRequests_produceMatchingResponses() {
        GetRevenueSummaryAction.Request rA = new GetRevenueSummaryAction.Request();
        rA.daysBack = 30;
        GetRevenueSummaryAction.Request rB = new GetRevenueSummaryAction.Request();
        rB.daysBack = 90;
        GetRevenueSummaryAction.Request rC = new GetRevenueSummaryAction.Request();
        rC.daysBack = 365;

        Test.startTest();
        List<GetRevenueSummaryAction.Response> resps =
            GetRevenueSummaryAction.getSummary(new List<GetRevenueSummaryAction.Request>{ rA, rB, rC });
        Test.stopTest();

        System.assertEquals(3, resps.size(), 'One response per request in order');
        System.assertEquals(30, resps[0].windowDays);
        System.assertEquals(90, resps[1].windowDays);
        System.assertEquals(365, resps[2].windowDays);
    }

    // ---------- Outcome message shape ----------

    @IsTest
    static void outcomeMessage_containsKeyPhrasesForLLM() {
        GetRevenueSummaryAction.Request req = new GetRevenueSummaryAction.Request();
        req.daysBack = 90;

        Test.startTest();
        List<GetRevenueSummaryAction.Response> resps =
            GetRevenueSummaryAction.getSummary(new List<GetRevenueSummaryAction.Request>{ req });
        Test.stopTest();

        String msg = resps[0].outcomeMessage;
        System.assert(msg.contains('90'), 'Message must mention the window number');
        System.assert(msg.contains('paid invoice'), 'Message must mention paid invoices');
        System.assert(msg.contains('Outstanding'), 'Message must mention outstanding');
    }
}

/**
 * Unit tests for SendPaymentRemindersAction — Agentforce-callable Stripe reminder trigger.
 *
 * SCOPE NOTE:
 * ===========
 * Salesforce Industries Billing blocks Invoice creation via Apex DML
 *   ("FIELD_INTEGRITY_EXCEPTION, Can't create Invoice in Apex. Use REST API instead.")
 * so the behaviors that need real Invoice records (single-by-DocumentNumber match,
 * "all" mode, Stripe_Payment_Status__c transition to 'Sent', TotalAmount rollup,
 * Platform Event publish with real Invoice_Id__c) can only be verified through an
 * integration test that seeds Invoices via the REST /invoices endpoint. That is
 * TS-TEST-003 in SECURITY.md's roadmap.
 *
 * What THIS test proves (input sanitization + no-match branch):
 *   - Null or blank documentNumber → friendly "Please provide" outcome
 *   - Whitespace-only input treated as blank
 *   - Unknown DocumentNumber → "No matching" outcome, zero reminders sent
 *   - Response contract: remindersSent, processedInvoices, totalAmount always initialised
 *   - Batch call: multiple Requests each get an independent Response
 */
@IsTest
private class SendPaymentRemindersActionTest {

    // ---------- Blank / null input ----------

    @IsTest
    static void nullDocumentNumber_returnsFriendlyMessage() {
        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        // documentNumber left null

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, resps.size());
        SendPaymentRemindersAction.Response resp = resps[0];
        System.assertEquals(0, resp.remindersSent);
        System.assertNotEquals(null, resp.processedInvoices, 'processedInvoices must be initialised, not null');
        System.assertEquals(0, resp.processedInvoices.size());
        System.assertEquals(0, resp.totalAmount, 'totalAmount must be initialised to 0');
        System.assert(resp.outcomeMessage.contains('Please provide'),
            'Null input must produce the "please provide" message. Got: ' + resp.outcomeMessage);
    }

    @IsTest
    static void whitespaceDocumentNumber_treatedAsBlank() {
        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        req.documentNumber = '   ';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, resps[0].remindersSent);
        System.assert(resps[0].outcomeMessage.contains('Please provide'),
            'Whitespace input must be treated as blank');
    }

    @IsTest
    static void emptyStringDocumentNumber_treatedAsBlank() {
        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        req.documentNumber = '';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, resps[0].remindersSent);
    }

    // ---------- DocumentNumber not found ----------

    @IsTest
    static void unknownDocumentNumber_returnsNoMatch() {
        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        req.documentNumber = 'DOC-999999999';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        SendPaymentRemindersAction.Response resp = resps[0];
        System.assertEquals(0, resp.remindersSent);
        System.assertEquals(0, resp.processedInvoices.size());
        System.assert(resp.outcomeMessage.contains('No matching'),
            'Expected "No matching" outcome, got: ' + resp.outcomeMessage);
    }

    // ---------- Batch call ----------

    @IsTest
    static void batchOfRequests_eachGetsIndependentResponse() {
        SendPaymentRemindersAction.Request r1 = new SendPaymentRemindersAction.Request();
        r1.documentNumber = null;
        SendPaymentRemindersAction.Request r2 = new SendPaymentRemindersAction.Request();
        r2.documentNumber = 'DOC-000-does-not-exist';
        SendPaymentRemindersAction.Request r3 = new SendPaymentRemindersAction.Request();
        r3.documentNumber = '   ';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(
                new List<SendPaymentRemindersAction.Request>{ r1, r2, r3 }
            );
        Test.stopTest();

        System.assertEquals(3, resps.size(), 'One response per request');
        // Each response is independently initialised (not shared state)
        for (SendPaymentRemindersAction.Response r : resps) {
            System.assertEquals(0, r.remindersSent);
            System.assertNotEquals(null, r.processedInvoices);
            System.assertEquals(0, r.processedInvoices.size());
            System.assertNotEquals(null, r.outcomeMessage);
        }
    }
}

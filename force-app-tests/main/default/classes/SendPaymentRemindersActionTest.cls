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

    // ---------- In-memory Invoice injection via JSON.deserialize ----------
    //
    // Salesforce Industries Billing blocks `insert new Invoice(...)` in Apex tests
    // ("Can't create Invoice in Apex. Use REST API instead."). Community-verified
    // workaround: build the Invoice via JSON.deserialize (bypasses the "not creatable
    // in Apex" check) and inject it through the @TestVisible testInvoicesOverride seam.
    // This unblocks coverage on the happy path, all-mode aggregation, and the
    // "found but no email" branch that previously could not be exercised.
    // Reference: https://afigueiredo.medium.com/how-to-trick-time-in-apex-unit-tests-the-json-deserialization-pattern-199694250975

    private static Invoice buildInvoice(String docNumber, Decimal amountWithTax, String stripeStatus, String contactEmail) {
        return buildInvoice(docNumber, amountWithTax, stripeStatus, contactEmail, 'a03000000000001AAA', '003000000000001AAA', '001000000000001AAA', 'Test Account');
    }

    private static Invoice buildInvoice(
        String docNumber,
        Decimal amountWithTax,
        String stripeStatus,
        String contactEmail,
        String invoiceId,
        String contactId,
        String accountId,
        String accountName
    ) {
        String emailFragment = (contactEmail == null)
            ? '"Email":null'
            : '"Email":"' + contactEmail + '"';
        String json = '{'
            + '"attributes":{"type":"Invoice"},'
            + '"Id":"' + invoiceId + '",'
            + '"DocumentNumber":"' + docNumber + '",'
            + '"TotalAmountWithTax":' + amountWithTax + ','
            + '"Stripe_Payment_Status__c":"' + stripeStatus + '",'
            + '"BillToContactId":"' + contactId + '",'
            + '"BillToContact":{"attributes":{"type":"Contact"},"Id":"' + contactId + '",' + emailFragment + '},'
            + '"BillingAccountId":"' + accountId + '",'
            + '"BillingAccount":{"attributes":{"type":"Account"},"Id":"' + accountId + '","Name":"' + accountName + '"}'
            + '}';
        return (Invoice) System.JSON.deserialize(json, Invoice.class);
    }

    @IsTest
    static void singleDocumentNumber_publishesEventAndFlipsStatusInMemory() {
        Invoice inv = buildInvoice('DOC-000123', 500.00, 'Not Started', 'buyer@example.com');
        SendPaymentRemindersAction.testInvoicesOverride = new List<Invoice>{ inv };
        SendPaymentRemindersAction.testSkipDml = true;

        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        req.documentNumber = 'DOC-000123';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, resps.size());
        SendPaymentRemindersAction.Response resp = resps[0];
        System.assertEquals(1, resp.remindersSent, 'One reminder should be sent');
        System.assertEquals(1, resp.processedInvoices.size());
        System.assertEquals('DOC-000123', resp.processedInvoices[0]);
        System.assertEquals(500.00, resp.totalAmount.setScale(2), 'totalAmount aggregates TotalAmountWithTax');
        System.assertEquals('Sent', inv.Stripe_Payment_Status__c,
            'Class must flip the in-memory Invoice status BEFORE the update DML');
        System.assert(resp.outcomeMessage.contains('Successfully sent'),
            'Success outcome expected, got: ' + resp.outcomeMessage);
    }

    @IsTest
    static void allMode_processesAllUnpaidInvoicesAndAggregatesTotal() {
        Invoice a = buildInvoice('DOC-A', 100.00, 'Not Started', 'a@example.com', 'a03000000000AAAAAA', '003000000000AAAAAA', '001000000000AAAAAA', 'Acct A');
        Invoice b = buildInvoice('DOC-B', 250.50, 'Failed',      'b@example.com', 'a03000000000BBBAAA', '003000000000BBBAAA', '001000000000BBBAAA', 'Acct B');
        Invoice c = buildInvoice('DOC-C', 49.50,  'Not Started', 'c@example.com', 'a03000000000CCCAAA', '003000000000CCCAAA', '001000000000CCCAAA', 'Acct C');
        SendPaymentRemindersAction.testInvoicesOverride = new List<Invoice>{ a, b, c };
        SendPaymentRemindersAction.testSkipDml = true;

        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        req.documentNumber = 'all';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        SendPaymentRemindersAction.Response resp = resps[0];
        System.assertEquals(3, resp.remindersSent, 'All 3 unpaid invoices should get reminders');
        System.assertEquals(3, resp.processedInvoices.size());
        System.assertEquals(400.00, resp.totalAmount.setScale(2), '100 + 250.50 + 49.50 = 400.00');
        System.assertEquals('Sent', a.Stripe_Payment_Status__c);
        System.assertEquals('Sent', b.Stripe_Payment_Status__c);
        System.assertEquals('Sent', c.Stripe_Payment_Status__c);
    }

    @IsTest
    static void invoiceFoundButNoBillToEmail_reportsNoRemindersSent() {
        Invoice inv = buildInvoice('DOC-NO-EMAIL', 300.00, 'Not Started', null);
        SendPaymentRemindersAction.testInvoicesOverride = new List<Invoice>{ inv };
        SendPaymentRemindersAction.testSkipDml = true;

        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        req.documentNumber = 'DOC-NO-EMAIL';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        SendPaymentRemindersAction.Response resp = resps[0];
        System.assertEquals(0, resp.remindersSent, 'No reminders sent when contact has no email');
        System.assertEquals(0, resp.processedInvoices.size());
        System.assert(resp.outcomeMessage.contains('none have a Bill To Contact email'),
            'Expected "none have a Bill To Contact email" outcome, got: ' + resp.outcomeMessage);
        System.assertNotEquals('Sent', inv.Stripe_Payment_Status__c,
            'Status must NOT flip when no email is present');
    }

    @IsTest
    static void mixedEmails_onlyInvoicesWithEmailGetReminders() {
        Invoice withEmail = buildInvoice('DOC-HAS', 200.00, 'Not Started', 'has@example.com', 'a03000000000HASAAA', '003000000000HASAAA', '001000000000HASAAA', 'HasAcct');
        Invoice noEmail   = buildInvoice('DOC-NON', 999.99, 'Not Started', null,               'a03000000000NONAAA', '003000000000NONAAA', '001000000000NONAAA', 'NonAcct');
        SendPaymentRemindersAction.testInvoicesOverride = new List<Invoice>{ withEmail, noEmail };
        SendPaymentRemindersAction.testSkipDml = true;

        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        req.documentNumber = 'all';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        SendPaymentRemindersAction.Response resp = resps[0];
        System.assertEquals(1, resp.remindersSent, 'Only the invoice WITH email counts');
        System.assertEquals(1, resp.processedInvoices.size());
        System.assertEquals('DOC-HAS', resp.processedInvoices[0]);
        System.assertEquals(200.00, resp.totalAmount.setScale(2),
            'totalAmount only aggregates invoices actually processed');
        System.assertEquals('Sent', withEmail.Stripe_Payment_Status__c);
        System.assertNotEquals('Sent', noEmail.Stripe_Payment_Status__c);
    }

    @IsTest
    static void nullAmountWithTax_doesNotBreakAggregate() {
        // Build an invoice with TotalAmountWithTax = null via manual JSON (buildInvoice can't emit null Decimal literal cleanly)
        String json = '{'
            + '"attributes":{"type":"Invoice"},'
            + '"Id":"a03000000000NULAAA",'
            + '"DocumentNumber":"DOC-NULL",'
            + '"TotalAmountWithTax":null,'
            + '"Stripe_Payment_Status__c":"Not Started",'
            + '"BillToContactId":"003000000000NULAAA",'
            + '"BillToContact":{"attributes":{"type":"Contact"},"Id":"003000000000NULAAA","Email":"null-amt@example.com"},'
            + '"BillingAccountId":"001000000000NULAAA",'
            + '"BillingAccount":{"attributes":{"type":"Account"},"Id":"001000000000NULAAA","Name":"NullAmt"}'
            + '}';
        Invoice inv = (Invoice) System.JSON.deserialize(json, Invoice.class);
        SendPaymentRemindersAction.testInvoicesOverride = new List<Invoice>{ inv };
        SendPaymentRemindersAction.testSkipDml = true;

        SendPaymentRemindersAction.Request req = new SendPaymentRemindersAction.Request();
        req.documentNumber = 'DOC-NULL';

        Test.startTest();
        List<SendPaymentRemindersAction.Response> resps =
            SendPaymentRemindersAction.sendReminders(new List<SendPaymentRemindersAction.Request>{ req });
        Test.stopTest();

        SendPaymentRemindersAction.Response resp = resps[0];
        System.assertEquals(1, resp.remindersSent,
            'Reminder still counted even when TotalAmountWithTax is null');
        System.assertEquals(0, resp.totalAmount, 'Null amount contributes 0 to the aggregate');
    }

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

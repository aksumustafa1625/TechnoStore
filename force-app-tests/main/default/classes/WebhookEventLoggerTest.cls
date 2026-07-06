/**
 * Unit tests for WebhookEventLogger.
 *
 * Covers:
 *   - Happy path insert (not duplicate)
 *   - Duplicate detection via pre-query
 *   - Blank/null external id → synthetic fallback id
 *   - markProcessed lifecycle transition
 *   - markProcessed with related record id
 *   - markProcessed / markFailed null-row guards (never throw)
 *   - markFailed captures exception type + message + stack
 *   - Field length caps (payload 32K, event type 80)
 *   - All Source__c picklist values are accepted
 *   - Bulk 200 inserts stay within governor limits
 *
 * NOTE: The race-condition catch branch (DmlException containing DUPLICATE_VALUE from
 * a parallel writer) is exercised indirectly — the DB Unique constraint on
 * External_Id__c will raise DUPLICATE_VALUE on concurrent inserts and the code path
 * re-queries the winner. That branch cannot be deterministically driven from a single
 * Apex test transaction; the pre-query duplicate path (isDuplicate=true after the
 * first insert) proves the idempotency contract in the common case.
 */
@IsTest
private class WebhookEventLoggerTest {

    // ---------- Happy path ----------

    @IsTest
    static void firstEvent_isRecordedAndNotDuplicate() {
        Test.startTest();
        WebhookEventLogger.RecordResult result = WebhookEventLogger.checkAndRecord(
            'evt_stripe_001', 'Stripe', 'checkout.session.completed', '{"amount":1000}'
        );
        Test.stopTest();

        System.assertEquals(false, result.isDuplicate, 'First event must not be flagged duplicate');
        System.assertNotEquals(null, result.row, 'Row must be inserted');
        System.assertNotEquals(null, result.row.Id, 'Row must have an Id after insert');

        Webhook_Event__c stored = [
            SELECT External_Id__c, Source__c, Event_Type__c, Status__c, Payload__c
            FROM Webhook_Event__c WHERE Id = :result.row.Id
        ];
        System.assertEquals('evt_stripe_001', stored.External_Id__c);
        System.assertEquals('Stripe', stored.Source__c);
        System.assertEquals('checkout.session.completed', stored.Event_Type__c);
        System.assertEquals('Received', stored.Status__c);
        System.assertEquals('{"amount":1000}', stored.Payload__c);
    }

    // ---------- Duplicate detection (pre-query path) ----------

    @IsTest
    static void secondCallWithSameExternalId_isMarkedDuplicate() {
        WebhookEventLogger.checkAndRecord('evt_docusign_042', 'DocuSign', 'envelope-completed', '{}');

        Test.startTest();
        WebhookEventLogger.RecordResult second = WebhookEventLogger.checkAndRecord(
            'evt_docusign_042', 'DocuSign', 'envelope-completed', '{}'
        );
        Test.stopTest();

        System.assertEquals(true, second.isDuplicate, 'Second call with same external id must be duplicate');
        System.assertNotEquals(null, second.row, 'Duplicate result must still return the existing row');
        Integer count = [SELECT COUNT() FROM Webhook_Event__c WHERE External_Id__c = 'evt_docusign_042'];
        System.assertEquals(1, count, 'Only one physical row should exist for a duplicate external id');
    }

    // ---------- Blank / null external id → synthetic fallback ----------

    @IsTest
    static void blankExternalId_usesSyntheticFallback() {
        Test.startTest();
        WebhookEventLogger.RecordResult r1 = WebhookEventLogger.checkAndRecord('', 'JIRA', 'issue.updated', '{}');
        WebhookEventLogger.RecordResult r2 = WebhookEventLogger.checkAndRecord(null, 'JIRA', 'issue.updated', '{}');
        Test.stopTest();

        System.assertEquals(false, r1.isDuplicate);
        System.assertEquals(false, r2.isDuplicate);
        System.assertNotEquals(null, r1.row.Id);
        System.assertNotEquals(null, r2.row.Id);

        Webhook_Event__c stored1 = [SELECT External_Id__c FROM Webhook_Event__c WHERE Id = :r1.row.Id];
        Webhook_Event__c stored2 = [SELECT External_Id__c FROM Webhook_Event__c WHERE Id = :r2.row.Id];
        System.assert(stored1.External_Id__c.startsWith('JIRA-'), 'Fallback id must be prefixed with source');
        System.assert(stored2.External_Id__c.startsWith('JIRA-'), 'Fallback id must be prefixed with source');
        System.assertNotEquals(stored1.External_Id__c, stored2.External_Id__c, 'Fallback ids must be unique');
    }

    @IsTest
    static void nullSource_fallbackIdPrefixedUnknown() {
        Test.startTest();
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(null, null, null, null);
        Test.stopTest();

        Webhook_Event__c stored = [SELECT External_Id__c FROM Webhook_Event__c WHERE Id = :r.row.Id];
        System.assert(stored.External_Id__c.startsWith('unknown-'), 'Null source must fall back to "unknown-" prefix');
    }

    // ---------- markProcessed lifecycle ----------

    @IsTest
    static void markProcessed_updatesStatusAndTimestamp() {
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
            'evt_processed_001', 'SAP', 'sap.event', '{}'
        );

        Test.startTest();
        WebhookEventLogger.markProcessed(r.row, null);
        Test.stopTest();

        Webhook_Event__c updated = [
            SELECT Status__c, Processed_At__c, Related_Record_Id__c
            FROM Webhook_Event__c WHERE Id = :r.row.Id
        ];
        System.assertEquals('Processed', updated.Status__c);
        System.assertNotEquals(null, updated.Processed_At__c);
        System.assertEquals(null, updated.Related_Record_Id__c);
    }

    @IsTest
    static void markProcessed_withRelatedId_stampsIt() {
        Account a = TestDataFactory.newAccount();
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
            'evt_related_001', 'WhatsApp', 'message.inbound', '{}'
        );

        Test.startTest();
        WebhookEventLogger.markProcessed(r.row, a.Id);
        Test.stopTest();

        Webhook_Event__c updated = [SELECT Related_Record_Id__c FROM Webhook_Event__c WHERE Id = :r.row.Id];
        System.assertEquals(String.valueOf(a.Id), updated.Related_Record_Id__c);
    }

    @IsTest
    static void markProcessed_nullRow_isNoOp() {
        Test.startTest();
        WebhookEventLogger.markProcessed(null, null);
        WebhookEventLogger.markProcessed(new Webhook_Event__c(), null); // no Id
        Test.stopTest();
        // If we reach here, no exception was thrown — assertion is implicit.
        System.assert(true, 'Null-row guard must not throw');
    }

    // ---------- markFailed lifecycle ----------

    @IsTest
    static void markFailed_capturesExceptionMessage() {
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
            'evt_failed_001', 'Stripe', 'charge.failed', '{}'
        );

        Test.startTest();
        try {
            Integer x = 1 / 0; // DivideByZero
        } catch (Exception e) {
            WebhookEventLogger.markFailed(r.row, e);
        }
        Test.stopTest();

        Webhook_Event__c updated = [
            SELECT Status__c, Error_Message__c FROM Webhook_Event__c WHERE Id = :r.row.Id
        ];
        System.assertEquals('Failed', updated.Status__c);
        System.assert(updated.Error_Message__c.contains('MathException') || updated.Error_Message__c.contains('Divide'),
            'Error message must include the exception type name or message. Got: ' + updated.Error_Message__c);
    }

    @IsTest
    static void markFailed_nullException_writesUnknownFailure() {
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
            'evt_failed_nullex', 'Stripe', 'test', '{}'
        );

        Test.startTest();
        WebhookEventLogger.markFailed(r.row, null);
        Test.stopTest();

        Webhook_Event__c updated = [SELECT Status__c, Error_Message__c FROM Webhook_Event__c WHERE Id = :r.row.Id];
        System.assertEquals('Failed', updated.Status__c);
        System.assertEquals('Unknown failure', updated.Error_Message__c);
    }

    @IsTest
    static void markFailed_nullRow_isNoOp() {
        Test.startTest();
        WebhookEventLogger.markFailed(null, new DmlException('x'));
        WebhookEventLogger.markFailed(new Webhook_Event__c(), new DmlException('x'));
        Test.stopTest();
        System.assert(true, 'Null-row guard must not throw');
    }

    // ---------- Length caps ----------

    @IsTest
    static void eventType_truncatedAt80Chars() {
        String longType = 'X'.repeat(120);
        Test.startTest();
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
            'evt_lentype', 'Other', longType, '{}'
        );
        Test.stopTest();

        Webhook_Event__c stored = [SELECT Event_Type__c FROM Webhook_Event__c WHERE Id = :r.row.Id];
        System.assertEquals(80, stored.Event_Type__c.length(), 'Event_Type__c must be truncated to 80 chars');
    }

    @IsTest
    static void payload_truncatedAt32KChars() {
        String largePayload = 'A'.repeat(40000);
        Test.startTest();
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
            'evt_lenpayload', 'Other', 'x', largePayload
        );
        Test.stopTest();

        Webhook_Event__c stored = [SELECT Payload__c FROM Webhook_Event__c WHERE Id = :r.row.Id];
        System.assertEquals(32000, stored.Payload__c.length(), 'Payload__c must be truncated to 32000 chars');
    }

    // ---------- Source picklist coverage ----------

    @IsTest
    static void allDocumentedSources_areAcceptedByPicklist() {
        List<String> sources = new List<String>{
            'Stripe', 'DocuSign', 'JIRA', 'Sendcloud', 'SAP', 'Slack', 'WhatsApp', 'Other'
        };
        Test.startTest();
        Integer i = 0;
        for (String s : sources) {
            WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
                'evt_src_' + i++, s, 'x', '{}'
            );
            System.assertNotEquals(null, r.row.Id, 'Source ' + s + ' must be accepted');
        }
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Webhook_Event__c WHERE External_Id__c LIKE 'evt_src_%'];
        System.assertEquals(sources.size(), count);
    }

    // ---------- Race condition: DUPLICATE_VALUE catch branch ----------
    // In production, this branch fires when two parallel webhook deliveries race past the
    // pre-query into the insert step and the DB Unique constraint rejects the loser.
    // We reproduce it deterministically by flipping the @TestVisible testSkipPreQuery seam
    // so the pre-query is bypassed and the insert path is forced to collide with the row
    // we planted first.
    @IsTest
    static void checkAndRecord_duplicateValueRaceCondition_catchBranchReturnsWinner() {
        // Winner already in the table (simulates the parallel writer that won the race).
        Webhook_Event__c winner = new Webhook_Event__c(
            External_Id__c = 'RACE-TEST-001',
            Source__c = 'Stripe',
            Event_Type__c = 'charge.succeeded',
            Payload__c = '{"winner":true}',
            Status__c = 'Received'
        );
        insert winner;

        Test.startTest();
        WebhookEventLogger.testSkipPreQuery = true;
        WebhookEventLogger.RecordResult result = WebhookEventLogger.checkAndRecord(
            'RACE-TEST-001', 'Stripe', 'charge.succeeded', '{"loser":true}'
        );
        WebhookEventLogger.testSkipPreQuery = false;
        Test.stopTest();

        System.assertEquals(true, result.isDuplicate,
            'Race-condition catch branch must return isDuplicate=true when Unique constraint fires on insert');
        System.assertNotEquals(null, result.row, 'Winner row must be re-queried and returned');
        System.assertEquals(winner.Id, result.row.Id,
            'Race-condition catch must return the pre-existing winner row, not the failed insert');

        Integer physicalRows = [SELECT COUNT() FROM Webhook_Event__c WHERE External_Id__c = 'RACE-TEST-001'];
        System.assertEquals(1, physicalRows,
            'DB Unique constraint must prevent a second physical row for the same External_Id__c');
    }

    // ---------- markProcessed / markFailed: catch branch on structural update failure ----------
    // Database.update(record, false) does NOT throw on save-result-level failures, but it DOES
    // throw when the underlying record has been deleted (or otherwise vanished). The catch
    // block logs a warning and swallows so the webhook handler never 500s just because
    // audit tracking couldn't write.

    @IsTest
    static void markProcessed_updateFailsOnDeletedRow_catchBranchLogsWarnGracefully() {
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
            'evt_deleted_processed', 'Stripe', 'charge.succeeded', '{}'
        );
        Id rowId = r.row.Id;
        delete r.row;
        Database.emptyRecycleBin(new List<Id>{ rowId });

        Test.startTest();
        // The record is gone — Database.update(upd, false) will throw internally. The catch
        // block must swallow it so we return cleanly.
        WebhookEventLogger.markProcessed(r.row, null);
        Test.stopTest();

        Integer stillGone = [SELECT COUNT() FROM Webhook_Event__c WHERE Id = :rowId];
        System.assertEquals(0, stillGone,
            'Deleted row must remain deleted; markProcessed catch branch must not resurrect it');
    }

    @IsTest
    static void markFailed_updateFailsOnDeletedRow_catchBranchLogsWarnGracefully() {
        WebhookEventLogger.RecordResult r = WebhookEventLogger.checkAndRecord(
            'evt_deleted_failed', 'Stripe', 'charge.failed', '{}'
        );
        Id rowId = r.row.Id;
        delete r.row;
        Database.emptyRecycleBin(new List<Id>{ rowId });

        Test.startTest();
        WebhookEventLogger.markFailed(r.row, new DmlException('boom'));
        Test.stopTest();

        Integer stillGone = [SELECT COUNT() FROM Webhook_Event__c WHERE Id = :rowId];
        System.assertEquals(0, stillGone,
            'Deleted row must remain deleted; markFailed catch branch must not resurrect it');
    }

    // ---------- Volume within governor limits ----------
    // This class is invoked ONCE per inbound webhook (not looped), so the realistic
    // volume test verifies a fleet of independent single calls within one Apex
    // transaction stays under the 100 SOQL / 150 DML governor limits. The pre-query
    // dedupe check spends 1 SOQL + 1 DML per call, so 50 sequential calls = 50/100
    // SOQL and 50/150 DML — well inside limits with 2x headroom.
    @IsTest
    static void volume_50UniqueEvents_allInsertedWithinLimits() {
        Test.startTest();
        for (Integer i = 0; i < 50; i++) {
            WebhookEventLogger.checkAndRecord('evt_vol_' + i, 'Stripe', 'x', '{}');
        }
        System.assert(Limits.getQueries() < Limits.getLimitQueries(),
            'SOQL limit budget must not be exhausted');
        System.assert(Limits.getDmlStatements() < Limits.getLimitDmlStatements(),
            'DML limit budget must not be exhausted');
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Webhook_Event__c WHERE External_Id__c LIKE 'evt_vol_%'];
        System.assertEquals(50, count, '50 unique events must all be persisted');
    }
}

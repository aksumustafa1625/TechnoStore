/**
 * Idempotency layer for inbound webhooks.
 *
 * Webhook delivery is at-least-once: Stripe, DocuSign Connect, JIRA Cloud all retry on
 * timeout / 5xx / network drop, and Stripe explicitly documents that the same event can
 * arrive multiple times. Without dedup, retries cause double-charges, duplicate emails,
 * duplicate Sendcloud parcels.
 *
 * Two-layer defense:
 *   1. DB-level: Webhook_Event__c.External_Id__c has a Unique constraint. A second insert
 *      with the same External_Id raises DUPLICATE_VALUE — protects under race conditions
 *      where two parallel webhook deliveries hit the endpoint simultaneously.
 *   2. Apex-level: checkAndRecord() queries the table first; if a row exists the handler
 *      short-circuits with 200 OK and Status=Duplicate. Saves a DML and avoids the
 *      DUPLICATE_VALUE exception path in the happy case.
 *
 * Lifecycle:
 *   - checkAndRecord(...) → returns RecordResult (isDuplicate flag + Webhook_Event__c row)
 *     · isDuplicate=true: handler does respond(200, "already processed") and returns
 *     · isDuplicate=false: row inserted with Status=Received; handler proceeds
 *   - markProcessed(row, relatedRecordId) → flips Status to Processed, stamps Processed_At
 *   - markFailed(row, exception) → flips Status to Failed, stores Error_Message
 *
 * Site Guest User must have Create access on Webhook_Event__c via the
 * Inventory_Webhook_Access permission set (extended to grant this).
 */
public without sharing class WebhookEventLogger {

    // Test-only seam: when true, checkAndRecord skips the pre-query dedupe branch and jumps
    // straight into the insert/DUPLICATE_VALUE catch path. Lets a test force the race-condition
    // branch that in production only fires under concurrent parallel inserts.
    @TestVisible
    private static Boolean testSkipPreQuery = false;

    public class RecordResult {
        public Boolean isDuplicate;
        public Webhook_Event__c row;
    }

    /**
     * Idempotency check + insert in one call.
     * @param externalId    Provider's unique event id (Stripe evt_*, DocuSign envelopeId+event, JIRA issueKey+timestamp)
     * @param source        Source__c picklist value
     * @param eventType     Provider event name (optional)
     * @param payload       Raw JSON body (truncated to 32K)
     * @return RecordResult with isDuplicate flag
     */
    public static RecordResult checkAndRecord(String externalId, String source, String eventType, String payload) {
        RecordResult result = new RecordResult();
        result.isDuplicate = false;

        if (String.isBlank(externalId)) {
            // No idempotency key — fall back to letting handler proceed but log the gap
            result.row = insertReceived(generateFallbackId(source), source, eventType, payload);
            return result;
        }

        if (!testSkipPreQuery) {
            List<Webhook_Event__c> existing = [
                SELECT Id, Status__c, External_Id__c, CreatedDate
                FROM Webhook_Event__c
                WHERE External_Id__c = :externalId
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                result.isDuplicate = true;
                result.row = existing[0];
                return result;
            }
        }

        try {
            result.row = insertReceived(externalId, source, eventType, payload);
        } catch (DmlException e) {
            // Race condition — second insert lost. Re-query to get the winner and mark duplicate.
            if (e.getMessage() != null && e.getMessage().contains('DUPLICATE_VALUE')) {
                List<Webhook_Event__c> winner = [
                    SELECT Id, Status__c, External_Id__c FROM Webhook_Event__c WHERE External_Id__c = :externalId LIMIT 1
                ];
                if (!winner.isEmpty()) {
                    result.isDuplicate = true;
                    result.row = winner[0];
                    return result;
                }
            }
            throw e;
        }
        return result;
    }

    // markProcessed and markFailed are best-effort: under Site Guest User context the user
    // license disallows Edit on custom objects, so the lifecycle status field can't transition.
    // Core idempotency (DB-level Unique on External_Id__c + the Received row that's already
    // inserted) is independent of this update and stays correct. We swallow update failures
    // so the webhook handler doesn't 500 just because audit-tracking couldn't write.
    public static void markProcessed(Webhook_Event__c row, Id relatedRecordId) {
        if (row == null || row.Id == null) return;
        try {
            Webhook_Event__c upd = new Webhook_Event__c(
                Id = row.Id,
                Status__c = 'Processed',
                Processed_At__c = System.now(),
                Related_Record_Id__c = (relatedRecordId == null) ? null : String.valueOf(relatedRecordId)
            );
            Database.update(upd, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WebhookEventLogger.markProcessed update failed (non-fatal): ' + e.getMessage());
        }
    }

    public static void markFailed(Webhook_Event__c row, Exception ex) {
        if (row == null || row.Id == null) return;
        try {
            String msg = (ex == null) ? 'Unknown failure' : (ex.getTypeName() + ': ' + ex.getMessage());
            String trace = (ex == null) ? null : ex.getStackTraceString();
            if (trace != null && msg.length() + trace.length() + 5 < 32000) {
                msg = msg + '\n\n' + trace;
            }
            Webhook_Event__c upd = new Webhook_Event__c(
                Id = row.Id,
                Status__c = 'Failed',
                Processed_At__c = System.now(),
                Error_Message__c = msg.left(32000)
            );
            Database.update(upd, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WebhookEventLogger.markFailed update failed (non-fatal): ' + e.getMessage());
        }
    }

    private static Webhook_Event__c insertReceived(String externalId, String source, String eventType, String payload) {
        Webhook_Event__c row = new Webhook_Event__c(
            External_Id__c = externalId,
            Source__c = source,
            Event_Type__c = (eventType == null) ? null : eventType.left(80),
            Payload__c = (payload == null) ? null : payload.left(32000),
            Status__c = 'Received'
        );
        insert row;
        return row;
    }

    private static String generateFallbackId(String source) {
        // Webhooks without natural unique IDs get a synthetic one so the DB doesn't NULL-collide.
        return (source == null ? 'unknown' : source) + '-' + System.now().getTime() + '-' + Math.round(Math.random() * 100000);
    }
}

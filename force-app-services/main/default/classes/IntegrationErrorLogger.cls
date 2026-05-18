/**
 * Centralised integration-failure log writer.
 *
 * Every Apex catch block, Mule global error handler, and webhook fault should funnel here
 * so the Integration Health dashboard has a single source of truth. Plain System.debug
 * is fire-and-forget — gone the moment the debug log rotates. This object persists every
 * failure with severity, type, payload, stack trace, and a correlation id that lets ops
 * triage trace SF ↔ Mule ↔ provider hops for a single business transaction.
 *
 * Severity mapping:
 *   Critical - customer-impacting or money/data loss; alert Slack #integration-ops
 *   Error    - system function broken, no direct customer impact (default for catch blocks)
 *   Warning  - degraded but auto-recovered or partial success
 *   Info     - trace/diagnostic logging
 *
 * All inserts use Database.insert(allOrNone=false) so a failure to log doesn't poison the
 * caller's transaction. The original exception in the caller's catch block must be
 * rethrown or handled independently — this logger never suppresses upstream.
 */
public without sharing class IntegrationErrorLogger {

    public class Request {
        public String sourceSystem;     // Source_System__c picklist value
        public String operation;        // short label, e.g. "Stripe Webhook checkout.session.completed"
        public String errorType;        // Auth / Parse / Validation / Downstream / Timeout / Other
        public String errorMessage;     // exception message or HTTP error body
        public String stackTrace;       // e.getStackTraceString() or Mule processor path
        public String payload;          // request/response body at fail time
        public Id relatedRecordId;      // Order / Quote / Contract / Invoice id
        public String correlationId;    // UUID propagated across SF→Mule→provider
        public String severity;         // Critical / Error / Warning / Info — defaults to Error
        public Integer retryCount;      // how many times upstream tried before logging
    }

    /**
     * Log a single failure. Returns the inserted record (or null on insert failure).
     * Never throws — designed to be safe inside catch blocks.
     */
    public static Integration_Error__c log(Request req) {
        if (req == null) return null;
        try {
            Integration_Error__c err = buildRecord(req);
            Database.SaveResult sr = Database.insert(err, false);
            if (sr.isSuccess()) {
                return err;
            } else {
                System.debug(LoggingLevel.ERROR, 'IntegrationErrorLogger insert failed: ' + sr.getErrors()[0].getMessage());
                return null;
            }
        } catch (Exception e) {
            // Last-resort fallback — the logger itself failed; emit to debug log.
            System.debug(LoggingLevel.ERROR, 'IntegrationErrorLogger fatal: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Convenience overload for Apex catch blocks.
     */
    public static Integration_Error__c log(String sourceSystem, String operation, Exception ex, Id relatedRecordId, String correlationId) {
        Request req = new Request();
        req.sourceSystem = sourceSystem;
        req.operation = operation;
        req.errorMessage = (ex == null) ? 'Unknown error' : (ex.getTypeName() + ': ' + ex.getMessage());
        req.stackTrace = (ex == null) ? null : ex.getStackTraceString();
        req.errorType = classifyException(ex);
        req.severity = 'Error';
        req.relatedRecordId = relatedRecordId;
        req.correlationId = correlationId;
        return log(req);
    }

    /**
     * Convenience overload for HTTP callout failures.
     */
    public static Integration_Error__c logHttpFailure(String sourceSystem, String operation, HttpResponse resp, String reqBody, Id relatedRecordId, String correlationId) {
        Request req = new Request();
        req.sourceSystem = sourceSystem;
        req.operation = operation;
        req.errorMessage = 'HTTP ' + (resp == null ? '?' : String.valueOf(resp.getStatusCode())) + ': ' + (resp == null ? '' : String.valueOf(resp.getBody()).left(2000));
        req.errorType = classifyHttpStatus(resp);
        req.severity = (resp != null && resp.getStatusCode() >= 500) ? 'Critical' : 'Error';
        req.payload = reqBody;
        req.relatedRecordId = relatedRecordId;
        req.correlationId = correlationId;
        return log(req);
    }

    /**
     * Mint a fresh correlation id at the start of a business transaction so SF Apex,
     * Mule HTTP requests, and external providers can all stamp the same id on their logs.
     */
    public static String newCorrelationId() {
        Blob b = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(b);
        // RFC 4122-ish display: 8-4-4-4-12
        return hex.substring(0,8) + '-' + hex.substring(8,12) + '-' + hex.substring(12,16) + '-' + hex.substring(16,20) + '-' + hex.substring(20,32);
    }

    private static Integration_Error__c buildRecord(Request req) {
        Integration_Error__c err = new Integration_Error__c(
            Source_System__c   = req.sourceSystem == null ? 'Other' : req.sourceSystem,
            Operation__c       = req.operation == null ? 'unknown' : req.operation.left(80),
            Error_Type__c      = req.errorType == null ? 'Other' : req.errorType,
            Error_Message__c   = req.errorMessage == null ? null : req.errorMessage.left(32000),
            Stack_Trace__c     = req.stackTrace == null ? null : req.stackTrace.left(32000),
            Payload__c         = req.payload == null ? null : req.payload.left(32000),
            Related_Record_Id__c = req.relatedRecordId == null ? null : String.valueOf(req.relatedRecordId),
            Correlation_Id__c  = req.correlationId == null ? null : req.correlationId.left(80),
            Severity__c        = (req.severity == null) ? 'Error' : req.severity,
            Status__c          = 'New',
            Retry_Count__c     = req.retryCount
        );
        return err;
    }

    private static String classifyException(Exception ex) {
        if (ex == null) return 'Other';
        String t = ex.getTypeName();
        String m = ex.getMessage() == null ? '' : ex.getMessage();
        if (t.contains('CalloutException') && m.toLowerCase().contains('timed out')) return 'Timeout';
        if (t.contains('CalloutException')) return 'Downstream';
        if (t.contains('JSONException')) return 'Parse';
        if (t.contains('DmlException') && m.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION')) return 'Validation';
        if (m.toLowerCase().contains('unauthorized') || m.contains('401') || m.contains('403')) return 'Auth';
        return 'Other';
    }

    private static String classifyHttpStatus(HttpResponse resp) {
        if (resp == null) return 'Other';
        Integer code = resp.getStatusCode();
        if (code == 401 || code == 403) return 'Auth';
        if (code == 400 || code == 422) return 'Validation';
        if (code == 408 || code == 504) return 'Timeout';
        if (code >= 500) return 'Downstream';
        if (code >= 400) return 'Validation';
        return 'Other';
    }
}

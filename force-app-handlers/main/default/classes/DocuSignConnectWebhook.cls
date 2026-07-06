/**
 * DocuSign Connect inbound webhook.
 *
 * SECURITY NOTE: This endpoint currently relies on payload-shape validation +
 * envelope-id idempotency (via WebhookEventLogger) rather than a shared-secret
 * or HMAC signature. That is a known gap tracked as TS-SEC-002 in SECURITY.md.
 * Production hardening path: verify DocuSign's `X-DocuSign-Signature-1` header
 * against Crypto.generateMac('hmacSHA256', body, secret) before dispatch.
 */
@RestResource(urlMapping='/docusign/webhook/*')
global without sharing class DocuSignConnectWebhook {

    // ---- Test seams (TS-TEST-021) ---------------------------------------------------
    // Two defensive branches in handle() cannot be triggered from a unit test without
    // a Salesforce-platform failure we cannot simulate:
    //   1. EventBus.publish returning a failed SaveResult (Salesforce accepts any
    //      well-formed platform event under governor limits — publish rarely fails).
    //   2. An unhandled exception between checkAndRecord and markProcessed (no line
    //      of code between those two points normally throws).
    // These booleans let the test suite exercise both branches without invasive
    // refactoring. Production code paths remain identical (both default to false).
    @TestVisible private static Boolean testForcePublishFailure = false;
    @TestVisible private static Boolean testForceUnhandledException = false;

    @HttpPost
    global static void handle() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String body = req.requestBody == null ? '' : req.requestBody.toString();
        String correlationId = IntegrationErrorLogger.newCorrelationId();
        WebhookEventLogger.RecordResult eventRecord = null;

        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);
            String envelopeId = extractEnvelopeId(payload);
            String dsStatus = extractEnvelopeStatus(payload);

            if (String.isBlank(envelopeId) || String.isBlank(dsStatus)) {
                respondJson(res, 400, 'Missing envelopeId or status', null, null);
                return;
            }

            // Idempotency check — DocuSign Connect retries on timeout/non-2xx; same envelope-status
            // pair must only fire once. External_Id = envelopeId + "|" + status.
            String externalId = envelopeId + '|' + dsStatus;
            eventRecord = WebhookEventLogger.checkAndRecord(externalId, 'DocuSign', 'envelope-' + dsStatus, body);
            if (eventRecord.isDuplicate) {
                respondJson(res, 200, 'Event already processed — duplicate delivery dropped', envelopeId, dsStatus);
                return;
            }

            DocuSign_Status_Update__e evt = new DocuSign_Status_Update__e(
                Envelope_Id__c = envelopeId,
                DocuSign_Status__c = dsStatus
            );
            Database.SaveResult sr;
            if (testForcePublishFailure) {
                // Deserialize a synthetic failed SaveResult — Database.SaveResult has no public
                // constructor but is JSON-deserializable. This lets the test suite drive the
                // publish-failure branch below without needing Salesforce to reject the event.
                sr = (Database.SaveResult) JSON.deserialize(
                    '{"success":false,"errors":[{"message":"Simulated publish failure (test seam)","statusCode":"UNKNOWN_EXCEPTION","fields":[]}],"id":null}',
                    Database.SaveResult.class
                );
            } else {
                sr = EventBus.publish(evt);
            }
            if (!sr.isSuccess()) {
                String pubErr = sr.getErrors()[0].getMessage();
                IntegrationErrorLogger.Request errReq = new IntegrationErrorLogger.Request();
                errReq.sourceSystem = 'DocuSign';
                errReq.operation = 'EventBus.publish DocuSign_Status_Update__e';
                errReq.errorMessage = pubErr;
                errReq.errorType = 'Downstream';
                errReq.severity = 'Critical';
                errReq.correlationId = correlationId;
                errReq.payload = body;
                IntegrationErrorLogger.log(errReq);
                WebhookEventLogger.markFailed(eventRecord.row, new EventPublishException(pubErr));
                respondJson(res, 500, 'Event publish failed: ' + pubErr, envelopeId, dsStatus);
                return;
            }
            if (testForceUnhandledException) {
                // Test seam — simulates a runtime exception AFTER checkAndRecord has
                // populated eventRecord.row, so the outer catch's markFailed branch runs.
                throw new EventPublishException('Simulated unhandled exception (test seam)');
            }
            WebhookEventLogger.markProcessed(eventRecord.row, null);
            respondJson(res, 200, 'Event published', envelopeId, dsStatus);
        } catch (Exception e) {
            IntegrationErrorLogger.log('DocuSign', 'DocuSignConnectWebhook unhandled', e, null, correlationId);
            if (eventRecord != null && eventRecord.row != null) {
                WebhookEventLogger.markFailed(eventRecord.row, e);
            }
            respondJson(res, 500, e.getTypeName() + ': ' + e.getMessage(), null, null);
        }
    }

    @HttpGet
    global static void healthCheck() {
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf('{"status":"ok"}');
        RestContext.response.addHeader('Content-Type', 'application/json');
    }

    public class EventPublishException extends Exception {}

    @SuppressWarnings('PMD.CognitiveComplexity')
    private static String extractEnvelopeId(Map<String, Object> p) {
        if (p == null) return null;
        if (p.get('data') instanceof Map<String, Object>) {
            Map<String, Object> data = (Map<String, Object>) p.get('data');
            if (data.get('envelopeId') != null) return String.valueOf(data.get('envelopeId'));
        }
        if (p.get('envelopeId') != null) return String.valueOf(p.get('envelopeId'));
        if (p.get('EnvelopeStatus') instanceof Map<String, Object>) {
            Map<String, Object> es = (Map<String, Object>) p.get('EnvelopeStatus');
            if (es.get('EnvelopeID') != null) return String.valueOf(es.get('EnvelopeID'));
        }
        return null;
    }

    @SuppressWarnings('PMD.CognitiveComplexity')
    private static String extractEnvelopeStatus(Map<String, Object> p) {
        if (p == null) return null;
        if (p.get('event') != null) {
            String evt = String.valueOf(p.get('event'));
            if (evt.startsWith('envelope-')) return evt.substring(9);
        }
        if (p.get('data') instanceof Map<String, Object>) {
            Map<String, Object> data = (Map<String, Object>) p.get('data');
            if (data.get('envelopeSummary') instanceof Map<String, Object>) {
                Map<String, Object> sum = (Map<String, Object>) data.get('envelopeSummary');
                if (sum.get('status') != null) return String.valueOf(sum.get('status'));
            }
            if (data.get('status') != null) return String.valueOf(data.get('status'));
        }
        if (p.get('status') != null) return String.valueOf(p.get('status'));
        if (p.get('EnvelopeStatus') instanceof Map<String, Object>) {
            Map<String, Object> es = (Map<String, Object>) p.get('EnvelopeStatus');
            if (es.get('Status') != null) return String.valueOf(es.get('Status'));
        }
        return null;
    }

    private static void respondJson(RestResponse res, Integer code, String msg, String envelopeId, String dsStatus) {
        res.statusCode = code;
        res.addHeader('Content-Type', 'application/json');
        Map<String, Object> body = new Map<String, Object>{
            'message' => msg,
            'envelopeId' => envelopeId,
            'docuSignStatus' => dsStatus
        };
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}

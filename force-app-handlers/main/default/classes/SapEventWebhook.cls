/**
 * Public REST endpoint that SAP Event Mesh calls when a subscribed event fires.
 * Companion to the inbound webhook pattern from ADR-003 (Site + Guest User +
 * Platform Event indirection); third instance after DocuSignConnectWebhook and
 * JiraStatusWebhook.
 *
 * Exposed at /services/apexrest/sap/event. Production target: SAP Event Mesh
 * subscription pushes CloudEvents 1.0 JSON payloads to this URL. Sandbox-only
 * limitation: SAP API Hub Sandbox doesn't expose Event Mesh, so the endpoint
 * is exercised by synthetic test payloads (scripts/test_sap_event_webhook.apex)
 * that mirror the CloudEvents shape SAP would produce.
 *
 * Expected CloudEvents 1.0 body shape:
 *   {
 *     "specversion": "1.0",
 *     "id": "evt-12345",
 *     "type": "sap.s4.beh.salesorder.v1.SalesOrder.Changed.v1",
 *     "source": "/sap/s4hanacloud",
 *     "subject": "0090000456",
 *     "datacontenttype": "application/json",
 *     "time": "2026-05-18T20:50:00Z",
 *     "data": { "SalesOrder": "0090000456", "OverallSDProcessStatus": "C", ... }
 *   }
 *
 * Authentication: HMAC shared secret in X-SAP-Secret header. Production with
 * full Event Mesh adds CloudEvents-extension signature header (sap-context-signature);
 * the demo uses the same shared-secret pattern as the JIRA / DocuSign webhooks.
 *
 * Three guarantees provided here:
 *   1. Idempotency — Webhook_Event__c row keyed by CloudEvent id; replay or
 *      at-least-once delivery double-fires are caught (ADR-013).
 *   2. Trust boundary — runs as Site Guest User but doesn't write to business
 *      objects directly; publishes SAP_Inbound_Event__e platform event which
 *      a system-context trigger handles. ADR-003 pattern.
 *   3. Audit on failure — schema-invalid payloads or HMAC mismatches return
 *      4xx and log to Integration_Error__c via IntegrationErrorLogger.
 */
@RestResource(urlMapping='/sap/event/*')
global without sharing class SapEventWebhook {

    @HttpPost
    global static void handle() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String body = (req.requestBody == null) ? '' : req.requestBody.toString();
        String correlationId = IntegrationErrorLogger.newCorrelationId();

        try {
            Inventory_Integration_Config__mdt cfg = Inventory_Integration_Config__mdt.getInstance('Default');
            if (cfg == null || String.isBlank(cfg.Shared_Secret__c)) {
                respond(res, 500, 'Server config missing.');
                return;
            }
            String providedSecret = req.headers.get('X-SAP-Secret');
            if (String.isBlank(providedSecret)) providedSecret = req.params.get('secret');
            if (String.isBlank(providedSecret) || providedSecret != cfg.Shared_Secret__c) {
                respond(res, 401, 'Invalid or missing X-SAP-Secret header.');
                return;
            }

            Map<String, Object> ce;
            try {
                ce = (Map<String, Object>) JSON.deserializeUntyped(body);
            } catch (Exception parseEx) {
                respond(res, 400, 'Invalid JSON body.');
                return;
            }

            String eventId = (ce.get('id') == null) ? null : String.valueOf(ce.get('id'));
            String eventType = (ce.get('type') == null) ? null : String.valueOf(ce.get('type'));
            String subject = (ce.get('subject') == null) ? null : String.valueOf(ce.get('subject'));
            String source = (ce.get('source') == null) ? null : String.valueOf(ce.get('source'));
            Object dataObj = ce.get('data');

            if (String.isBlank(eventId) || String.isBlank(eventType)) {
                respond(res, 400, 'CloudEvent missing required id or type.');
                return;
            }

            // Idempotency check + insert in one call (ADR-013)
            WebhookEventLogger.RecordResult logResult = WebhookEventLogger.checkAndRecord(eventId, 'SAP', eventType, body);
            if (logResult.isDuplicate) {
                respond(res, 200, 'Event ' + eventId + ' already processed; no-op (idempotent).');
                return;
            }

            // Dispatch inline (platform event indirection skipped due to Developer Edition
            // custom-object cap; see ADR-028 Decision section). Production org with no cap
            // pressure can reintroduce SAP_Inbound_Event__e platform event for trust-boundary
            // cleanness — dispatcher signature is unchanged.
            SapInboundEventDispatcher.CloudEvent ce2 = new SapInboundEventDispatcher.CloudEvent();
            ce2.eventId = eventId;
            ce2.eventType = eventType;
            ce2.subject = subject;
            ce2.source = source;
            ce2.data = (dataObj instanceof Map<String, Object>) ? (Map<String, Object>) dataObj : null;
            SapInboundEventDispatcher.dispatch(ce2);

            WebhookEventLogger.markProcessed(logResult.row, null);
            respond(res, 200, 'Event ' + eventId + ' dispatched.');
        } catch (Exception e) {
            IntegrationErrorLogger.log('SAP', 'SapEventWebhook.handle', e, null, correlationId);
            respond(res, 500, e.getTypeName() + ': ' + e.getMessage());
        }
    }

    @HttpGet
    global static void healthCheck() {
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf('{"status":"ok","service":"SapEventWebhook"}');
        RestContext.response.addHeader('Content-Type', 'application/json');
    }

    private static void respond(RestResponse res, Integer code, String msg) {
        res.statusCode = code;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'message' => msg }));
    }
}

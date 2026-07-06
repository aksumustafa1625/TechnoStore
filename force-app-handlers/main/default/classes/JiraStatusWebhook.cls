/**
 * Public REST endpoint that JIRA Cloud Automation calls when an inventory ticket
 * transitions to Done. Out-of-stock workflow:
 *   1. Warehouse marks Order Out of Stock via the VF page (see WarehouseInventoryApprovalController)
 *   2. JiraTicketService.createTicketAsync opens a JIRA Task linked back via Order.JIRA_Ticket_Id__c
 *   3. Warehouse replenishes physical stock, marks the JIRA ticket Done
 *   4. JIRA Automation Rule fires → POSTs here → Order auto-activates
 *
 * Exposed at /services/apexrest/jira/webhook via Site Guest User access on the
 * Inventory_Webhook_Access permission set (same set that grants InventoryCheckCallback,
 * since both serve the same end-to-end warehouse integration).
 *
 * Two supported payload shapes:
 *   (a) Custom shape — when called from JIRA Automation Rule "Send web request" action:
 *         { "issueKey": "TS-10", "status": "Done" }
 *       Secret carried in X-Jira-Secret header.
 *
 *   (b) Native JIRA Webhook v1.0 shape — when registered via /rest/webhooks/1.0/webhook:
 *         { "webhookEvent": "jira:issue_updated",
 *           "issue": { "key": "TS-10", "fields": { "status": { "name": "Done" } } },
 *           "changelog": { "items": [ { "field": "status", "toString": "Done" } ] } }
 *       Since v1.0 webhooks can't send custom headers, secret is read from ?secret=...
 *       URL query parameter as fallback.
 *
 * Secret must match Inventory_Integration_Config__mdt.Default.Shared_Secret__c.
 *
 * Idempotency: every accepted event is recorded in Webhook_Event__c via WebhookEventLogger.
 * If the same issueKey+status+timestamp combination arrives again, the duplicate short-circuits
 * with 200 OK and Status=Duplicate. Stripe and JIRA both deliver at-least-once; without this
 * layer a retry causes the Order to re-activate and a duplicate Asset / FeedItem cascade.
 * Failures route to Integration_Error__c so the ops dashboard surfaces them.
 *
 * Pattern (mirrors DocuSignConnectWebhook + InventoryCheckCallback): the endpoint runs as
 * the Site Guest User with no direct Order edit permission. It publishes an
 * Inventory_Status_Update__e platform event; the after-insert trigger handler then updates
 * the Order in a system context — flipping Inventory_Status__c to In Stock AND, if the
 * Order is still Draft, Status to Activated (which fires the asset-creation trigger).
 */
@RestResource(urlMapping='/jira/webhook/*')
global without sharing class JiraStatusWebhook {

    /**
     * @TestVisible seam: allows tests to force a lookup key that will NOT match any
     * deployed Inventory_Integration_Config__mdt record, so the null-config 500 branch
     * can be exercised. Never set outside test context — remains null in production.
     */
    @TestVisible private static String testConfigKey = null;

    @HttpPost
    global static void handle() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String body = (req.requestBody == null) ? '' : req.requestBody.toString();
        String correlationId = IntegrationErrorLogger.newCorrelationId();
        WebhookEventLogger.RecordResult eventRecord = null;

        try {
            String cfgKey = String.isNotBlank(testConfigKey) ? testConfigKey : 'Default';
            Inventory_Integration_Config__mdt config = Inventory_Integration_Config__mdt.getInstance(cfgKey);
            if (config == null || String.isBlank(config.Shared_Secret__c)) {
                respond(res, 500, 'Server config missing.');
                return;
            }

            String providedSecret = req.headers.get('X-Jira-Secret');
            if (String.isBlank(providedSecret)) {
                providedSecret = req.params.get('secret');
            }
            if (String.isBlank(providedSecret) || providedSecret != config.Shared_Secret__c) {
                respond(res, 401, 'Invalid or missing secret (X-Jira-Secret header or ?secret= query param).');
                return;
            }

            Map<String, Object> payload;
            try {
                payload = (Map<String, Object>) JSON.deserializeUntyped(body);
            } catch (Exception parseEx) {
                IntegrationErrorLogger.log('JIRA', 'JiraStatusWebhook JSON parse', parseEx, null, correlationId);
                respond(res, 400, 'Invalid JSON body.');
                return;
            }

            String issueKey = extractIssueKey(payload);
            String status   = extractStatus(payload);
            String timestamp = extractTimestamp(payload);

            if (String.isBlank(issueKey) || String.isBlank(status)) {
                respond(res, 400, 'Missing issueKey or status (neither custom shape nor JIRA native webhook shape detected).');
                return;
            }
            if (status != 'Done') {
                respond(res, 200, 'Status "' + status + '" ignored — only Done triggers activation.');
                return;
            }

            // Idempotency check — same issueKey+status+timestamp deduped at DB level via Unique constraint.
            String externalId = issueKey + '|' + status + (String.isBlank(timestamp) ? '' : ('|' + timestamp));
            eventRecord = WebhookEventLogger.checkAndRecord(externalId, 'JIRA', 'jira:issue_updated', body);
            if (eventRecord.isDuplicate) {
                respond(res, 200, 'Event ' + externalId + ' already processed — duplicate delivery dropped.');
                return;
            }

            List<Order> orders = [
                SELECT Id, Status
                FROM Order
                WHERE JIRA_Ticket_Id__c = :issueKey
                LIMIT 1
            ];
            if (orders.isEmpty()) {
                WebhookEventLogger.markProcessed(eventRecord.row, null);
                respond(res, 404, 'No Order linked to JIRA issue ' + issueKey + '.');
                return;
            }

            Order o = orders[0];
            if (o.Status == 'Activated') {
                WebhookEventLogger.markProcessed(eventRecord.row, o.Id);
                respond(res, 200, 'Order already Activated for ' + issueKey + ' — no action taken.');
                return;
            }

            Inventory_Status_Update__e evt = new Inventory_Status_Update__e(
                Order_Id__c     = o.Id,
                New_Status__c   = 'In Stock',
                Confirmed_By__c = 'JIRA ' + issueKey
            );
            Database.SaveResult sr = EventBus.publish(evt);
            if (!sr.isSuccess()) {
                String pubErr = sr.getErrors()[0].getMessage();
                IntegrationErrorLogger.Request errReq = new IntegrationErrorLogger.Request();
                errReq.sourceSystem = 'JIRA';
                errReq.operation = 'EventBus.publish Inventory_Status_Update__e';
                errReq.errorMessage = pubErr;
                errReq.errorType = 'Downstream';
                errReq.severity = 'Critical';
                errReq.relatedRecordId = o.Id;
                errReq.correlationId = correlationId;
                errReq.payload = body;
                IntegrationErrorLogger.log(errReq);
                WebhookEventLogger.markFailed(eventRecord.row, new EventPublishException(pubErr));
                respond(res, 500, 'Event publish failed: ' + pubErr);
                return;
            }

            WebhookEventLogger.markProcessed(eventRecord.row, o.Id);
            respond(res, 200, 'Order activation queued for ' + issueKey + '.');
        } catch (Exception e) {
            IntegrationErrorLogger.log('JIRA', 'JiraStatusWebhook unhandled', e, null, correlationId);
            if (eventRecord != null && eventRecord.row != null) {
                WebhookEventLogger.markFailed(eventRecord.row, e);
            }
            respond(res, 500, e.getTypeName() + ': ' + e.getMessage());
        }
    }

    @HttpGet
    global static void healthCheck() {
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf('{"status":"ok","service":"JiraStatusWebhook"}');
        RestContext.response.addHeader('Content-Type', 'application/json');
    }

    public class EventPublishException extends Exception {}

    private static String extractIssueKey(Map<String, Object> p) {
        if (p == null) return null;
        if (p.get('issueKey') != null) return String.valueOf(p.get('issueKey'));
        if (p.get('issue') instanceof Map<String, Object>) {
            Map<String, Object> issue = (Map<String, Object>) p.get('issue');
            if (issue.get('key') != null) return String.valueOf(issue.get('key'));
        }
        return null;
    }

    private static String extractStatus(Map<String, Object> p) {
        if (p == null) return null;
        if (p.get('status') != null) return String.valueOf(p.get('status'));
        if (p.get('issue') instanceof Map<String, Object>) {
            Map<String, Object> issue = (Map<String, Object>) p.get('issue');
            if (issue.get('fields') instanceof Map<String, Object>) {
                Map<String, Object> fields = (Map<String, Object>) issue.get('fields');
                if (fields.get('status') instanceof Map<String, Object>) {
                    Map<String, Object> st = (Map<String, Object>) fields.get('status');
                    if (st.get('name') != null) return String.valueOf(st.get('name'));
                }
            }
        }
        if (p.get('changelog') instanceof Map<String, Object>) {
            Map<String, Object> cl = (Map<String, Object>) p.get('changelog');
            if (cl.get('items') instanceof List<Object>) {
                for (Object item : (List<Object>) cl.get('items')) {
                    if (item instanceof Map<String, Object>) {
                        Map<String, Object> it = (Map<String, Object>) item;
                        if ('status'.equalsIgnoreCase(String.valueOf(it.get('field'))) && it.get('toString') != null) {
                            return String.valueOf(it.get('toString'));
                        }
                    }
                }
            }
        }
        return null;
    }

    private static String extractTimestamp(Map<String, Object> p) {
        if (p == null) return null;
        if (p.get('timestamp') != null) return String.valueOf(p.get('timestamp'));
        return null;
    }

    private static void respond(RestResponse res, Integer code, String msg) {
        res.statusCode = code;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'message' => msg }));
    }
}

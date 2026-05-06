/**
 * Public REST endpoint that MuleSoft calls when a warehouse user clicks Confirm/Reject in Slack.
 *
 * Exposed at /services/apexrest/inventory/callback (Site Guest User access via the
 * Inventory_Webhook_Access permission set).
 *
 * Expected JSON body from MuleSoft:
 *   {
 *     "sharedSecret": "<must match Inventory_Integration_Config__mdt.Default.Shared_Secret__c>",
 *     "orderId": "<Order Id>",
 *     "newStatus": "In Stock" | "Out of Stock",
 *     "confirmedBy": "<Slack display name>"
 *   }
 *
 * Pattern (mirrors DocuSignConnectWebhook): the endpoint runs as the Site Guest User, which
 * intentionally has no direct Order edit permission. The endpoint publishes an
 * Inventory_Status_Update__e platform event; an after-insert trigger then updates the Order
 * in a system context (without granting guest user write access to Order itself).
 */
@RestResource(urlMapping='/inventory/callback/*')
global without sharing class InventoryCheckCallback {

    @HttpPost
    global static void handle() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String body = (req.requestBody == null) ? '' : req.requestBody.toString();

        try {
            Inventory_Integration_Config__mdt config = Inventory_Integration_Config__mdt.getInstance('Default');
            if (config == null || String.isBlank(config.Shared_Secret__c)) {
                respond(res, 500, 'Server config missing.');
                return;
            }

            Map<String, Object> payload;
            try {
                payload = (Map<String, Object>) JSON.deserializeUntyped(body);
            } catch (Exception parseEx) {
                respond(res, 400, 'Invalid JSON body.');
                return;
            }

            String providedSecret = String.valueOf(payload.get('sharedSecret'));
            if (providedSecret != config.Shared_Secret__c) {
                respond(res, 401, 'Invalid shared secret.');
                return;
            }

            String orderId = String.valueOf(payload.get('orderId'));
            String newStatus = String.valueOf(payload.get('newStatus'));
            String confirmedBy = String.valueOf(payload.get('confirmedBy'));

            if (String.isBlank(orderId) || String.isBlank(newStatus)) {
                respond(res, 400, 'Missing orderId or newStatus.');
                return;
            }
            if (newStatus != 'In Stock' && newStatus != 'Out of Stock') {
                respond(res, 400, 'newStatus must be "In Stock" or "Out of Stock".');
                return;
            }

            Inventory_Status_Update__e evt = new Inventory_Status_Update__e(
                Order_Id__c = orderId,
                New_Status__c = newStatus,
                Confirmed_By__c = (confirmedBy == null) ? 'Slack User' : confirmedBy
            );
            Database.SaveResult sr = EventBus.publish(evt);
            if (!sr.isSuccess()) {
                respond(res, 500, 'Event publish failed: ' + sr.getErrors()[0].getMessage());
                return;
            }
            respond(res, 200, 'Inventory status update event published.');
        } catch (Exception e) {
            respond(res, 500, e.getTypeName() + ': ' + e.getMessage());
        }
    }

    @HttpGet
    global static void healthCheck() {
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf('{"status":"ok","service":"InventoryCheckCallback"}');
        RestContext.response.addHeader('Content-Type', 'application/json');
    }

    private static void respond(RestResponse res, Integer code, String msg) {
        res.statusCode = code;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'message' => msg }));
    }
}

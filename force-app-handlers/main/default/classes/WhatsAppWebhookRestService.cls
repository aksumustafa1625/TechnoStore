/**
 * Public REST endpoint that Twilio calls when an inbound WhatsApp message arrives.
 * Fourth webhook in the TechnoStore inbound family after DocuSignConnectWebhook,
 * JiraStatusWebhook and SapEventWebhook — same enterprise pattern: shared-secret auth,
 * idempotency (ADR-013), IntegrationErrorLogger on failure, and a clean response.
 *
 * Exposed at /services/apexrest/whatsapp/webhook. Twilio POSTs an
 * application/x-www-form-urlencoded body with Body, From, To, MessageSid, etc.
 * We parse it, create a Lead, and return TwiML XML so Twilio replies to the sender.
 *
 * Auth: shared secret passed as ?secret= query param (Twilio can append query params to
 * the webhook URL but cannot easily add custom headers). Reuses
 * Inventory_Integration_Config__mdt.Default.Shared_Secret__c (same family as the SAP/JIRA
 * webhooks). PRODUCTION-GRADE alternative: validate the X-Twilio-Signature header
 * (Base64 HMAC-SHA1 of the full URL + sorted POST params, keyed by the Twilio Auth Token) —
 * noted as the hardening step.
 *
 * Idempotency: Twilio retries on timeout/non-2xx. MessageSid is the unique message id, so a
 * replay returns 200 without creating a duplicate Lead (WebhookEventLogger / ADR-013).
 */
@RestResource(urlMapping='/whatsapp/webhook/*')
global without sharing class WhatsAppWebhookRestService {

    @HttpPost
    global static void handleIncomingMessage() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String correlationId = IntegrationErrorLogger.newCorrelationId();

        try {
            // 1. Shared-secret auth (Twilio appends ?secret= to the configured webhook URL)
            Inventory_Integration_Config__mdt cfg = Inventory_Integration_Config__mdt.getInstance('Default');
            if (cfg == null || String.isBlank(cfg.Shared_Secret__c)) {
                respondTwiml(res, 500, 'Server config missing.');
                return;
            }
            String providedSecret = req.params.get('secret');
            if (String.isBlank(providedSecret) || providedSecret != cfg.Shared_Secret__c) {
                respondTwiml(res, 401, 'Unauthorized.');
                return;
            }

            // 2. Collect Twilio's parameters. Twilio sends application/x-www-form-urlencoded;
            //    when that Content-Type is used, Salesforce parses the form body into
            //    RestRequest.params (and requestBody is empty). For other delivery modes the
            //    fields arrive in the raw body. Merge both so it works in every case.
            Map<String, String> params = new Map<String, String>();
            if (req.params != null) {
                params.putAll(req.params);              // query params + form-urlencoded body fields
            }
            String body = (req.requestBody == null) ? '' : req.requestBody.toString();
            if (String.isNotBlank(body)) {
                Map<String, String> bodyParams = parseUrlEncodedBody(body);
                for (String k : bodyParams.keySet()) params.put(k, bodyParams.get(k));
            }
            String messageSid  = params.get('MessageSid');
            String fromNumber  = params.get('From');     // e.g. "whatsapp:+49160..."
            String messageText = params.get('Body');
            // Audit payload: prefer raw body, else reconstruct from parsed params
            String auditPayload = String.isNotBlank(body) ? body : JSON.serialize(params);

            if (String.isBlank(messageSid)) {
                respondTwiml(res, 400, 'Missing MessageSid.');
                return;
            }

            // 3. Idempotency — Twilio retries; MessageSid is the unique key (ADR-013)
            WebhookEventLogger.RecordResult logResult =
                WebhookEventLogger.checkAndRecord(messageSid, 'WhatsApp', 'inbound.message', auditPayload);
            if (logResult.isDuplicate) {
                respondTwiml(res, 200, 'Already received — no duplicate created.');
                return;
            }

            // 4. Business action — create a Lead from the inbound message.
            //    Enrich it by extracting an email address from the message text if present,
            //    so a customer who writes "...my email is jane@acme.de" gets a Lead with the
            //    Email field auto-populated — not just a free-text Description.
            String phone = String.isBlank(fromNumber) ? '' : fromNumber.replace('whatsapp:', '').trim();
            String extractedEmail = extractEmail(messageText);
            Lead newLead = new Lead(
                LastName    = 'WhatsApp Lead ' + (String.isBlank(phone) ? '(unknown)' : phone),
                Company     = 'WhatsApp Inbound',
                Phone       = phone,
                Email       = extractedEmail,
                LeadSource  = 'WhatsApp',
                Description = messageText,
                Status      = 'Open - Not Contacted'
            );
            insert newLead;

            WebhookEventLogger.markProcessed(logResult.row, newLead.Id);

            // 5. TwiML reply — Twilio sends this text back to the WhatsApp sender
            respondTwiml(res, 200, 'Thanks for contacting TechnoStore! Your request has been received and a team member will get back to you shortly. ✅');

        } catch (Exception e) {
            IntegrationErrorLogger.log('WhatsApp', 'WhatsAppWebhookRestService.handleIncomingMessage', e, null, correlationId);
            respondTwiml(res, 500, 'Sorry, a system error occurred. Please try again later.');
        }
    }

    // Twilio also issues a GET when you click "test" / health checks — answer politely.
    @HttpGet
    global static void healthCheck() {
        RestContext.response.statusCode = 200;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf('{"status":"ok","service":"WhatsAppWebhookRestService"}');
    }

    private static void respondTwiml(RestResponse res, Integer code, String message) {
        res.statusCode = code;
        res.addHeader('Content-Type', 'application/xml');
        res.responseBody = Blob.valueOf(
            '<?xml version="1.0" encoding="UTF-8"?><Response><Message>' + message + '</Message></Response>'
        );
    }

    // Pull the first email address out of free-text message body (null if none found).
    private static String extractEmail(String text) {
        if (String.isBlank(text)) return null;
        Matcher m = Pattern.compile('[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}').matcher(text);
        return m.find() ? m.group() : null;
    }

    private static Map<String, String> parseUrlEncodedBody(String body) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(body)) return result;
        for (String pair : body.split('&')) {
            String[] kv = pair.split('=');
            if (kv.size() == 2) {
                result.put(
                    EncodingUtil.urlDecode(kv[0], 'UTF-8'),
                    EncodingUtil.urlDecode(kv[1], 'UTF-8')
                );
            }
        }
        return result;
    }
}

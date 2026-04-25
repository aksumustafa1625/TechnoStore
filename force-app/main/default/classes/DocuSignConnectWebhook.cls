@RestResource(urlMapping='/docusign/webhook/*')
global without sharing class DocuSignConnectWebhook {

    @HttpPost
    global static void handle() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String body = req.requestBody == null ? '' : req.requestBody.toString();

        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);
            String envelopeId = extractEnvelopeId(payload);
            String dsStatus = extractEnvelopeStatus(payload);

            if (String.isBlank(envelopeId) || String.isBlank(dsStatus)) {
                respondJson(res, 400, 'Missing envelopeId or status', null, null);
                return;
            }

            DocuSign_Status_Update__e evt = new DocuSign_Status_Update__e(
                Envelope_Id__c = envelopeId,
                DocuSign_Status__c = dsStatus
            );
            Database.SaveResult sr = EventBus.publish(evt);
            if (!sr.isSuccess()) {
                respondJson(res, 500, 'Event publish failed: ' + sr.getErrors()[0].getMessage(), envelopeId, dsStatus);
                return;
            }
            respondJson(res, 200, 'Event published', envelopeId, dsStatus);
        } catch (Exception e) {
            respondJson(res, 500, e.getTypeName() + ': ' + e.getMessage(), null, null);
        }
    }

    @HttpGet
    global static void healthCheck() {
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf('{"status":"ok"}');
        RestContext.response.addHeader('Content-Type', 'application/json');
    }

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

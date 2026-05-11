// Smoke test: verify Apex can reach SAP API Hub Sandbox + return real Business Partner data.
//
// PREREQUISITES:
//   1. scripts/setup_sap_config.apex has been run with a valid API Key
//   2. SAP_API_Hub remote site is Active in Setup
//   3. SAP_Integration_Access permission set is assigned to the running user
//
// EXPECTED OUTPUT:
//   SUCCESS — fetched N Business Partners from SAP
//   BP: 1000000 / SAP Demo Customer GmbH
//   BP: 1000001 / Another Demo Customer AG
//   ...
//
// If status is 401: API Key is wrong or not saved. Re-run setup_sap_config.apex.
// If status is 403: API Hub Sandbox subscription not granted on api.sap.com.
// If status is 404: URL path wrong (SAP changed endpoint? Check api.sap.com Try Out tab).

SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
if (cfg == null || String.isBlank(cfg.API_Key__c) || cfg.API_Key__c == 'PASTE_YOUR_SAP_API_HUB_API_KEY_HERE') {
    System.debug('FAIL: SAP_Config__c missing or has placeholder API Key.');
    System.debug('Run scripts/setup_sap_config.apex with your real API Key first.');
    return;
}

HttpRequest req = new HttpRequest();
req.setEndpoint(cfg.API_Base_URL__c + '/s4hanacloud/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner?$top=5&$format=json');
req.setMethod('GET');
req.setHeader('APIKey', cfg.API_Key__c);
req.setHeader('Accept', 'application/json');
req.setTimeout(60000);

System.debug('Calling: ' + req.getEndpoint());

try {
    HttpResponse resp = new Http().send(req);
    System.debug('HTTP status: ' + resp.getStatusCode());

    if (resp.getStatusCode() == 200) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
        Map<String, Object> d = (Map<String, Object>) body.get('d');
        List<Object> results = (List<Object>) d.get('results');
        System.debug('SUCCESS — fetched ' + results.size() + ' Business Partners from SAP S/4HANA Cloud Sandbox');
        for (Object r : results) {
            Map<String, Object> bp = (Map<String, Object>) r;
            String bpId = String.valueOf(bp.get('BusinessPartner'));
            String bpName = String.valueOf(bp.get('BusinessPartnerFullName'));
            String bpCategory = String.valueOf(bp.get('BusinessPartnerCategory'));
            System.debug('  BP ' + bpId + ' [' + bpCategory + '] / ' + bpName);
        }
    } else {
        System.debug('FAIL — HTTP ' + resp.getStatusCode() + ': ' + resp.getBody().abbreviate(500));
    }
} catch (Exception e) {
    System.debug('FAIL — Exception: ' + e.getTypeName() + ' — ' + e.getMessage());
}

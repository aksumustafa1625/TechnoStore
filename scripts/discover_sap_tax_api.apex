// Discover what tax-related APIs exist in the SAP API Hub Sandbox.
// Try a few candidate endpoints and see which respond.
SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
String baseUrl = cfg.API_Base_URL__c;
if (!baseUrl.startsWith('http')) baseUrl = 'https://' + baseUrl;

List<String> candidatePaths = new List<String>{
    '/s4hanacloud/sap/opu/odata/sap/API_DETERMINE_TAX_SRV/$metadata',
    '/s4hanacloud/sap/opu/odata/sap/API_TAX_CALCULATION/$metadata',
    '/s4hanacloud/sap/opu/odata/sap/API_TAXCALCULATION_SRV/$metadata',
    '/taxservice/$metadata',
    '/s4hanacloud/sap/opu/odata/sap/API_PRODUCT_SRV/$metadata',
    '/s4hanacloud/sap/opu/odata/sap/API_SALES_ORDER_SRV/$metadata'
};

for (String path : candidatePaths) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(baseUrl + path);
    req.setMethod('GET');
    req.setHeader('APIKey', cfg.API_Key__c);
    req.setHeader('Accept', 'application/xml');
    req.setHeader('Accept-Encoding', 'identity');
    req.setTimeout(15000);
    try {
        HttpResponse resp = new Http().send(req);
        System.debug(resp.getStatusCode() + ' ← ' + path);
        if (resp.getStatusCode() == 200) {
            String body = resp.getBody();
            // Just dump first 300 chars to confirm we got real metadata
            System.debug('  preview: ' + body.abbreviate(200));
        }
    } catch (Exception e) {
        System.debug('EXC  ← ' + path + ' / ' + e.getMessage());
    }
}

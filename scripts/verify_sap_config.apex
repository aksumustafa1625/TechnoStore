// Verify SAP_Config__c Custom Setting is populated + Remote Site is active
SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
if (cfg == null) {
    System.debug('FAIL: SAP_Config__c Org Defaults record does NOT exist');
    return;
}
System.debug('SAP_Config exists:');
System.debug('  API_Base_URL__c = ' + cfg.API_Base_URL__c);
System.debug('  API_Key__c populated = ' + (String.isNotBlank(cfg.API_Key__c) ? 'YES (length=' + cfg.API_Key__c.length() + ')' : 'NO'));

// Remote Site Setting is configured (see force-app/main/default/remoteSiteSettings/SAP_API_Hub.remoteSite-meta.xml)
// — RemoteProxy isn't queryable in this org's API; trusting the metadata.
System.debug('Remote Site SAP_API_Hub assumed active (deployed via metadata)');

// Quick callout sanity check — call SAP BP API directly from Apex
if (String.isNotBlank(cfg.API_Base_URL__c) && String.isNotBlank(cfg.API_Key__c)) {
    String baseUrl = cfg.API_Base_URL__c;
    if (!baseUrl.startsWith('http')) baseUrl = 'https://' + baseUrl;
    String endpoint = baseUrl + '/s4hanacloud/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner?$top=1&$format=json';

    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('GET');
    req.setHeader('APIKey', cfg.API_Key__c);
    req.setHeader('Accept', 'application/json');
    req.setHeader('Accept-Encoding', 'identity');
    req.setTimeout(30000);

    try {
        HttpResponse resp = new Http().send(req);
        System.debug('SAP BP query status: ' + resp.getStatusCode());
        String body = resp.getBody();
        if (body != null && body.length() > 600) body = body.substring(0, 600) + '...';
        System.debug('Body preview: ' + body);
    } catch (Exception e) {
        System.debug('Callout exception: ' + e.getTypeName() + ' - ' + e.getMessage());
    }
}

// Verify current SAP integration target URL
SAP_Config__c cfg = SAP_Config__c.getOrgDefaults();
System.debug('=== SAP_Config__c ORG DEFAULTS ===');
System.debug('Base URL: ' + cfg.API_Base_URL__c);
System.debug('API Key set: ' + (String.isNotBlank(cfg.API_Key__c) ? 'YES (len=' + cfg.API_Key__c.length() + ')' : 'NO'));
System.debug('');

if (cfg.API_Base_URL__c != null) {
    if (cfg.API_Base_URL__c.contains('api.sap.com')) {
        System.debug('>>> Target: PUBLIC SAP API HUB SANDBOX (api.sap.com)');
        System.debug('>>> Trial Fiori (my429998.s4hana.cloud.sap) will NOT see records from these calls');
    } else if (cfg.API_Base_URL__c.contains('s4hana.cloud.sap')) {
        System.debug('>>> Target: S/4HANA CLOUD TENANT');
        System.debug('>>> Trial Fiori WILL see records from these calls');
    } else if (cfg.API_Base_URL__c.contains('ngrok')) {
        System.debug('>>> Target: NGROK (likely Mule proxy)');
        System.debug('>>> Visibility depends on Mule downstream target');
    } else {
        System.debug('>>> Target: UNKNOWN URL pattern');
    }
}

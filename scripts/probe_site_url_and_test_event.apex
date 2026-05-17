// Get DocuSign_Webhook Site's actual SecureUrl
Id siteId;
for (Site s : [SELECT Id FROM Site WHERE Name='DocuSign_Webhook' LIMIT 1]) {
    siteId = s.Id;
}
System.debug('SiteId=' + siteId);

if (siteId != null) {
    for (SiteDetail sd : [SELECT DurableId, SecureUrl FROM SiteDetail WHERE DurableId = :siteId LIMIT 1]) {
        System.debug('SecureUrl=' + sd.SecureUrl);
    }
    // Try with String cast
    String sidStr = String.valueOf(siteId);
    for (SiteDetail sd : [SELECT DurableId, SecureUrl FROM SiteDetail WHERE DurableId = :sidStr LIMIT 1]) {
        System.debug('SecureUrl(str)=' + sd.SecureUrl);
    }
}

System.debug('OrgDomainUrl=' + URL.getOrgDomainUrl().toExternalForm());

// Get the public domain for the DocuSign_Webhook site so we can build the WhatsApp webhook URL.
System.debug('=== DomainSite for DocuSign_Webhook ===');
try {
    for (DomainSite ds : [SELECT Domain.Domain, Site.Name, PathPrefix FROM DomainSite WHERE Site.Name = 'DocuSign_Webhook']) {
        System.debug('  domain=' + ds.Domain.Domain + ' | site=' + ds.Site.Name + ' | prefix=' + ds.PathPrefix);
        System.debug('  >>> Webhook URL base: https://' + ds.Domain.Domain + (String.isBlank(ds.PathPrefix) ? '' : ds.PathPrefix));
    }
} catch (Exception e) {
    System.debug('DomainSite query failed: ' + e.getMessage());
}

// Confirm the guest user now has WhatsApp class access via the perm set
System.debug('=== WhatsApp class access for DocuSign guest user ===');
for (SetupEntityAccess sea : [
    SELECT SetupEntityId, Parent.Name FROM SetupEntityAccess
    WHERE Parent.Name = 'Inventory_Webhook_Access' AND SetupEntityType = 'ApexClass'
]) {
    System.debug('  perm set grants ApexClass id: ' + sea.SetupEntityId);
}

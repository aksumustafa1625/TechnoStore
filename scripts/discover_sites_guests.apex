// Discover existing Sites + guest users + the webhook permission set, to wire WhatsApp guest access.
System.debug('=== SITES ===');
try {
    for (Site s : [SELECT Id, Name, Subdomain, UrlPathPrefix, Status, MasterLabel FROM Site]) {
        System.debug('  Site: ' + s.Name + ' | label=' + s.MasterLabel + ' | subdomain=' + s.Subdomain
            + ' | prefix=' + s.UrlPathPrefix + ' | status=' + s.Status);
    }
} catch (Exception e) { System.debug('Site query failed: ' + e.getMessage()); }

System.debug('=== GUEST USERS ===');
for (User u : [SELECT Id, Name, Username, Profile.Name FROM User WHERE UserType = 'Guest']) {
    System.debug('  Guest: ' + u.Name + ' | profile=' + u.Profile.Name + ' | id=' + u.Id);
}

System.debug('=== PERM SET ===');
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name = 'Inventory_Webhook_Access']) {
    System.debug('  ' + ps.Name + ' = ' + ps.Id);
}

System.debug('=== EXISTING ASSIGNMENTS of Inventory_Webhook_Access ===');
for (PermissionSetAssignment psa : [
    SELECT Assignee.Name, Assignee.UserType FROM PermissionSetAssignment
    WHERE PermissionSet.Name = 'Inventory_Webhook_Access'
]) {
    System.debug('  -> ' + psa.Assignee.Name + ' (' + psa.Assignee.UserType + ')');
}

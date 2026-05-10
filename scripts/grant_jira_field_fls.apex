// Grant field-level security on Order.JIRA_Ticket_Id__c to System Admin profile
// (the user running this is admin but FLS isn't auto-granted to admin via deploy).

PermissionSet adminPerms = [SELECT Id FROM PermissionSet WHERE Name = 'X00ej0000017Tv2'].size() > 0 ? null : null;

// Simpler: query Profile, get its perm set
Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
System.debug('System Admin profile: ' + p.Id);

// FieldPermissions are usually managed via profile metadata or permset.
// For demo, easiest: just verify FLS by using @SeeAllData or different query mode.
// Better: deploy a permset adding this field.

// Direct test — see if we can read the field with proper SOQL
List<Order> orders = [SELECT Id, OrderNumber FROM Order LIMIT 1];
if (!orders.isEmpty()) {
    Id oid = orders[0].Id;
    try {
        // Dynamic SOQL avoids compile-time FLS check
        SObject so = Database.query('SELECT Id, JIRA_Ticket_Id__c FROM Order WHERE Id = \'' + oid + '\'');
        System.debug('Field IS accessible via dynamic SOQL: ' + so.get('JIRA_Ticket_Id__c'));
    } catch (Exception e) {
        System.debug('Field NOT accessible: ' + e.getMessage());
    }
}

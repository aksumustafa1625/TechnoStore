// Grant FLS for the 4 new VAT formula fields to System Administrator profile
// Uses FieldPermissions DML

// Find System Administrator PermissionSet (every profile has a paired PermissionSet)
List<PermissionSet> sysAdminPS = [
    SELECT Id, Name, ProfileId, Profile.Name
    FROM PermissionSet
    WHERE IsOwnedByProfile = true AND Profile.Name = 'System Administrator'
    LIMIT 1
];
System.debug('SysAdmin PermissionSet: ' + sysAdminPS);

if (sysAdminPS.isEmpty()) {
    System.debug('ERROR: SysAdmin permission set not found');
    return;
}

Id psId = sysAdminPS[0].Id;
List<String> fieldsToGrant = new List<String>{
    'Quote.Estimated_VAT_19_Percent__c',
    'Quote.Total_With_Estimated_VAT__c',
    'QuoteLineItem.Estimated_VAT_Amount__c',
    'QuoteLineItem.Total_With_Estimated_VAT__c'
};

// Check existing
Map<String, FieldPermissions> existing = new Map<String, FieldPermissions>();
for (FieldPermissions fp : [
    SELECT Id, Field, ParentId, PermissionsRead, PermissionsEdit
    FROM FieldPermissions
    WHERE ParentId = :psId AND Field IN :fieldsToGrant
]) {
    existing.put(fp.Field, fp);
}

List<FieldPermissions> toUpsert = new List<FieldPermissions>();
for (String fld : fieldsToGrant) {
    if (existing.containsKey(fld)) {
        FieldPermissions fp = existing.get(fld);
        fp.PermissionsRead = true;
        fp.PermissionsEdit = false; // formula fields are read-only
        toUpsert.add(fp);
    } else {
        FieldPermissions fp = new FieldPermissions();
        fp.ParentId = psId;
        fp.Field = fld;
        fp.SobjectType = fld.substringBefore('.');
        fp.PermissionsRead = true;
        fp.PermissionsEdit = false;
        toUpsert.add(fp);
    }
}

upsert toUpsert;
System.debug('Granted FLS for ' + toUpsert.size() + ' fields');
for (FieldPermissions fp : toUpsert) System.debug('  ' + fp.Field + ' Read=' + fp.PermissionsRead);

// Assign critical Permission Sets for Browse Catalog / Product Discovery
String userId = '005000000000000XXX';

// Get the key permission sets
List<PermissionSet> psToAssign = [
    SELECT Id, Name, Label
    FROM PermissionSet
    WHERE Name IN (
        'ProductDiscoveryAdmin',
        'ProductDiscoveryUser',
        'ProductCatalogManagementAdministrator',
        'ProductCatalogManagementViewer',
        'RevLifecycleManagementProductAndPriceConfigurationApi',
        'IndustriesConfiguratorPlatformApi'
    )
    AND IsOwnedByProfile = false
];

System.debug('Found ' + psToAssign.size() + ' permission sets to assign');

// Check which are already assigned
Set<Id> alreadyAssigned = new Set<Id>();
for (PermissionSetAssignment psa : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :userId]) {
    alreadyAssigned.add(psa.PermissionSetId);
}

List<PermissionSetAssignment> newAssignments = new List<PermissionSetAssignment>();
for (PermissionSet ps : psToAssign) {
    if (!alreadyAssigned.contains(ps.Id)) {
        PermissionSetAssignment psa = new PermissionSetAssignment();
        psa.AssigneeId = userId;
        psa.PermissionSetId = ps.Id;
        newAssignments.add(psa);
        System.debug('Will assign: ' + ps.Name + ' (' + ps.Label + ')');
    } else {
        System.debug('Already assigned: ' + ps.Name);
    }
}

if (!newAssignments.isEmpty()) {
    insert newAssignments;
    System.debug('SUCCESS: Assigned ' + newAssignments.size() + ' permission sets');
} else {
    System.debug('All permission sets already assigned');
}

// Verify
List<PermissionSetAssignment> verify = [
    SELECT PermissionSet.Name, PermissionSet.Label
    FROM PermissionSetAssignment
    WHERE AssigneeId = :userId
    AND PermissionSet.IsOwnedByProfile = false
    ORDER BY PermissionSet.Name
];
System.debug('=== Final PS assignments:');
for (PermissionSetAssignment psa : verify) {
    System.debug('  Assigned: ' + psa.PermissionSet.Name + ' | ' + psa.PermissionSet.Label);
}

// Force assign permission sets - check actual count and try insert
String userId = '005aj00000UuoAYAAZ';

// Count ALL PSA records for user
List<PermissionSetAssignment> allPSA = [
    SELECT Id, PermissionSetId, PermissionSet.Name, PermissionSet.Label,
           PermissionSet.IsOwnedByProfile, PermissionSet.NamespacePrefix
    FROM PermissionSetAssignment
    WHERE AssigneeId = :userId
];
System.debug('=== TOTAL PSA records for user: ' + allPSA.size());
for (PermissionSetAssignment psa : allPSA) {
    System.debug('  PSA: ' + psa.PermissionSet.Name + ' | Profile=' + psa.PermissionSet.IsOwnedByProfile + ' | NS=' + psa.PermissionSet.NamespacePrefix);
}

// Now try to assign ProductDiscoveryAdmin
PermissionSet pdAdmin = [SELECT Id, Name FROM PermissionSet WHERE Name = 'ProductDiscoveryAdmin' AND IsOwnedByProfile = false LIMIT 1];
System.debug('=== ProductDiscoveryAdmin PS Id: ' + pdAdmin.Id);

// Check if already assigned
List<PermissionSetAssignment> existing = [
    SELECT Id FROM PermissionSetAssignment
    WHERE AssigneeId = :userId AND PermissionSetId = :pdAdmin.Id
];
System.debug('=== Existing PSA for ProductDiscoveryAdmin: ' + existing.size());

if (existing.isEmpty()) {
    try {
        PermissionSetAssignment psa = new PermissionSetAssignment();
        psa.AssigneeId = userId;
        psa.PermissionSetId = pdAdmin.Id;
        insert psa;
        System.debug('SUCCESS: Assigned ProductDiscoveryAdmin');
    } catch (Exception e) {
        System.debug('ERROR assigning: ' + e.getMessage());
    }
} else {
    System.debug('ProductDiscoveryAdmin already explicitly assigned');
}

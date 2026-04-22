// Check user permissions, feature settings, and license assignments
// for Browse Catalog / Product Discovery

String userId = '005aj00000UuoAYAAZ'; // technostore-admin@example.com

// 1. Check Permission Set Assignments for the user
List<PermissionSetAssignment> psas = [
    SELECT Id, PermissionSetId, PermissionSet.Name, PermissionSet.Label, PermissionSet.IsOwnedByProfile
    FROM PermissionSetAssignment
    WHERE AssigneeId = :userId
    ORDER BY PermissionSet.Name
];
System.debug('=== Permission Sets assigned to user: ' + psas.size());
for (PermissionSetAssignment psa : psas) {
    if (!psa.PermissionSet.IsOwnedByProfile) {
        System.debug('PS: ' + psa.PermissionSet.Name + ' | Label: ' + psa.PermissionSet.Label);
    }
}

// 2. Check for Revenue Cloud / Industries CPQ related permission sets
List<PermissionSet> revPS = [
    SELECT Id, Name, Label, NamespacePrefix
    FROM PermissionSet
    WHERE (Name LIKE '%Revenue%' OR Name LIKE '%CPQ%' OR Name LIKE '%Product%'
           OR Name LIKE '%Catalog%' OR Name LIKE '%Browse%' OR Name LIKE '%Discovery%'
           OR Name LIKE '%Industries%' OR Name LIKE '%EPC%' OR Name LIKE '%Commerce%')
    AND IsOwnedByProfile = false
    ORDER BY Name
];
System.debug('=== Revenue/CPQ/Product related Permission Sets: ' + revPS.size());
for (PermissionSet ps : revPS) {
    // Check if assigned to user
    Boolean assigned = false;
    for (PermissionSetAssignment psa : psas) {
        if (psa.PermissionSetId == ps.Id) { assigned = true; break; }
    }
    System.debug('PS: ' + ps.Name + ' | NS: ' + ps.NamespacePrefix + ' | Assigned: ' + assigned);
}

// 3. Check Custom Permissions assigned to user
List<SetupEntityAccess> customPerms = [
    SELECT SetupEntityId, SetupEntityType, ParentId, Parent.Name
    FROM SetupEntityAccess
    WHERE SetupEntityType = 'CustomPermission'
    AND ParentId IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :userId)
];
System.debug('=== Custom Permissions via PS: ' + customPerms.size());
for (SetupEntityAccess sea : customPerms) {
    System.debug('CustomPerm: ' + sea.SetupEntityId + ' | Via PS: ' + sea.Parent.Name);
}

// 4. Check ALL Custom Permissions in the org
List<CustomPermission> allCustomPerms = [
    SELECT Id, DeveloperName, MasterLabel, NamespacePrefix
    FROM CustomPermission
    WHERE (DeveloperName LIKE '%Product%' OR DeveloperName LIKE '%Catalog%'
           OR DeveloperName LIKE '%Browse%' OR DeveloperName LIKE '%Revenue%'
           OR DeveloperName LIKE '%Discovery%' OR DeveloperName LIKE '%CPQ%')
    ORDER BY DeveloperName
];
System.debug('=== Custom Permissions (Product/Catalog related): ' + allCustomPerms.size());
for (CustomPermission cp : allCustomPerms) {
    System.debug('CP: ' + cp.DeveloperName + ' | NS: ' + cp.NamespacePrefix + ' | Label: ' + cp.MasterLabel);
}

// 5. Check User License
User u = [SELECT Id, Name, Profile.Name, UserType, Profile.UserLicense.Name FROM User WHERE Id = :userId];
System.debug('=== User Profile: ' + u.Profile.Name + ' | License: ' + u.Profile.UserLicense.Name);

// 6. Check ALL Custom Permissions in org (not just filtered)
List<CustomPermission> allCPs = [
    SELECT Id, DeveloperName, MasterLabel, NamespacePrefix
    FROM CustomPermission
    ORDER BY DeveloperName
    LIMIT 50
];
System.debug('=== ALL Custom Permissions in org: ' + allCPs.size());
for (CustomPermission cp : allCPs) {
    System.debug('AllCP: ' + cp.DeveloperName + ' | NS: ' + cp.NamespacePrefix + ' | ' + cp.MasterLabel);
}

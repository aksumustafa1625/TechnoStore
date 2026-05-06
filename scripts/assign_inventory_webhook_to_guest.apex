// Assign Inventory_Webhook_Access permission set to the DocuSign Webhook Site Guest User.
// This guest user is the principal that runs the Apex REST callback when MuleSoft hits
// /services/apexrest/inventory/callback through the public Site URL.

Id guestUserId = '005xx0000000000XXX'; // DocuSign Webhook Site guest user (reused)

PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Inventory_Webhook_Access' LIMIT 1];

// Skip if already assigned
List<PermissionSetAssignment> existing = [
    SELECT Id FROM PermissionSetAssignment
    WHERE AssigneeId = :guestUserId AND PermissionSetId = :ps.Id
];
if (!existing.isEmpty()) {
    System.debug('Permission set already assigned. Nothing to do.');
    return;
}

PermissionSetAssignment psa = new PermissionSetAssignment(
    AssigneeId = guestUserId,
    PermissionSetId = ps.Id
);
insert psa;
System.debug('Assigned Inventory_Webhook_Access to guest user ' + guestUserId);

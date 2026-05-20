// Test send to the user's verified email (demo-user@example.com)
// AND check daily email limits + bounced addresses
// If THIS mail arrives but previous test didn't, the recipient demo-recipient@example.com
// is on a bounce list. If THIS also fails, the issue is system-wide.

System.debug('=== DAILY EMAIL LIMIT ===');
System.OrgLimit emailLimit = OrgLimits.getMap().get('SingleEmail');
if (emailLimit != null) {
    System.debug('SingleEmail: ' + emailLimit.getValue() + ' / ' + emailLimit.getLimit());
}
System.OrgLimit massEmailLimit = OrgLimits.getMap().get('MassEmail');
if (massEmailLimit != null) {
    System.debug('MassEmail: ' + massEmailLimit.getValue() + ' / ' + massEmailLimit.getLimit());
}

System.debug('=== ATTEMPTING SEND TO VERIFIED USER EMAIL ===');
Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
mail.setToAddresses(new String[]{ 'demo-user@example.com' });
mail.setSubject('Verified-Addr Test ' + System.now().format('HH:mm:ss'));
mail.setPlainTextBody(
    'If this email arrives, substitute address fix is working.\n' +
    'Test sent at: ' + System.now() + '\n' +
    'Org ID: ' + UserInfo.getOrganizationId()
);

Messaging.SendEmailResult[] results = Messaging.sendEmail(
    new Messaging.SingleEmailMessage[]{ mail }, false  // allOrNone = false
);

for (Messaging.SendEmailResult r : results) {
    System.debug('Success: ' + r.isSuccess());
    if (!r.isSuccess()) {
        for (Messaging.SendEmailError err : r.getErrors()) {
            System.debug('  ERROR: ' + err.getStatusCode() + ' | ' + err.getMessage());
        }
    } else {
        System.debug('✅ Email queued successfully');
    }
}

// Check if demo-recipient@example.com is on a Contact with bounce flag
System.debug('=== CHECKING BOUNCE STATUS FOR PREVIOUS RECIPIENT ===');
List<Contact> bouncedContacts = [
    SELECT Id, Name, Email, EmailBouncedReason, EmailBouncedDate
    FROM Contact
    WHERE Email = 'demo-recipient@example.com'
    LIMIT 5
];
if (bouncedContacts.isEmpty()) {
    System.debug('No Contact with email demo-recipient@example.com (so no Contact-level bounce)');
} else {
    for (Contact c : bouncedContacts) {
        System.debug('Contact: ' + c.Name + ' | BouncedReason: ' + c.EmailBouncedReason +
                     ' | BouncedDate: ' + c.EmailBouncedDate);
    }
}

// Diagnose why test email didn't arrive
// Checks: user email verification status, deliverability access, recent email errors

User me = [
    SELECT Id, Username, Email, Name, IsActive,
           IsEmailConfirmed
    FROM User
    WHERE Id = :UserInfo.getUserId()
    LIMIT 1
];

System.debug('=== USER STATUS ===');
System.debug('Name: ' + me.Name);
System.debug('Username: ' + me.Username);
System.debug('Email: ' + me.Email);
System.debug('IsActive: ' + me.IsActive);
System.debug('IsEmailConfirmed: ' + me.IsEmailConfirmed);

System.debug('=== ORG INFO ===');
System.debug('Org ID: ' + UserInfo.getOrganizationId());

System.debug('=== EMAIL LIMITS ===');
System.OrgLimit emailLimit = OrgLimits.getMap().get('SingleEmail');
if (emailLimit != null) {
    System.debug('SingleEmail used: ' + emailLimit.getValue() + ' / ' + emailLimit.getLimit());
}

// Check recent EmailMessage records (related to outbound)
System.debug('=== RECENT EMAILMESSAGE RECORDS (last 10) ===');
try {
    List<EmailMessage> recent = [
        SELECT Id, Subject, Status, MessageDate, ToAddress, FromAddress, FromName, HasAttachment
        FROM EmailMessage
        WHERE MessageDate >= :System.now().addHours(-1)
        ORDER BY MessageDate DESC
        LIMIT 10
    ];
    System.debug('Found ' + recent.size() + ' EmailMessage records in last hour');
    for (EmailMessage em : recent) {
        System.debug('  - ' + em.MessageDate + ' | Status=' + em.Status +
                     ' | To=' + em.ToAddress + ' | From=' + em.FromAddress +
                     ' | Subject=' + em.Subject);
    }
} catch (Exception e) {
    System.debug('EmailMessage query failed: ' + e.getMessage());
}

// Try sending with explicit ReplyTo to verified address
System.debug('=== ATTEMPTING TEST SEND WITH EXPLICIT REPLY-TO ===');
Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
mail.setToAddresses(new String[]{ 'demo-recipient@example.com' });
mail.setReplyTo(me.Email);
mail.setSenderDisplayName('TechnoStore Demo');
mail.setSubject('Diag Test ' + System.now().format('HH:mm:ss'));
mail.setPlainTextBody('Diagnostic test mail. If you see this, deliverability is fixed.');

Messaging.SendEmailResult[] results = Messaging.sendEmail(
    new Messaging.SingleEmailMessage[]{ mail }, false
);

for (Messaging.SendEmailResult r : results) {
    System.debug('Success: ' + r.isSuccess());
    if (!r.isSuccess()) {
        for (Messaging.SendEmailError err : r.getErrors()) {
            System.debug('  ERROR: ' + err.getStatusCode() + ' | ' + err.getMessage());
            System.debug('  TargetObjectId: ' + err.getTargetObjectId());
        }
    }
}

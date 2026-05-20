// Verify substitute email address is working post-Deliverability change.
// Expected: receives a test email at demo-recipient@example.com
// From address will be <something>@<orgid>.sfcustomeremail.com (Salesforce-managed)

Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
mail.setToAddresses(new String[]{ 'demo-recipient@example.com' });
mail.setSubject('TechnoStore Deliverability Test - ' + System.now().format('HH:mm:ss'));
mail.setPlainTextBody(
    'If you receive this email, the substitute email address fix is working.\n\n' +
    'Sent from Salesforce org: ' + UserInfo.getOrganizationId() + '\n' +
    'User: ' + UserInfo.getName() + ' (' + UserInfo.getUserEmail() + ')\n' +
    'Timestamp: ' + System.now()
);

Messaging.SendEmailResult[] results = Messaging.sendEmail(
    new Messaging.SingleEmailMessage[]{ mail }
);

for (Messaging.SendEmailResult r : results) {
    if (r.isSuccess()) {
        System.debug('✅ EMAIL SENT - substitute address working');
    } else {
        System.debug('❌ EMAIL FAILED:');
        for (Messaging.SendEmailError err : r.getErrors()) {
            System.debug('  - ' + err.getStatusCode() + ': ' + err.getMessage());
        }
    }
}

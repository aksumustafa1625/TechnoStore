SObject inv = Database.query(
    'SELECT Id, DocumentNumber, Stripe_Payment_Status__c, Lexoffice_Status__c, Lexoffice_Invoice_Id__c, Lexoffice_Published_At__c ' +
    'FROM Invoice WHERE DocumentNumber = \'DOC-000000001\' LIMIT 1'
);
System.debug('=== TRIGGER VERIFY ===');
System.debug('  DocumentNumber: ' + inv.get('DocumentNumber'));
System.debug('  Stripe_Payment_Status__c: ' + inv.get('Stripe_Payment_Status__c'));
System.debug('  Lexoffice_Status__c: ' + inv.get('Lexoffice_Status__c'));
System.debug('  Lexoffice_Invoice_Id__c: ' + inv.get('Lexoffice_Invoice_Id__c'));
System.debug('  Lexoffice_Published_At__c: ' + inv.get('Lexoffice_Published_At__c'));
if (inv.get('Lexoffice_Status__c') == 'Published') {
    System.debug('>>> SUCCESS: trigger auto-published to lexoffice on payment!');
} else {
    System.debug('>>> Still pending or @future not finished — re-run in a few seconds.');
}

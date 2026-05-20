// Test InvoiceTrigger touching ONLY Stripe_Payment_Status__c (old field, no cache lag).
// Use DOC-000000001 whose Lexoffice_Status__c is null (idempotency: null != 'Published' -> fires).
// The compiled trigger + LexofficeInvoiceService handle the new Lexoffice_* fields fine.
SObject inv = Database.query(
    'SELECT Id, DocumentNumber FROM Invoice WHERE DocumentNumber = \'DOC-000000001\' LIMIT 1'
);
Id invId = (Id) inv.get('Id');
System.debug('Target: ' + inv.get('DocumentNumber') + ' (' + invId + ')');

SObject s1 = Schema.getGlobalDescribe().get('Invoice').newSObject();
s1.put('Id', invId); s1.put('Stripe_Payment_Status__c', 'Sent');
update s1;
System.debug('Set Stripe_Payment_Status__c = Sent.');

SObject s2 = Schema.getGlobalDescribe().get('Invoice').newSObject();
s2.put('Id', invId); s2.put('Stripe_Payment_Status__c', 'Paid');
update s2;
System.debug('>>> Set Stripe_Payment_Status__c = Paid. Trigger should enqueue @future lexoffice publish.');
System.debug('>>> Invoice Id: ' + invId);

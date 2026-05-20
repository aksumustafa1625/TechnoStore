// Test lexoffice publish for demo invoice INV-0007 (Main Capital IT-Partners GmbH).
// Calls the deployed LexofficeInvoiceService (already compiled — bypasses anon schema cache).
List<Demo_Invoice__c> invs = [
    SELECT Id, Name FROM Demo_Invoice__c WHERE Order__c IN (SELECT Id FROM Order WHERE OrderNumber = '00000170') LIMIT 1
];
if (invs.isEmpty()) { System.debug('Demo invoice not found — run create_demo_invoice_lexoffice.apex first'); return; }
Id invoiceId = invs[0].Id;
System.debug('Publishing ' + invs[0].Name + ' (' + invoiceId + ') to lexoffice...');

LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(invoiceId);
System.debug('=== LEXOFFICE PUBLISH RESULT ===');
System.debug('  status: ' + r.status);
System.debug('  lexofficeInvoiceId: ' + r.lexofficeInvoiceId);
System.debug('  message: ' + r.message);

if (r.status == 'Success') {
    System.debug('>>> SUCCESS — open lexoffice web UI, the invoice should appear under Rechnungen.');
}

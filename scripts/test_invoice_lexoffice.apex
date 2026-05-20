// Test refactored lexoffice publish against standard Invoice DOC-000000002 (Posted)
List<Invoice> invs = [SELECT Id, DocumentNumber FROM Invoice WHERE Status = 'Posted' ORDER BY CreatedDate DESC LIMIT 1];
if (invs.isEmpty()) { invs = [SELECT Id, DocumentNumber FROM Invoice ORDER BY CreatedDate DESC LIMIT 1]; }
if (invs.isEmpty()) { System.debug('No Invoice'); return; }
Id invoiceId = invs[0].Id;
System.debug('lexoffice publish for ' + invs[0].DocumentNumber + ' (' + invoiceId + ')');

LexofficeInvoiceService.Result r = LexofficeInvoiceService.publishFromButton(invoiceId);
System.debug('=== LEXOFFICE RESULT ===');
System.debug('  status: ' + r.status);
System.debug('  lexofficeInvoiceId: ' + r.lexofficeInvoiceId);
System.debug('  message: ' + r.message);

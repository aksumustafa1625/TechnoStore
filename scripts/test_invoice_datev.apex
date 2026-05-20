// Test refactored DATEV export against standard Invoice DOC-000000002 (Posted)
List<Invoice> invs = [SELECT Id, DocumentNumber FROM Invoice WHERE Status = 'Posted' ORDER BY CreatedDate DESC LIMIT 1];
if (invs.isEmpty()) { invs = [SELECT Id, DocumentNumber FROM Invoice ORDER BY CreatedDate DESC LIMIT 1]; }
if (invs.isEmpty()) { System.debug('No Invoice'); return; }
Id invoiceId = invs[0].Id;
System.debug('DATEV export for ' + invs[0].DocumentNumber + ' (' + invoiceId + ')');

DatevExportService.Result r = DatevExportService.exportFromButton(invoiceId);
System.debug('=== DATEV RESULT ===');
System.debug('  status: ' + r.status);
System.debug('  fileName: ' + r.fileName);
System.debug('  message: ' + r.message);
if (r.csvPreview != null) {
    for (String line : r.csvPreview.split('\r\n')) System.debug('  CSV: ' + line);
}

// Test DATEV Buchungsstapel CSV export for INV-0007 (Main Capital IT-Partners GmbH).
List<Demo_Invoice__c> invs = [
    SELECT Id, Name FROM Demo_Invoice__c WHERE Order__c IN (SELECT Id FROM Order WHERE OrderNumber = '00000170') LIMIT 1
];
if (invs.isEmpty()) { System.debug('Demo invoice not found'); return; }
Id invoiceId = invs[0].Id;
System.debug('Exporting ' + invs[0].Name + ' to DATEV CSV...');

DatevExportService.Result r = DatevExportService.exportFromButton(invoiceId);
System.debug('=== DATEV EXPORT RESULT ===');
System.debug('  status: ' + r.status);
System.debug('  fileName: ' + r.fileName);
System.debug('  contentVersionId: ' + r.contentVersionId);
System.debug('  message: ' + r.message);
System.debug('=== CSV PREVIEW ===');
System.debug('\n' + r.csvPreview);

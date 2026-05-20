// Reproduce the DATEV button failure and capture the FULL error message.
// Try the most-recently-modified Invoice (what the user is viewing).
List<Invoice> invs = [SELECT Id, DocumentNumber, Status FROM Invoice ORDER BY LastModifiedDate DESC LIMIT 3];
for (Invoice i : invs) {
    System.debug('--- Trying ' + i.DocumentNumber + ' (Status=' + i.Status + ') ---');
    DatevExportService.Result r = DatevExportService.exportFromButton(i.Id);
    System.debug('  status: ' + r.status);
    System.debug('  message: ' + r.message);
    System.debug('  fileName: ' + r.fileName);
}

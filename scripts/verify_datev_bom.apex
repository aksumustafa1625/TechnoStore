// Generate a fresh DATEV export and confirm the attached file starts with UTF-8 BOM (EF BB BF).
Invoice inv = [SELECT Id, DocumentNumber FROM Invoice ORDER BY CreatedDate DESC LIMIT 1];
DatevExportService.Result r = DatevExportService.exportFromButton(inv.Id);
System.debug('Export status: ' + r.status + ' | file: ' + r.fileName);

ContentVersion cv = [
    SELECT VersionData FROM ContentVersion WHERE Id = :r.contentVersionId LIMIT 1
];
String hexPrefix = EncodingUtil.convertToHex(cv.VersionData).substring(0, 6).toUpperCase();
System.debug('First 3 bytes (hex): ' + hexPrefix);
if (hexPrefix == 'EFBBBF') {
    System.debug('>>> BOM present — Excel/DATEV will read UTF-8 correctly, umlauts render properly.');
} else {
    System.debug('>>> BOM missing, got: ' + hexPrefix);
}

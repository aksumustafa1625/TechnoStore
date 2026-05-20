ContentVersion cv = [
    SELECT Id, Title, VersionData FROM ContentVersion
    WHERE Id = '068aj00000J9df7AAB' LIMIT 1
];
String csv = cv.VersionData.toString();
System.debug('=== ' + cv.Title + ' ===');
// Print line by line so newlines survive the debug log
for (String line : csv.split('\r\n')) {
    System.debug('LINE: ' + line);
}

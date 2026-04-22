// Clear QuoteProposedDuration__c on all PCQ records
// The default "Short" value was auto-set and restricts products to Short Term quotes only
// Setting to null makes categories available for ALL quote durations

List<ProductCategoryQualification> pcqs = [
    SELECT Id, CategoryId, QuoteProposedDuration__c, IsQualified
    FROM ProductCategoryQualification
];
System.debug('Total PCQ records: ' + pcqs.size());

// Count how many have Duration set
Integer shortCount = 0;
Integer nullCount = 0;
for (ProductCategoryQualification pcq : pcqs) {
    if (pcq.QuoteProposedDuration__c != null) {
        shortCount++;
        pcq.QuoteProposedDuration__c = null;  // Clear to make available for all durations
    } else {
        nullCount++;
    }
}
System.debug('PCQ with Duration set (clearing): ' + shortCount);
System.debug('PCQ with Duration null (keeping): ' + nullCount);

if (shortCount > 0) {
    update pcqs;
    System.debug('Updated ' + shortCount + ' PCQ records');
}

// Verify
List<ProductCategoryQualification> updated = [
    SELECT Id, CategoryId, IsQualified, QuoteProposedDuration__c
    FROM ProductCategoryQualification
    LIMIT 5
];
for (ProductCategoryQualification pcq : updated) {
    System.debug('PCQ: Category=' + pcq.CategoryId + ', IsQualified=' + pcq.IsQualified + ', Duration=' + pcq.QuoteProposedDuration__c);
}

// Also check the Account for Test Quote 4 (which has an account)
Account acct = [SELECT Id, Name, Industry, NumberOfEmployees FROM Account WHERE Id = '001aj00002MpcooAAB'];
System.debug('Test Account: ' + acct.Name + ', Industry=' + acct.Industry + ', Employees=' + acct.NumberOfEmployees);

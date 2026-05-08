// For Premium Workstation Pro, simulate qualification check for each key demo account.
// Logic mirrors what the RLM engine does at catalog browse time:
//   - Account.NumberOfEmployees must be in [Min, Max] of ProductQualification
//   - Account.Industry must NOT appear in any active ProductDisqualification

Id productId = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-WS-PREMIUM' LIMIT 1].Id;

// Load qualification rule
ProductQualification pq = [SELECT MinNumberOfEmployees__c, MaxNumberOfEmployees__c FROM ProductQualification WHERE ProductId = :productId LIMIT 1];

// Load disqualified industries
Set<String> blockedIndustries = new Set<String>();
for (ProductDisqualification pdq : [SELECT Industry__c FROM ProductDisqualification WHERE ProductId = :productId]) {
    blockedIndustries.add(pdq.Industry__c);
}
System.debug('Premium Workstation Pro requires Min=' + pq.MinNumberOfEmployees__c + ' employees');
System.debug('Disqualified industries: ' + blockedIndustries);
System.debug('');

List<String> demoNames = new List<String>{
    'Hamburg DataWorks AG',
    'Köln Retail Cloud GmbH',
    'Frankfurt FinTech Hub GmbH',
    'München Industrial Systems GmbH',
    'Burlington Textiles Corp of America',
    'Grand Hotels & Resorts Ltd',
    'University of Arizona',
    'GenePoint',
    'United Oil & Gas Corp.',
    'EdgeMX'
};

System.debug('======== Qualification simulation per account ========');
for (Account a : [SELECT Name, Industry, NumberOfEmployees FROM Account WHERE Name IN :demoNames]) {
    Boolean industryOk = a.Industry != null && !blockedIndustries.contains(a.Industry);
    Boolean employeesOk = a.NumberOfEmployees != null
                          && a.NumberOfEmployees >= pq.MinNumberOfEmployees__c
                          && a.NumberOfEmployees <= pq.MaxNumberOfEmployees__c;
    String verdict = (industryOk && employeesOk) ? '✓ QUALIFIED'
                   : (!industryOk && !employeesOk) ? '✗ DISQUALIFIED (industry+employees)'
                   : (!industryOk) ? '✗ DISQUALIFIED (industry: ' + a.Industry + ' is blocked)'
                   : '✗ DISQUALIFIED (employees: ' + a.NumberOfEmployees + ' < min ' + pq.MinNumberOfEmployees__c + ')';
    System.debug('  ' + a.Name.rightPad(40) + ' | Industry=' + (a.Industry == null ? 'null' : a.Industry).rightPad(15) + ' | Emp=' + a.NumberOfEmployees + ' | ' + verdict);
}

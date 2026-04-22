// Fix ProductQualification employee bounds
// MaxNumberOfEmployees__c = null causes Decision Table condition
// "inputEmployees < MaxEmp" to always fail (null comparison)
// Similarly MinNumberOfEmployees__c = null causes "inputEmployees >= MinEmp" to fail

List<ProductQualification> pqs = [
    SELECT Id, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
];

Integer updatedMin = 0;
Integer updatedMax = 0;

for (ProductQualification pq : pqs) {
    if (pq.MinNumberOfEmployees__c == null) {
        pq.MinNumberOfEmployees__c = 0;
        updatedMin++;
    }
    if (pq.MaxNumberOfEmployees__c == null) {
        pq.MaxNumberOfEmployees__c = 999999;
        updatedMax++;
    }
}

if (!pqs.isEmpty()) {
    update pqs;
    System.debug('SUCCESS: Updated ' + pqs.size() + ' ProductQualification records');
    System.debug('Set MinEmp=0 for ' + updatedMin + ' records');
    System.debug('Set MaxEmp=999999 for ' + updatedMax + ' records');
}

// Verify
ProductQualification sample = [
    SELECT Id, ProductId, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    LIMIT 1
];
System.debug('Sample after fix: Min=' + sample.MinNumberOfEmployees__c + ', Max=' + sample.MaxNumberOfEmployees__c);
Integer stillNull = [SELECT COUNT() FROM ProductQualification WHERE MaxNumberOfEmployees__c = null];
System.debug('Still null MaxEmp: ' + stillNull);

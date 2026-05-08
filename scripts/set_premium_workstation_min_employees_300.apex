List<ProductQualification> quals = [
    SELECT Id, Product.ProductCode, MinNumberOfEmployees__c
    FROM ProductQualification
    WHERE Product.ProductCode IN ('COMP-WS-002', 'COMP-WS-PREMIUM', 'COMP-WS-STUDIO')
];

for (ProductQualification qual : quals) {
    qual.MinNumberOfEmployees__c = 300;
}

update quals;

System.debug('Updated premium workstation qualification records: ' + quals.size());
for (ProductQualification qual : [
    SELECT Id, Product.Name, Product.ProductCode, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE Product.ProductCode IN ('COMP-WS-002', 'COMP-WS-PREMIUM', 'COMP-WS-STUDIO')
    ORDER BY Product.ProductCode
]) {
    System.debug(qual.Product.ProductCode + ' | ' + qual.Product.Name + ' | Min=' + qual.MinNumberOfEmployees__c + ' Max=' + qual.MaxNumberOfEmployees__c);
}

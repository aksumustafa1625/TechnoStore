List<ProductQualification> pqs = [
    SELECT Id, Product.ProductCode, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE Product.ProductCode IN ('REG01', 'POS01', 'ENPOS101', 'SCN01')
];

for (ProductQualification pq : pqs) {
    pq.MinNumberOfEmployees__c = 0;
    pq.MaxNumberOfEmployees__c = 999999;
}

update pqs;

for (ProductQualification pq : [
    SELECT Id, Product.Name, Product.ProductCode, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE Product.ProductCode IN ('REG01', 'POS01', 'ENPOS101', 'SCN01')
    ORDER BY Product.ProductCode
]) {
    System.debug(pq.Product.ProductCode + ' | Min=' + pq.MinNumberOfEmployees__c + ' Max=' + pq.MaxNumberOfEmployees__c);
}

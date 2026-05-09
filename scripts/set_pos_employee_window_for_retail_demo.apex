// Make the POS Solutions demo reliable in Browse Catalog.
//
// ProductDisqualification by Industry is configured, but in the standard
// product listing UI the employee-based ProductQualification is the reliable
// final filter. Demo account values:
//   - Koln Retail Cloud GmbH: 200 employees -> POS visible
//   - Hamburg DataWorks AG:   300 employees -> POS hidden
//   - Frankfurt FinTech:      410 employees -> POS hidden
//
// Therefore POS products qualify only for 0..250 employees.

Set<String> posProductCodes = new Set<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};

List<ProductQualification> pqs = [
    SELECT Id, Product.ProductCode, Product.Name, MinNumberOfEmployees__c, MaxNumberOfEmployees__c, EffectiveFromDate, EffectiveToDate
    FROM ProductQualification
    WHERE Product.ProductCode IN :posProductCodes
];

for (ProductQualification pq : pqs) {
    pq.MinNumberOfEmployees__c = 0;
    pq.MaxNumberOfEmployees__c = 250;
    pq.EffectiveFromDate = Date.today().addDays(-1);
    pq.EffectiveToDate = Date.newInstance(2099, 12, 31);
}
update pqs;

System.debug('Updated POS ProductQualification rows: ' + pqs.size());
for (ProductQualification pq : [
    SELECT Product.ProductCode, Product.Name, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE Product.ProductCode IN :posProductCodes
    ORDER BY Product.ProductCode
]) {
    System.debug(pq.Product.ProductCode + ' | ' + pq.Product.Name + ' | Min=' + pq.MinNumberOfEmployees__c + ' Max=' + pq.MaxNumberOfEmployees__c);
}

// Verify Workstation catalog tier counts for a non-blocked industry.

final Id WORKSTATION_CAT = '0ZGaj000000LPRgGAO';
final String TEST_INDUSTRY = 'Technology';

List<Integer> employeeCounts = new List<Integer>{25, 75, 200, 300};

List<Product2> workstationProducts = [
    SELECT Id, Name, ProductCode
    FROM Product2
    WHERE IsActive = true
    AND Id IN (
        SELECT ProductId
        FROM ProductCategoryProduct
        WHERE ProductCategoryId = :WORKSTATION_CAT
    )
    ORDER BY Name
];

Map<Id, ProductQualification> qualificationByProductId = new Map<Id, ProductQualification>();
for (ProductQualification pq : [
    SELECT ProductId, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE ProductId IN :workstationProducts
]) {
    qualificationByProductId.put(pq.ProductId, pq);
}

Map<Id, Set<String>> blockedIndustriesByProductId = new Map<Id, Set<String>>();
for (ProductDisqualification pdq : [
    SELECT ProductId, Industry__c
    FROM ProductDisqualification
    WHERE ProductId IN :workstationProducts
]) {
    if (!blockedIndustriesByProductId.containsKey(pdq.ProductId)) {
        blockedIndustriesByProductId.put(pdq.ProductId, new Set<String>());
    }
    blockedIndustriesByProductId.get(pdq.ProductId).add(pdq.Industry__c);
}

System.debug('======== Workstation tier count simulation | Industry=' + TEST_INDUSTRY + ' ========');
for (Integer employees : employeeCounts) {
    List<String> visibleProductNames = new List<String>();
    for (Product2 product : workstationProducts) {
        ProductQualification pq = qualificationByProductId.get(product.Id);
        Boolean employeesOk = pq != null
            && employees >= pq.MinNumberOfEmployees__c
            && employees <= pq.MaxNumberOfEmployees__c;
        Boolean industryOk = !blockedIndustriesByProductId.containsKey(product.Id)
            || !blockedIndustriesByProductId.get(product.Id).contains(TEST_INDUSTRY);

        if (employeesOk && industryOk) {
            visibleProductNames.add(product.Name);
        }
    }
    System.debug('Employees=' + employees + ' -> visible=' + visibleProductNames.size() + ' | ' + String.join(visibleProductNames, ', '));
}

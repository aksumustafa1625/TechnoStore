// Simulate POS product qualification by account industry.

Set<String> posProductCodes = new Set<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};
List<Account> demoAccounts = [
    SELECT Name, Industry, NumberOfEmployees
    FROM Account
    WHERE Name IN ('Köln Retail Cloud GmbH', 'Hamburg DataWorks AG', 'Frankfurt FinTech Hub GmbH')
    ORDER BY Name
];

List<Product2> products = [
    SELECT Id, Name, ProductCode
    FROM Product2
    WHERE ProductCode IN :posProductCodes
    ORDER BY Name
];

Map<Id, ProductQualification> pqByProductId = new Map<Id, ProductQualification>();
for (ProductQualification pq : [
    SELECT ProductId, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE ProductId IN :products
]) {
    pqByProductId.put(pq.ProductId, pq);
}

Map<Id, Set<String>> blockedIndustriesByProductId = new Map<Id, Set<String>>();
for (ProductDisqualification pdq : [
    SELECT ProductId, Industry__c
    FROM ProductDisqualification
    WHERE ProductId IN :products
]) {
    if (!blockedIndustriesByProductId.containsKey(pdq.ProductId)) {
        blockedIndustriesByProductId.put(pdq.ProductId, new Set<String>());
    }
    blockedIndustriesByProductId.get(pdq.ProductId).add(pdq.Industry__c);
}

System.debug('======== POS qualification simulation ========');
for (Account account : demoAccounts) {
    List<String> visible = new List<String>();
    for (Product2 product : products) {
        ProductQualification pq = pqByProductId.get(product.Id);
        Integer employees = account.NumberOfEmployees == null ? 0 : account.NumberOfEmployees;
        Boolean employeeOk = pq != null
            && employees >= pq.MinNumberOfEmployees__c
            && employees <= pq.MaxNumberOfEmployees__c;
        Boolean industryOk = !blockedIndustriesByProductId.containsKey(product.Id)
            || !blockedIndustriesByProductId.get(product.Id).contains(account.Industry);
        if (employeeOk && industryOk) visible.add(product.Name);
    }
    System.debug(account.Name + ' | Industry=' + account.Industry + ' | visible=' + visible.size() + ' | ' + String.join(visible, ', '));
}

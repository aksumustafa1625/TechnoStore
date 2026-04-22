// Check ProductQualification records in full detail for Laptop category products
List<ProductCategoryProduct> laptopProds = [
    SELECT Id, ProductId
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = '0ZGaj000000LPRdGAO'
    LIMIT 10
];
Set<Id> prodIds = new Set<Id>();
for (ProductCategoryProduct pcp : laptopProds) prodIds.add(pcp.ProductId);

List<ProductQualification> pqs = [
    SELECT Id, ProductId, IsQualified, EffectiveFromDate, EffectiveToDate,
           MinNumberOfEmployees__c, MaxNumberOfEmployees__c,
           RootProductId, ParentProductId
    FROM ProductQualification
    WHERE ProductId IN :prodIds
];

System.debug('ProductQualification records for Laptop:');
for (ProductQualification pq : pqs) {
    System.debug('Product=' + pq.ProductId +
                 ', IsQualified=' + pq.IsQualified +
                 ', From=' + pq.EffectiveFromDate +
                 ', To=' + pq.EffectiveToDate +
                 ', MinEmp=' + pq.MinNumberOfEmployees__c +
                 ', MaxEmp=' + pq.MaxNumberOfEmployees__c +
                 ', Root=' + pq.RootProductId +
                 ', Parent=' + pq.ParentProductId);
}

// Also check ProductDisqualification records for these products
List<ProductDisqualification> pdqs = [
    SELECT Id, ProductId, IsDisqualified__c, EffectiveFromDate, EffectiveToDate
    FROM ProductDisqualification
    WHERE ProductId IN :prodIds
    LIMIT 20
];
System.debug('ProductDisqualification for Laptop products: ' + pdqs.size());
for (ProductDisqualification pdq : pdqs) {
    System.debug('PDQ: Product=' + pdq.ProductId + ', IsDisqualified=' + pdq.IsDisqualified__c);
}

// Check fields available on ProductDisqualification
System.debug('Done');

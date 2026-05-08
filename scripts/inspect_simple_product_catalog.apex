// Look at a simple non-bundle product fully — what links it to the Browse Catalog?

// Find an existing base/simple product in the same demo set
List<Product2> bases = [SELECT Id, Name, ProductCode, Family, Type, BasedOnId, IsActive FROM Product2
                       WHERE Type IN ('Base','Simple','') AND IsActive = true
                       ORDER BY CreatedDate DESC LIMIT 5];
System.debug('======== Sample base products ========');
for (Product2 p : bases) System.debug(p);

if (!bases.isEmpty()) {
    Id sampleId = bases[0].Id;
    System.debug('======== Detail for ' + bases[0].Name + ' (' + sampleId + ') ========');

    System.debug('---- PricebookEntries ----');
    for (PricebookEntry pbe : [SELECT Id, Pricebook2.Name, UnitPrice, IsActive FROM PricebookEntry WHERE Product2Id = :sampleId]) {
        System.debug('  ' + pbe);
    }

    System.debug('---- ProductCategoryProduct ----');
    for (ProductCategoryProduct pcp : [SELECT Id, ProductCategoryId, ProductCategory.Name FROM ProductCategoryProduct WHERE ProductId = :sampleId]) {
        System.debug('  Category: ' + pcp.ProductCategory.Name + ' (' + pcp.ProductCategoryId + ')');
    }

    System.debug('---- ProductSellingModel via ProductSellingModelOption ----');
    for (ProductSellingModelOption psmo : [SELECT Id, ProductSellingModelId, ProductSellingModel.Name FROM ProductSellingModelOption WHERE Product2Id = :sampleId]) {
        System.debug('  ' + psmo);
    }

    System.debug('---- ProductQualification ----');
    for (ProductQualification pq : [SELECT Id, IsQualified, MinNumberOfEmployees__c, MaxNumberOfEmployees__c, EffectiveFromDate, EffectiveToDate FROM ProductQualification WHERE ProductId = :sampleId]) {
        System.debug(pq);
    }

    System.debug('---- ProductDisqualification ----');
    for (ProductDisqualification pdq : [SELECT Id, Industry__c, Reason FROM ProductDisqualification WHERE ProductId = :sampleId]) {
        System.debug('  ' + pdq.Industry__c + ' | ' + pdq.Reason);
    }
}

System.debug('======== ProductCategory list ========');
for (ProductCategory pc : [SELECT Id, Name, ParentCategoryId, CatalogId FROM ProductCategory ORDER BY Name LIMIT 30]) {
    System.debug('  ' + pc.Name + ' | Parent=' + pc.ParentCategoryId + ' | Catalog=' + pc.CatalogId);
}

System.debug('======== ProductCatalog list ========');
for (ProductCatalog pcat : [SELECT Id, Name, EffectiveStartDate, EffectiveEndDate FROM ProductCatalog]) {
    System.debug('  ' + pcat);
}

// Investigate the Workstation category + existing workstation products,
// then add Premium Workstation Pro to the Workstation category, plus
// add qualification rules to RenderStation Ultra + WorkStation X Pro
// (so they ALSO get filtered the same way for the demo).

System.debug('======== Workstation category in TechStore Electronics Catalog ========');
List<ProductCategory> wsCats = [SELECT Id, Name, ParentCategoryId, ParentCategory.Name, CatalogId, Catalog.Name
                                FROM ProductCategory WHERE Name = 'Workstation'];
for (ProductCategory pc : wsCats) {
    System.debug('  ' + pc.Name + ' | Parent=' + (pc.ParentCategory != null ? pc.ParentCategory.Name : 'null') + ' | Catalog=' + (pc.Catalog != null ? pc.Catalog.Name : 'null') + ' | Id=' + pc.Id);
}

System.debug('======== Products in Workstation category ========');
if (!wsCats.isEmpty()) {
    Id wsCatId = wsCats[0].Id;
    for (ProductCategoryProduct pcp : [SELECT ProductId, Product.Name, Product.ProductCode FROM ProductCategoryProduct WHERE ProductCategoryId = :wsCatId]) {
        System.debug('  ' + pcp.Product.Name + ' (' + pcp.Product.ProductCode + ' | ' + pcp.ProductId + ')');
    }
}

System.debug('======== Existing Workstation product qualification status ========');
for (Product2 p : [SELECT Id, Name, ProductCode FROM Product2 WHERE Name LIKE '%Workstation%' OR Name LIKE '%RenderStation%']) {
    System.debug('---- ' + p.Name + ' (' + p.ProductCode + ') ----');
    Integer pqCount = [SELECT COUNT() FROM ProductQualification WHERE ProductId = :p.Id];
    Integer pdqCount = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :p.Id];
    System.debug('  ProductQualification: ' + pqCount);
    System.debug('  ProductDisqualification: ' + pdqCount);
    for (ProductQualification pq : [SELECT MinNumberOfEmployees__c, MaxNumberOfEmployees__c, EffectiveFromDate, EffectiveToDate FROM ProductQualification WHERE ProductId = :p.Id]) {
        System.debug('    PQ: Min=' + pq.MinNumberOfEmployees__c + ' Max=' + pq.MaxNumberOfEmployees__c + ' From=' + pq.EffectiveFromDate + ' To=' + pq.EffectiveToDate);
    }
    for (ProductDisqualification pdq : [SELECT Industry__c FROM ProductDisqualification WHERE ProductId = :p.Id]) {
        System.debug('    PDQ Industry: ' + pdq.Industry__c);
    }
}

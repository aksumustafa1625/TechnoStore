List<ProductCategoryProduct> laptopProds = [SELECT Id, ProductId FROM ProductCategoryProduct WHERE ProductCategoryId = '0ZGaj000000LPRdGAO' LIMIT 10];
Set<Id> prodIds = new Set<Id>();
for (ProductCategoryProduct pcp : laptopProds) prodIds.add(pcp.ProductId);

List<ProductQualification> pqs = [
    SELECT Id, ProductId, IsQualified, EffectiveFromDate, EffectiveToDate
    FROM ProductQualification
    WHERE ProductId IN :prodIds
];
for(ProductQualification pq : pqs) {
    System.debug('PQ: ' + pq.ProductId + ' IsQualified=' + pq.IsQualified + ' From=' + pq.EffectiveFromDate + ' To=' + pq.EffectiveToDate);
}

List<ProductCategoryQualification> pcqs = [
    SELECT Id, CategoryId, IsQualified, EffectiveFromDate, EffectiveToDate, QuoteProposedDuration__c
    FROM ProductCategoryQualification
    WHERE CategoryId = '0ZGaj000000LPRdGAO'
];
for(ProductCategoryQualification pcq : pcqs) {
    System.debug('PCQ: ' + pcq.CategoryId + ' IsQualified=' + pcq.IsQualified + ' From=' + pcq.EffectiveFromDate + ' To=' + pcq.EffectiveToDate + ' Duration=' + pcq.QuoteProposedDuration__c);
}
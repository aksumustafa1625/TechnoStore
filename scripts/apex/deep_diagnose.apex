// Deep diagnostic for Browse Catalog - Quote 13 (EdgeMX, Summer Campaign)
String quoteId = '0Q0aj0000028XorCAE'; // Test Quote 13
String laptopCatId = '0ZGaj000000LPRdGAO';
String summerPbId = '01saj00000JJ3TtAAL';

// 1. Verify Quote 13 details
Quote q = [SELECT Id, Name, AccountId, Pricebook2Id FROM Quote WHERE Id = :quoteId];
System.debug('=== Quote: ' + q.Name + ' | Account: ' + q.AccountId + ' | PB: ' + q.Pricebook2Id);

// 2. Verify Account
if (q.AccountId != null) {
    Account acc = [SELECT Id, Name, Industry, NumberOfEmployees FROM Account WHERE Id = :q.AccountId];
    System.debug('=== Account: ' + acc.Name + ' | Industry: ' + acc.Industry + ' | Employees: ' + acc.NumberOfEmployees);
}

// 3. Laptop category products
List<ProductCategoryProduct> laptopPCPs = [
    SELECT Id, ProductId
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :laptopCatId
];
Set<Id> laptopProdIds = new Set<Id>();
for (ProductCategoryProduct pcp : laptopPCPs) laptopProdIds.add(pcp.ProductId);
System.debug('=== Laptop products count: ' + laptopProdIds.size());

// 4. Check PricebookEntry for Laptop products in Summer Campaign
List<PricebookEntry> summerPBEs = [
    SELECT Id, Product2Id, UnitPrice, IsActive, ProductSellingModelId
    FROM PricebookEntry
    WHERE Product2Id IN :laptopProdIds
    AND Pricebook2Id = :summerPbId
    AND IsActive = true
];
System.debug('=== Summer Campaign PBE for Laptop products: ' + summerPBEs.size());
for (PricebookEntry pbe : summerPBEs) {
    System.debug('PBE: Product=' + pbe.Product2Id + ' | Price=' + pbe.UnitPrice + ' | PSM=' + pbe.ProductSellingModelId);
}

// 5. Check ProductQualification for Laptop products (after our fix)
List<ProductQualification> pqs = [
    SELECT Id, ProductId, IsQualified, MinNumberOfEmployees__c, MaxNumberOfEmployees__c,
           EffectiveFromDate, EffectiveToDate, ParentProductId, RootProductId
    FROM ProductQualification
    WHERE ProductId IN :laptopProdIds
];
System.debug('=== ProductQualification for Laptop: ' + pqs.size());
for (ProductQualification pq : pqs) {
    System.debug('PQ: Product=' + pq.ProductId + ' | IsQual=' + pq.IsQualified +
                 ' | MinEmp=' + pq.MinNumberOfEmployees__c + ' | MaxEmp=' + pq.MaxNumberOfEmployees__c +
                 ' | From=' + pq.EffectiveFromDate + ' | To=' + pq.EffectiveToDate +
                 ' | Parent=' + pq.ParentProductId + ' | Root=' + pq.RootProductId);
}

// 6. Simulate the DT condition manually - would the DT find a match?
// For EdgeMX (1000 employees, Electronics industry), today = 2026-04-13
Date today = Date.today();
Integer empCount = 1000;
System.debug('=== Simulating DT conditions for emp=' + empCount + ', date=' + today);

List<ProductQualification> dtMatch = [
    SELECT Id, ProductId, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE ProductId IN :laptopProdIds
    AND IsQualified = true
    AND EffectiveFromDate <= :today
    AND EffectiveToDate >= :today
    AND MinNumberOfEmployees__c <= :empCount
    AND MaxNumberOfEmployees__c >= :empCount
];
System.debug('=== DT simulation matches (EmpLT style): ' + dtMatch.size());

// Also try the other direction
List<ProductQualification> dtMatch2 = [
    SELECT Id, ProductId, MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE ProductId IN :laptopProdIds
    AND IsQualified = true
    AND EffectiveFromDate <= :today
    AND EffectiveToDate >= :today
];
System.debug('=== DT matches (date only, ignoring emp): ' + dtMatch2.size());

// 7. Check ExpressionSet
List<ExpressionSet> exprSets = [SELECT Id, Name FROM ExpressionSet LIMIT 10];
System.debug('=== ExpressionSet count: ' + exprSets.size());
for (ExpressionSet es : exprSets) { System.debug('ES: ' + es.Name + ' | ' + es.Id); }

// 8. Check ProductCategoryQualification for Laptop
List<ProductCategoryQualification> pcqs = [
    SELECT Id, CategoryId, IsQualified, EffectiveFromDate, EffectiveToDate, QuoteProposedDuration__c
    FROM ProductCategoryQualification
    WHERE CategoryId = :laptopCatId
];
System.debug('=== PCQ for Laptop: ' + pcqs.size());
for (ProductCategoryQualification pcq : pcqs) {
    System.debug('PCQ: IsQual=' + pcq.IsQualified + ' | Duration=' + pcq.QuoteProposedDuration__c +
                 ' | From=' + pcq.EffectiveFromDate + ' | To=' + pcq.EffectiveToDate);
}

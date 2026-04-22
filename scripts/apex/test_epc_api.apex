// Directly test the EPC product discovery API
// Quote: Test Quote 12 (0Q0aj0000028UnmCAE)
// Catalog: TechStore Electronics (0ZSaj000000KBlhGAG)
// Category: Laptop (0ZGaj000000LPRdGAO)

String quoteId = '0Q0aj0000028UnmCAE';
String catalogId = '0ZSaj000000KBlhGAG';
String categoryId = '0ZGaj000000LPRdGAO';

System.debug('=== EPC API DIRECT TEST ===');
System.debug('Quote: ' + quoteId);
System.debug('Catalog: ' + catalogId);
System.debug('Category: ' + categoryId);

// Check the Quote record first
Quote q = [SELECT Id, Name, Pricebook2Id, AccountId FROM Quote WHERE Id = :quoteId];
System.debug('Quote PB: ' + q.Pricebook2Id);
System.debug('Quote Account: ' + q.AccountId);

// Check if account has any relevant fields
if (q.AccountId != null) {
    Account acc = [SELECT Id, Name, Industry, NumberOfEmployees FROM Account WHERE Id = :q.AccountId];
    System.debug('Account: ' + acc.Name + ', Industry: ' + acc.Industry + ', Employees: ' + acc.NumberOfEmployees);
}

// Check ProductCategoryQualification for Laptop category
List<ProductCategoryQualification> pcqs = [
    SELECT Id, CategoryId, IsQualified, EffectiveFromDate, EffectiveToDate, QuoteProposedDuration__c
    FROM ProductCategoryQualification
    WHERE CategoryId = :categoryId
];
System.debug('PCQ records for Laptop: ' + pcqs.size());
for (ProductCategoryQualification pcq : pcqs) {
    System.debug('PCQ: IsQualified=' + pcq.IsQualified + ', Duration=' + pcq.QuoteProposedDuration__c + ', From=' + pcq.EffectiveFromDate + ', To=' + pcq.EffectiveToDate);
}

// Check ProductQualification for Laptop products
List<ProductCategoryProduct> laptopProds = [
    SELECT Id, ProductId
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = :categoryId
];
Set<Id> laptopProdIds = new Set<Id>();
for (ProductCategoryProduct pcp : laptopProds) {
    laptopProdIds.add(pcp.ProductId);
}
System.debug('Products in Laptop category: ' + laptopProdIds.size());

List<ProductQualification> pqs = [
    SELECT Id, ProductId, IsQualified, EffectiveFromDate, EffectiveToDate,
           MinNumberOfEmployees__c, MaxNumberOfEmployees__c
    FROM ProductQualification
    WHERE ProductId IN :laptopProdIds
];
System.debug('ProductQualifications for Laptop products: ' + pqs.size());
for (ProductQualification pq : pqs) {
    System.debug('PQ: Product=' + pq.ProductId + ', IsQualified=' + pq.IsQualified +
                 ', MinEmp=' + pq.MinNumberOfEmployees__c + ', MaxEmp=' + pq.MaxNumberOfEmployees__c +
                 ', From=' + pq.EffectiveFromDate + ', To=' + pq.EffectiveToDate);
}

// Check PricebookEntry for Laptop products in Summer Campaign PB
List<PricebookEntry> pbes = [
    SELECT Id, Product2Id, Pricebook2Id, UnitPrice, IsActive, ProductSellingModelId
    FROM PricebookEntry
    WHERE Product2Id IN :laptopProdIds
    AND Pricebook2Id = '01saj00000JJ3TtAAL'  // Summer Campaign
    AND IsActive = true
    AND ProductSellingModelId != null
];
System.debug('Summer Campaign PSM PBE for Laptop products: ' + pbes.size());

// Check Quote.ProposedDuration field - this might be a custom field
try {
    SObject qObj = Database.query('SELECT Id, Name, ProposedDuration__c FROM Quote WHERE Id = \'' + quoteId + '\'');
    System.debug('Quote.ProposedDuration__c: ' + qObj.get('ProposedDuration__c'));
} catch (Exception e) {
    System.debug('No ProposedDuration__c on Quote: ' + e.getMessage());
}

// Check if there's a ProductDiscovery_ProposedDuration__c field
try {
    SObject qObj = Database.query('SELECT Id, Name, ProductDiscovery_ProposedDuration__c FROM Quote WHERE Id = \'' + quoteId + '\'');
    System.debug('Quote.ProductDiscovery_ProposedDuration__c: ' + qObj.get('ProductDiscovery_ProposedDuration__c'));
} catch (Exception e) {
    System.debug('No ProductDiscovery_ProposedDuration__c: ' + e.getMessage());
}

System.debug('=== DONE ===');

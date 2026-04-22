// Diagnose Browse Catalog product visibility
System.debug('=== BROWSE CATALOG DIAGNOSTICS ===');

// Check ProductQualification records
Integer pqCount = [SELECT COUNT() FROM ProductQualification WHERE IsQualified = true];
System.debug('ProductQualification (IsQualified=true): ' + pqCount);

// Check ProductCategoryQualification records
Integer pcqCount = [SELECT COUNT() FROM ProductCategoryQualification];
System.debug('ProductCategoryQualification total: ' + pcqCount);

// Check ProductCategoryProduct records
Integer pcpCount = [SELECT COUNT() FROM ProductCategoryProduct];
System.debug('ProductCategoryProduct total: ' + pcpCount);

// Check ProductSellingModelOption records
Integer psmoCount = [SELECT COUNT() FROM ProductSellingModelOption];
System.debug('Total ProductSellingModelOption: ' + psmoCount);

// Check PricebookEntry with PSM for Standard PB
Integer pbeStdCount = [SELECT COUNT() FROM PricebookEntry
    WHERE Pricebook2Id = '01saj00000JH8hNAAT'
    AND IsActive = true
    AND ProductSellingModelId != null];
System.debug('PricebookEntry (Standard PB, IsActive, HasPSM): ' + pbeStdCount);

// Check PricebookEntry with PSM for Summer Campaign
Integer pbeSummerCount = [SELECT COUNT() FROM PricebookEntry
    WHERE Pricebook2Id = '01saj00000JJ3TtAAL'
    AND IsActive = true
    AND ProductSellingModelId != null];
System.debug('PricebookEntry (Summer Campaign, IsActive, HasPSM): ' + pbeSummerCount);

// Check quote Test Quote 12 details
Quote q = [SELECT Id, Name, Pricebook2Id FROM Quote WHERE Id = '0Q0aj0000028UnmCAE' LIMIT 1];
System.debug('Quote: ' + q.Name + ', PB: ' + q.Pricebook2Id);

// Check products in Laptop category (TechStore)
List<ProductCategoryProduct> laptopCatProds = [
    SELECT Id, ProductId, ProductCategoryId
    FROM ProductCategoryProduct
    WHERE ProductCategoryId = '0ZGaj000000LPRdGAO'
    LIMIT 10
];
System.debug('Products in Laptop category: ' + laptopCatProds.size());
if (!laptopCatProds.isEmpty()) {
    Set<Id> prodIds = new Set<Id>();
    for (ProductCategoryProduct pcp : laptopCatProds) {
        prodIds.add(pcp.ProductId);
    }
    System.debug('Laptop product IDs: ' + prodIds);

    // Check qualification for these products
    List<ProductQualification> pqs = [
        SELECT Id, ProductId, IsQualified, EffectiveFromDate, EffectiveToDate
        FROM ProductQualification
        WHERE ProductId IN :prodIds
    ];
    System.debug('Qualifications for laptop products: ' + pqs.size());

    // Check PBE for these products
    List<PricebookEntry> pbes = [
        SELECT Id, Product2Id, Pricebook2Id, UnitPrice, IsActive, ProductSellingModelId
        FROM PricebookEntry
        WHERE Product2Id IN :prodIds AND IsActive = true
    ];
    System.debug('Active PBEs for laptop products: ' + pbes.size());
    for (PricebookEntry pbe : pbes) {
        System.debug('PBE: Product=' + pbe.Product2Id + ', PB=' + pbe.Pricebook2Id + ', Price=' + pbe.UnitPrice + ', PSM=' + pbe.ProductSellingModelId);
    }
}

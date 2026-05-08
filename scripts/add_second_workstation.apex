// Add a second qualification-restricted product to confirm:
//   1. Index count rises 156 -> 157 (proves new products picked up)
//   2. Two distinct demo products available (Premium Workstation Pro + Compact Studio)
//   3. Both follow identical pattern: if one filters correctly, the other will too

final Id COMPUTER_CLASSIFICATION = '11Baj000014WD4EEAW';
final Id WORKSTATION_CAT          = '0ZGaj000000LPRgGAO';
final Id COMPUTERS_LAPTOPS_CAT    = '0ZGaj000000LPQ1GAO';
final Id SELLING_MODEL_ID         = '0jPaj000000EWphEAG';

// 1) Product2 — same pattern as Premium Workstation Pro, no Type field
Product2 prod = new Product2(
    Name = 'Compact Workstation Studio',
    ProductCode = 'COMP-WS-STUDIO',
    Family = 'Hardware',
    IsActive = true,
    Description = 'Compact creative workstation, Intel Core i9-14900K, 64GB DDR5, 2TB NVMe, NVIDIA RTX 4070 Ti, ideal for design, video editing, and engineering teams in mid-size enterprises.',
    BasedOnId = COMPUTER_CLASSIFICATION,
    StockKeepingUnit = 'WS-STUDIO-001',
    QuantityUnitOfMeasure = 'Each',
    ExternalId = 'TECHSTORE-COMP-WS-STUDIO'
);
insert prod;
System.debug('Created Compact Workstation Studio: ' + prod.Id);

// 2) PricebookEntries
Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Id summerPb = [SELECT Id FROM Pricebook2 WHERE Name = 'TechStore Summer Campaign' LIMIT 1].Id;
insert new List<PricebookEntry>{
    new PricebookEntry(Pricebook2Id = stdPb,    Product2Id = prod.Id, UnitPrice = 3800, IsActive = true, UseStandardPrice = false),
    new PricebookEntry(Pricebook2Id = summerPb, Product2Id = prod.Id, UnitPrice = 3550, IsActive = true, UseStandardPrice = false)
};

// 3) Categories
List<ProductCategory> desktops = [SELECT Id FROM ProductCategory WHERE Name = 'Desktop PC' LIMIT 1];
List<ProductCategoryProduct> pcps = new List<ProductCategoryProduct>{
    new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = WORKSTATION_CAT),
    new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = COMPUTERS_LAPTOPS_CAT)
};
if (!desktops.isEmpty()) pcps.add(new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = desktops[0].Id));
insert pcps;

// 4) SellingModel
insert new ProductSellingModelOption(Product2Id = prod.Id, ProductSellingModelId = SELLING_MODEL_ID);

// 5) ProductQualification — same Min=100
insert new ProductQualification(
    ProductId = prod.Id,
    MinNumberOfEmployees__c = 100,
    MaxNumberOfEmployees__c = 999999,
    EffectiveFromDate = Date.today().addDays(-1),
    EffectiveToDate = Date.newInstance(2099, 12, 31)
);

// 6) ProductDisqualifications — same 12 industries blocked
List<String> blocked = new List<String>{'Retail','Healthcare','Education','Hospitality','Recreation','Not For Profit','Apparel','Food & Beverage','Government','Construction','Agriculture','Entertainment'};
List<ProductDisqualification> pdqs = new List<ProductDisqualification>();
for (String ind : blocked) {
    pdqs.add(new ProductDisqualification(
        ProductId = prod.Id,
        Industry__c = ind,
        Reason = 'Compact Workstation Studio is intended for technology, finance, and creative enterprises. ' + ind + ' is outside the target customer profile.',
        EffectiveFromDate = Date.today().addDays(-1),
        EffectiveToDate = Date.newInstance(2099, 12, 31)
    ));
}
insert pdqs;

System.debug('======== SUMMARY ========');
Product2 v = [SELECT Type, BasedOn.Name, QuantityUnitOfMeasure, ExternalId FROM Product2 WHERE Id = :prod.Id];
System.debug('  Type=' + v.Type + ' (should be null)');
System.debug('  BasedOn=' + v.BasedOn.Name);
System.debug('  UOM=' + v.QuantityUnitOfMeasure);
System.debug('  PBE count: ' + [SELECT COUNT() FROM PricebookEntry WHERE Product2Id = :prod.Id]);
System.debug('  Category links: ' + [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId = :prod.Id]);
System.debug('  PQ count: ' + [SELECT COUNT() FROM ProductQualification WHERE ProductId = :prod.Id]);
System.debug('  PDQ count: ' + [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :prod.Id]);

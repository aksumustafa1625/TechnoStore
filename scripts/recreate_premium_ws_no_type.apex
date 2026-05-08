// Delete Premium Workstation Pro completely (and all dependent records)
// then recreate without the Type field, matching the working WorkStation X Pro pattern.

Id oldProductId = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-WS-PREMIUM' LIMIT 1].Id;
System.debug('Deleting old Product Id: ' + oldProductId);

// 1. ProductDisqualification
delete [SELECT Id FROM ProductDisqualification WHERE ProductId = :oldProductId];
System.debug('  Deleted PDQs');

// 2. ProductQualification
delete [SELECT Id FROM ProductQualification WHERE ProductId = :oldProductId];
System.debug('  Deleted PQs');

// 3. ProductSellingModelOption
delete [SELECT Id FROM ProductSellingModelOption WHERE Product2Id = :oldProductId];
System.debug('  Deleted PSMOs');

// 4. ProductCategoryProduct
delete [SELECT Id FROM ProductCategoryProduct WHERE ProductId = :oldProductId];
System.debug('  Deleted ProductCategoryProduct');

// 5. PricebookEntry — must inactivate before delete (Standard PBE first dependency)
List<PricebookEntry> pbes = [SELECT Id, IsActive, Pricebook2.IsStandard FROM PricebookEntry WHERE Product2Id = :oldProductId];
for (PricebookEntry pbe : pbes) pbe.IsActive = false;
update pbes;
delete pbes;
System.debug('  Deleted PricebookEntries');

// 6. Product2
delete new Product2(Id = oldProductId);
System.debug('  Deleted Product2');

// === RECREATE without Type field ===
final Id COMPUTER_CLASSIFICATION = '11Baj000014WD4EEAW';
final Id WORKSTATION_CAT          = '0ZGaj000000LPRgGAO';
final Id COMPUTERS_LAPTOPS_CAT    = '0ZGaj000000LPQ1GAO';
final Id SELLING_MODEL_ID         = '0jPaj000000EWphEAG';

Product2 prod = new Product2(
    Name = 'Premium Workstation Pro',
    ProductCode = 'COMP-WS-PREMIUM',
    Family = 'Hardware',
    IsActive = true,
    Description = 'Enterprise-grade workstation, Intel Xeon W7-3475X, 128GB ECC RAM, 4TB NVMe RAID, NVIDIA RTX A5000, dual 4K displays, Windows 11 Pro for Workstations.',
    BasedOnId = COMPUTER_CLASSIFICATION,
    StockKeepingUnit = 'WS-PRO-001',
    QuantityUnitOfMeasure = 'Each',
    ExternalId = 'TECHSTORE-COMP-WS-PREMIUM'
    // NOTE: Type intentionally left null
);
insert prod;
System.debug('Created new Product2: ' + prod.Id);

// PricebookEntries
Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Id summerPb = [SELECT Id FROM Pricebook2 WHERE Name = 'TechStore Summer Campaign' LIMIT 1].Id;
insert new List<PricebookEntry>{
    new PricebookEntry(Pricebook2Id = stdPb,    Product2Id = prod.Id, UnitPrice = 4500, IsActive = true, UseStandardPrice = false),
    new PricebookEntry(Pricebook2Id = summerPb, Product2Id = prod.Id, UnitPrice = 4200, IsActive = true, UseStandardPrice = false)
};
System.debug('  Created PBEs');

// Categories
List<ProductCategory> desktops = [SELECT Id FROM ProductCategory WHERE Name = 'Desktop PC' LIMIT 1];
List<ProductCategoryProduct> pcps = new List<ProductCategoryProduct>{
    new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = WORKSTATION_CAT),
    new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = COMPUTERS_LAPTOPS_CAT)
};
if (!desktops.isEmpty()) pcps.add(new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = desktops[0].Id));
insert pcps;
System.debug('  Created ' + pcps.size() + ' ProductCategoryProducts');

// SellingModel
insert new ProductSellingModelOption(Product2Id = prod.Id, ProductSellingModelId = SELLING_MODEL_ID);
System.debug('  Created PSMO');

// Qualification + Disqualifications
insert new ProductQualification(
    ProductId = prod.Id,
    MinNumberOfEmployees__c = 100,
    MaxNumberOfEmployees__c = 999999,
    EffectiveFromDate = Date.today().addDays(-1),
    EffectiveToDate = Date.newInstance(2099, 12, 31)
);

List<String> blocked = new List<String>{'Retail','Healthcare','Education','Hospitality','Recreation','Not For Profit','Apparel','Food & Beverage','Government','Construction','Agriculture','Entertainment'};
List<ProductDisqualification> pdqs = new List<ProductDisqualification>();
for (String ind : blocked) {
    pdqs.add(new ProductDisqualification(
        ProductId = prod.Id,
        Industry__c = ind,
        Reason = 'Premium Workstation Pro is intended for technology, finance, manufacturing, and engineering enterprises. ' + ind + ' is outside the target customer profile.',
        EffectiveFromDate = Date.today().addDays(-1),
        EffectiveToDate = Date.newInstance(2099, 12, 31)
    ));
}
insert pdqs;
System.debug('  Created PQ + ' + pdqs.size() + ' PDQs');

// Verify
Product2 verify = [SELECT Id, Name, Type, BasedOn.Name, QuantityUnitOfMeasure, ExternalId FROM Product2 WHERE Id = :prod.Id];
System.debug('======== VERIFIED ========');
System.debug('  Id=' + verify.Id);
System.debug('  Name=' + verify.Name);
System.debug('  Type=' + verify.Type + '  (must be null)');
System.debug('  BasedOn=' + verify.BasedOn.Name);
System.debug('  UOM=' + verify.QuantityUnitOfMeasure);
System.debug('  ExternalId=' + verify.ExternalId);

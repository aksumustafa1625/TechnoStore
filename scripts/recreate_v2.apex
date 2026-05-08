// More robust delete + recreate

Id oldId = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-WS-PREMIUM' LIMIT 1].Id;
System.debug('Old Product Id: ' + oldId);

// Delete dependent records that already are gone or fresh from prior run might fail — use allOrNone=false
Database.delete([SELECT Id FROM ProductDisqualification WHERE ProductId = :oldId], false);
Database.delete([SELECT Id FROM ProductQualification    WHERE ProductId = :oldId], false);
Database.delete([SELECT Id FROM ProductSellingModelOption WHERE Product2Id = :oldId], false);
Database.delete([SELECT Id FROM ProductCategoryProduct  WHERE ProductId = :oldId], false);

// Inactivate PBEs first, then delete them one by one
List<PricebookEntry> pbes = [SELECT Id, IsActive, Pricebook2.IsStandard FROM PricebookEntry WHERE Product2Id = :oldId];
System.debug('PBE count: ' + pbes.size());

// Step 1: Inactivate all
for (PricebookEntry pbe : pbes) pbe.IsActive = false;
update pbes;
System.debug('All PBEs inactivated');

// Step 2: Delete non-standard PBEs first
List<PricebookEntry> customPbes = new List<PricebookEntry>();
List<PricebookEntry> stdPbes = new List<PricebookEntry>();
for (PricebookEntry pbe : pbes) {
    if (pbe.Pricebook2.IsStandard) stdPbes.add(pbe); else customPbes.add(pbe);
}
List<Database.DeleteResult> drs = Database.delete(customPbes, false);
for (Integer i=0; i<drs.size(); i++) {
    System.debug('  Custom PBE ' + customPbes[i].Id + ' delete: success=' + drs[i].isSuccess() + (drs[i].isSuccess() ? '' : ' err=' + drs[i].getErrors()[0].getMessage()));
}

// Step 3: Delete standard PBEs
drs = Database.delete(stdPbes, false);
for (Integer i=0; i<drs.size(); i++) {
    System.debug('  Std PBE ' + stdPbes[i].Id + ' delete: success=' + drs[i].isSuccess() + (drs[i].isSuccess() ? '' : ' err=' + drs[i].getErrors()[0].getMessage()));
}

// Step 4: Delete Product2
Database.DeleteResult pdr = Database.delete(new Product2(Id=oldId), false);
System.debug('Product delete: success=' + pdr.isSuccess() + (pdr.isSuccess() ? '' : ' err=' + pdr.getErrors()[0].getMessage()));

if (!pdr.isSuccess()) {
    System.debug('!!! Product delete failed — switching to RENAME approach: deactivate the old product and create a new one with a different ProductCode');
    Product2 deact = new Product2(Id = oldId, IsActive = false, ProductCode = 'COMP-WS-PREMIUM-OLD');
    update deact;
    System.debug('Old product deactivated + renamed');
}

// === RECREATE ===
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
);
insert prod;
System.debug('NEW Product Id: ' + prod.Id);

Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Id summerPb = [SELECT Id FROM Pricebook2 WHERE Name = 'TechStore Summer Campaign' LIMIT 1].Id;
insert new List<PricebookEntry>{
    new PricebookEntry(Pricebook2Id = stdPb,    Product2Id = prod.Id, UnitPrice = 4500, IsActive = true, UseStandardPrice = false),
    new PricebookEntry(Pricebook2Id = summerPb, Product2Id = prod.Id, UnitPrice = 4200, IsActive = true, UseStandardPrice = false)
};

List<ProductCategory> desktops = [SELECT Id FROM ProductCategory WHERE Name = 'Desktop PC' LIMIT 1];
List<ProductCategoryProduct> pcps = new List<ProductCategoryProduct>{
    new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = WORKSTATION_CAT),
    new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = COMPUTERS_LAPTOPS_CAT)
};
if (!desktops.isEmpty()) pcps.add(new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = desktops[0].Id));
insert pcps;

insert new ProductSellingModelOption(Product2Id = prod.Id, ProductSellingModelId = SELLING_MODEL_ID);

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
        Reason = 'Premium Workstation Pro is intended for technology and engineering enterprises. ' + ind + ' is outside the target customer profile.',
        EffectiveFromDate = Date.today().addDays(-1),
        EffectiveToDate = Date.newInstance(2099, 12, 31)
    ));
}
insert pdqs;

Product2 verify = [SELECT Type, BasedOn.Name FROM Product2 WHERE Id = :prod.Id];
System.debug('VERIFY Type=' + verify.Type + ' (should be null) | BasedOn=' + verify.BasedOn.Name);

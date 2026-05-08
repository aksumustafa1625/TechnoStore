// Set up "Premium Workstation Pro" product with strict qualification rules.
//
// Rules:
//   - Min 100 employees required (filters out small accounts)
//   - Disqualified for: Retail, Healthcare, Education, Hospitality, Recreation,
//     Not For Profit, Apparel, Food & Beverage, Government, Construction,
//     Agriculture, Entertainment (i.e. non-tech-appropriate sectors)
//
// Demo expected outcome:
//   - Hamburg DataWorks AG (Tech, 320 emp)        -> QUALIFIES, shows in catalog
//   - Köln Retail Cloud GmbH (Retail, 180 emp)    -> DISQUALIFIED (industry)
//   - University of Arizona (Education, 39000)    -> DISQUALIFIED (industry)
//   - Frankfurt FinTech Hub (Finance, 410)        -> QUALIFIES
//   - München Industrial (Manufacturing, 580)     -> QUALIFIES
//
// Idempotent: re-running upserts on ProductCode = COMP-WS-PREMIUM.

final String PRODUCT_CODE = 'COMP-WS-PREMIUM';
final String PRODUCT_NAME = 'Premium Workstation Pro';
final Id BASED_ON_CLASSIFICATION = '11Baj000015O78DEAS';        // copied from SlimAir UltraBook 14
final Id SELLING_MODEL_ID        = '0jPaj000000EWphEAG';        // copied from SlimAir UltraBook 14
final Id COMPUTERS_LAPTOPS_CAT   = '0ZGaj000000LPQ1GAO';
final Id DESKTOP_PC_CAT          = '0ZGaj000000LPQ8GAO';        // child of Computers & Laptops (resolve dynamically)

// 1) Upsert Product2
List<Product2> existing = [SELECT Id FROM Product2 WHERE ProductCode = :PRODUCT_CODE LIMIT 1];
Product2 prod;
if (existing.isEmpty()) {
    prod = new Product2(
        Name = PRODUCT_NAME,
        ProductCode = PRODUCT_CODE,
        Family = 'Hardware',
        Type = 'Base',
        IsActive = true,
        Description = 'Enterprise-grade workstation with Xeon W processors, 64GB ECC RAM, 2TB NVMe storage, and dual 4K displays. Available for technology and engineering enterprises with 100+ employees.',
        BasedOnId = BASED_ON_CLASSIFICATION,
        StockKeepingUnit = 'WS-PRO-001'
    );
    insert prod;
    System.debug('Created Product2: ' + prod.Id);
} else {
    prod = existing[0];
    System.debug('Reusing existing Product2: ' + prod.Id);
}

// 2) Standard PricebookEntry (required before custom PBEs)
Id standardPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
List<PricebookEntry> existingStdPbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id AND Pricebook2Id = :standardPbId];
if (existingStdPbe.isEmpty()) {
    PricebookEntry stdPbe = new PricebookEntry(
        Pricebook2Id = standardPbId,
        Product2Id = prod.Id,
        UnitPrice = 4500.00,
        IsActive = true,
        UseStandardPrice = false
    );
    insert stdPbe;
    System.debug('Created Standard PBE: ' + stdPbe.Id);
} else {
    System.debug('Standard PBE already exists');
}

// 3) Add to TechStore Summer Campaign as well (existing demo PB)
Id summerPbId = [SELECT Id FROM Pricebook2 WHERE Name = 'TechStore Summer Campaign' LIMIT 1].Id;
List<PricebookEntry> existingSummerPbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id AND Pricebook2Id = :summerPbId];
if (existingSummerPbe.isEmpty()) {
    insert new PricebookEntry(
        Pricebook2Id = summerPbId,
        Product2Id = prod.Id,
        UnitPrice = 4200.00,
        IsActive = true,
        UseStandardPrice = false
    );
    System.debug('Created Summer Campaign PBE');
}

// 4) Find Desktop PC category (child of Computers & Laptops)
List<ProductCategory> desktops = [SELECT Id FROM ProductCategory WHERE Name = 'Desktop PC' AND ParentCategoryId = :COMPUTERS_LAPTOPS_CAT LIMIT 1];
if (desktops.isEmpty()) {
    System.debug('WARN: Desktop PC category not found, will only link to Computers & Laptops parent');
}
Id desktopCatId = desktops.isEmpty() ? null : desktops[0].Id;

// 5) ProductCategoryProduct
Set<Id> existingCats = new Set<Id>();
for (ProductCategoryProduct pcp : [SELECT ProductCategoryId FROM ProductCategoryProduct WHERE ProductId = :prod.Id]) {
    existingCats.add(pcp.ProductCategoryId);
}
List<ProductCategoryProduct> newPcps = new List<ProductCategoryProduct>();
if (!existingCats.contains(COMPUTERS_LAPTOPS_CAT)) newPcps.add(new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = COMPUTERS_LAPTOPS_CAT));
if (desktopCatId != null && !existingCats.contains(desktopCatId)) newPcps.add(new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = desktopCatId));
if (!newPcps.isEmpty()) {
    insert newPcps;
    System.debug('Created ' + newPcps.size() + ' ProductCategoryProduct link(s)');
}

// 6) ProductSellingModelOption
List<ProductSellingModelOption> existingPsmo = [SELECT Id FROM ProductSellingModelOption WHERE Product2Id = :prod.Id AND ProductSellingModelId = :SELLING_MODEL_ID];
if (existingPsmo.isEmpty()) {
    insert new ProductSellingModelOption(Product2Id = prod.Id, ProductSellingModelId = SELLING_MODEL_ID);
    System.debug('Created ProductSellingModelOption');
}

// 7) ProductQualification (Min=100 employees)
List<ProductQualification> existingPq = [SELECT Id FROM ProductQualification WHERE ProductId = :prod.Id];
if (existingPq.isEmpty()) {
    insert new ProductQualification(
        ProductId = prod.Id,
        MinNumberOfEmployees__c = 100,
        MaxNumberOfEmployees__c = 999999,
        EffectiveFromDate = Date.today().addDays(-1),
        EffectiveToDate = Date.newInstance(2099, 12, 31)
    );
    System.debug('Created ProductQualification: Min=100');
}

// 8) ProductDisqualifications (industry-based)
List<String> blockedIndustries = new List<String>{
    'Retail', 'Healthcare', 'Education', 'Hospitality', 'Recreation',
    'Not For Profit', 'Apparel', 'Food & Beverage', 'Government',
    'Construction', 'Agriculture', 'Entertainment'
};
Set<String> existingPdqIndustries = new Set<String>();
for (ProductDisqualification pdq : [SELECT Industry__c FROM ProductDisqualification WHERE ProductId = :prod.Id]) {
    existingPdqIndustries.add(pdq.Industry__c);
}
List<ProductDisqualification> newPdqs = new List<ProductDisqualification>();
for (String industry : blockedIndustries) {
    if (!existingPdqIndustries.contains(industry)) {
        newPdqs.add(new ProductDisqualification(
            ProductId = prod.Id,
            Industry__c = industry,
            Reason = 'Premium Workstation Pro is intended for technology, finance, manufacturing, and engineering enterprises. ' + industry + ' is outside the target customer profile.',
            EffectiveFromDate = Date.today().addDays(-1),
            EffectiveToDate = Date.newInstance(2099, 12, 31)
        ));
    }
}
if (!newPdqs.isEmpty()) {
    insert newPdqs;
    System.debug('Created ' + newPdqs.size() + ' ProductDisqualification record(s)');
}

System.debug('======== SUMMARY ========');
System.debug('Product2 Id: ' + prod.Id);
Integer pbeCount = [SELECT COUNT() FROM PricebookEntry WHERE Product2Id = :prod.Id];
Integer pcpCount = [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId = :prod.Id];
Integer pqCount  = [SELECT COUNT() FROM ProductQualification WHERE ProductId = :prod.Id];
Integer pdqCount = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :prod.Id];
Integer psmoCount= [SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id = :prod.Id];
System.debug('PricebookEntries: ' + pbeCount);
System.debug('ProductCategoryProduct: ' + pcpCount);
System.debug('ProductSellingModelOption: ' + psmoCount);
System.debug('ProductQualification: ' + pqCount);
System.debug('ProductDisqualification: ' + pdqCount);

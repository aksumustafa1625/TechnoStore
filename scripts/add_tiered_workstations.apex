// Add 3 tiered workstation products to demonstrate progressive disclosure
// based on Account.NumberOfEmployees:
// Target total visible Workstation products by Account.NumberOfEmployees:
//   - 25 employees  -> 1 product
//   - 75 employees  -> 2 products
//   - 200 employees -> 3 products
//   - 300+ employees -> 5+ products
//
// Tier placement:
//   - Existing WorkStation X Pro    (Min=25)
//   - Office Workstation Plus       (Min=75,  open to all industries)   $1,799
//   - Business Workstation          (Min=200, open to all industries)   $2,499
//   - Hyperscale Compute Node       (Min=300, 12 industries blocked)    $8,999
//   - Existing premium products     (Min=300, if present)
//
// After running:
//   1) Setup -> Product Discovery Settings -> Rebuild Index
//   2) Setup -> Salesforce Pricing Setup -> Sync (next to Sync Pricing Data)

final Id COMPUTER_CLASSIFICATION = '11Baj000014WD4EEAW';   // matches existing workstations
final Id WORKSTATION_CAT          = '0ZGaj000000LPRgGAO';
final Id COMPUTERS_LAPTOPS_CAT    = '0ZGaj000000LPQ1GAO';
final Id SELLING_MODEL_ID         = '0jPaj000000EWphEAG';

Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Id summerPb = [SELECT Id FROM Pricebook2 WHERE Name = 'TechStore Summer Campaign' LIMIT 1].Id;
List<ProductCategory> desktops = [SELECT Id FROM ProductCategory WHERE Name = 'Desktop PC' LIMIT 1];
Id desktopId = desktops.isEmpty() ? null : desktops[0].Id;

List<String> blockedIndustries = new List<String>{'Retail','Healthcare','Education','Hospitality','Recreation','Not For Profit','Apparel','Food & Beverage','Government','Construction','Agriculture','Entertainment'};

// ============== EXISTING PRODUCT TIERS ==============
// These products already exist in the demo org. Keep them aligned so the total
// visible Workstation count rises at the requested employee thresholds.
Map<String, Integer> existingProductMinsByCode = new Map<String, Integer>{
    'COMP-WS-001' => 25,
    'COMP-WS-002' => 300,
    'COMP-WS-PREMIUM' => 300,
    'COMP-WS-STUDIO' => 300
};
Set<String> existingProductCodes = existingProductMinsByCode.keySet();

for (Product2 existingProd : [
    SELECT Id, Name, ProductCode, IsActive
    FROM Product2
    WHERE ProductCode IN :existingProductCodes
]) {
    existingProd.IsActive = true;
    update existingProd;

    Integer targetMin = existingProductMinsByCode.get(existingProd.ProductCode);
    List<ProductQualification> existingPqs = [
        SELECT Id, MinNumberOfEmployees__c, MaxNumberOfEmployees__c, EffectiveFromDate, EffectiveToDate
        FROM ProductQualification
        WHERE ProductId = :existingProd.Id
    ];
    if (existingPqs.isEmpty()) {
        insert new ProductQualification(
            ProductId = existingProd.Id,
            MinNumberOfEmployees__c = targetMin,
            MaxNumberOfEmployees__c = 999999,
            EffectiveFromDate = Date.today().addDays(-1),
            EffectiveToDate = Date.newInstance(2099, 12, 31)
        );
    } else {
        for (ProductQualification pq : existingPqs) {
            pq.MinNumberOfEmployees__c = targetMin;
            pq.MaxNumberOfEmployees__c = 999999;
            pq.EffectiveFromDate = Date.today().addDays(-1);
            pq.EffectiveToDate = Date.newInstance(2099, 12, 31);
        }
        update existingPqs;
    }
    System.debug('Existing tier aligned: ' + existingProd.ProductCode + ' | ' + existingProd.Name + ' | Min=' + targetMin);
}

// ============== TIER DEFINITIONS ==============
// {productCode, name, description, sku, minEmp, blockIndustries, stdPrice, summerPrice}
List<Map<String, Object>> tiers = new List<Map<String, Object>>{
    new Map<String, Object>{
        'code' => 'COMP-WS-OFFICE',
        'name' => 'Office Workstation Plus',
        'desc' => 'Reliable office workstation, Intel Core i5-14500, 32GB DDR5, 1TB NVMe, integrated graphics. Ideal for growing teams of 75+ employees.',
        'sku'  => 'WS-OFFICE-001',
        'minEmp' => 75,
        'industryBlock' => false,
        'stdPrice' => 1799,
        'summerPrice' => 1599
    },
    new Map<String, Object>{
        'code' => 'COMP-WS-BUSINESS',
        'name' => 'Business Workstation',
        'desc' => 'Mid-market business workstation, Intel Core i7-14700K, 64GB DDR5, 1TB NVMe, NVIDIA T1000. Suited for growing teams of 200+ employees.',
        'sku'  => 'WS-BUSINESS-001',
        'minEmp' => 200,
        'industryBlock' => false,
        'stdPrice' => 2499,
        'summerPrice' => 2199
    },
    new Map<String, Object>{
        'code' => 'COMP-WS-HYPERSCALE',
        'name' => 'Hyperscale Compute Node',
        'desc' => 'Hyperscale compute node for AI/ML training and large-scale simulation, Dual Xeon Platinum 8480+, 512GB ECC DDR5, 8TB NVMe RAID, 4x NVIDIA H100 80GB. For enterprises with 300+ employees in tech-aligned industries.',
        'sku'  => 'WS-HYPER-001',
        'minEmp' => 300,
        'industryBlock' => true,
        'stdPrice' => 8999,
        'summerPrice' => 8499
    }
};

// ============== CREATE EACH ==============
for (Map<String, Object> t : tiers) {
    String code = (String) t.get('code');
    List<Product2> existing = [SELECT Id, Name, Description, IsActive FROM Product2 WHERE ProductCode = :code LIMIT 1];
    Product2 prod;
    if (existing.isEmpty()) {
        prod = new Product2(
            Name = (String) t.get('name'),
            ProductCode = code,
            Family = 'Hardware',
            IsActive = true,
            Description = (String) t.get('desc'),
            BasedOnId = COMPUTER_CLASSIFICATION,
            StockKeepingUnit = (String) t.get('sku'),
            QuantityUnitOfMeasure = 'Each',
            ExternalId = 'TECHSTORE-' + code
        );
        insert prod;
        System.debug('Created ' + (String) t.get('name') + ': ' + prod.Id);
    } else {
        prod = existing[0];
        prod.Name = (String) t.get('name');
        prod.Description = (String) t.get('desc');
        prod.IsActive = true;
        update prod;
        System.debug('Updated existing ' + code + ': ' + prod.Id);
    }

    // Pricebook entries
    Set<Id> targetPbIds = new Set<Id>{stdPb, summerPb};
    Map<Id, PricebookEntry> pbesByPb = new Map<Id, PricebookEntry>();
    for (PricebookEntry pbe : [
        SELECT Id, Pricebook2Id, UnitPrice, IsActive
        FROM PricebookEntry
        WHERE Product2Id = :prod.Id AND Pricebook2Id IN :targetPbIds
    ]) {
        pbesByPb.put(pbe.Pricebook2Id, pbe);
    }

    Map<Id, Decimal> targetPrices = new Map<Id, Decimal>{
        stdPb => (Decimal) t.get('stdPrice'),
        summerPb => (Decimal) t.get('summerPrice')
    };
    List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
    List<PricebookEntry> pbesToUpdate = new List<PricebookEntry>();
    for (Id pbId : targetPrices.keySet()) {
        if (pbesByPb.containsKey(pbId)) {
            PricebookEntry pbe = pbesByPb.get(pbId);
            pbe.UnitPrice = targetPrices.get(pbId);
            pbe.IsActive = true;
            pbesToUpdate.add(pbe);
        } else {
            pbesToInsert.add(new PricebookEntry(
                Pricebook2Id = pbId,
                Product2Id = prod.Id,
                UnitPrice = targetPrices.get(pbId),
                IsActive = true,
                UseStandardPrice = false
            ));
        }
    }
    if (!pbesToInsert.isEmpty()) insert pbesToInsert;
    if (!pbesToUpdate.isEmpty()) update pbesToUpdate;

    // Categories: Workstation + Computers & Laptops + Desktop PC
    Set<Id> existingCatIds = new Set<Id>();
    for (ProductCategoryProduct pcp : [SELECT ProductCategoryId FROM ProductCategoryProduct WHERE ProductId = :prod.Id]) {
        existingCatIds.add(pcp.ProductCategoryId);
    }
    List<ProductCategoryProduct> pcps = new List<ProductCategoryProduct>();
    if (!existingCatIds.contains(WORKSTATION_CAT)) pcps.add(new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = WORKSTATION_CAT));
    if (!existingCatIds.contains(COMPUTERS_LAPTOPS_CAT)) pcps.add(new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = COMPUTERS_LAPTOPS_CAT));
    if (desktopId != null && !existingCatIds.contains(desktopId)) pcps.add(new ProductCategoryProduct(ProductId = prod.Id, ProductCategoryId = desktopId));
    if (!pcps.isEmpty()) insert pcps;

    // Selling model
    if ([SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id = :prod.Id AND ProductSellingModelId = :SELLING_MODEL_ID] == 0) {
        insert new ProductSellingModelOption(Product2Id = prod.Id, ProductSellingModelId = SELLING_MODEL_ID);
    }

    // Qualification
    List<ProductQualification> existingPqs = [
        SELECT Id, MinNumberOfEmployees__c, MaxNumberOfEmployees__c, EffectiveFromDate, EffectiveToDate
        FROM ProductQualification
        WHERE ProductId = :prod.Id
    ];
    if (existingPqs.isEmpty()) {
        insert new ProductQualification(
            ProductId = prod.Id,
            MinNumberOfEmployees__c = (Integer) t.get('minEmp'),
            MaxNumberOfEmployees__c = 999999,
            EffectiveFromDate = Date.today().addDays(-1),
            EffectiveToDate = Date.newInstance(2099, 12, 31)
        );
    } else {
        for (ProductQualification pq : existingPqs) {
            pq.MinNumberOfEmployees__c = (Integer) t.get('minEmp');
            pq.MaxNumberOfEmployees__c = 999999;
            pq.EffectiveFromDate = Date.today().addDays(-1);
            pq.EffectiveToDate = Date.newInstance(2099, 12, 31);
        }
        update existingPqs;
    }

    // Industry blocks (only for hyperscale tier)
    if ((Boolean) t.get('industryBlock')) {
        Set<String> existingBlockedIndustries = new Set<String>();
        List<ProductDisqualification> duplicatePdqs = new List<ProductDisqualification>();
        for (ProductDisqualification existingPdq : [
            SELECT Id, Industry__c
            FROM ProductDisqualification
            WHERE ProductId = :prod.Id
        ]) {
            if (existingBlockedIndustries.contains(existingPdq.Industry__c)) {
                duplicatePdqs.add(existingPdq);
            } else {
                existingBlockedIndustries.add(existingPdq.Industry__c);
            }
        }
        if (!duplicatePdqs.isEmpty()) delete duplicatePdqs;

        List<ProductDisqualification> pdqs = new List<ProductDisqualification>();
        for (String ind : blockedIndustries) {
            if (!existingBlockedIndustries.contains(ind)) {
                pdqs.add(new ProductDisqualification(
                    ProductId = prod.Id,
                    Industry__c = ind,
                    Reason = (String) t.get('name') + ' is intended for technology, finance, and engineering enterprises. ' + ind + ' is outside the target customer profile.',
                    EffectiveFromDate = Date.today().addDays(-1),
                    EffectiveToDate = Date.newInstance(2099, 12, 31)
                ));
            }
        }
        if (!pdqs.isEmpty()) insert pdqs;
        System.debug('  industry blocks aligned: inserted=' + pdqs.size() + ', duplicatesRemoved=' + duplicatePdqs.size());
    } else {
        System.debug('  no industry blocks (open to all industries above ' + (Integer) t.get('minEmp') + ' emp)');
    }
}

System.debug('======== SUMMARY: All workstations ========');
for (Product2 p : [SELECT Id, Name, ProductCode FROM Product2 WHERE Id IN (SELECT ProductId FROM ProductCategoryProduct WHERE ProductCategoryId = :WORKSTATION_CAT) ORDER BY Name]) {
    Decimal minE = 0;
    Integer pdqCount = 0;
    Decimal price = 0;
    for (ProductQualification pq : [SELECT MinNumberOfEmployees__c FROM ProductQualification WHERE ProductId = :p.Id LIMIT 1]) minE = pq.MinNumberOfEmployees__c;
    pdqCount = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :p.Id];
    for (PricebookEntry pbe : [SELECT UnitPrice FROM PricebookEntry WHERE Product2Id = :p.Id AND Pricebook2.IsStandard = true LIMIT 1]) price = pbe.UnitPrice;
    System.debug('  ' + p.Name.rightPad(30) + ' | Min=' + String.valueOf(minE).rightPad(6) + ' | PDQ=' + String.valueOf(pdqCount).rightPad(3) + ' | $' + price);
}

// Retail industry qualification demo for POS products.
//
// Demo behavior:
//   - Retail accounts can see POS products in POS Solutions.
//   - Technology / Finance / Manufacturing / other non-retail accounts are
//     disqualified from these POS products.

final Id POS_SOLUTIONS_CAT = '0ZGaj000000LA62GAG';
final Id ONE_TIME_MODEL_ID = '0jPaj000000EWphEAG';

Set<String> posProductCodes = new Set<String>{'REG01', 'POS01', 'ENPOS101', 'SCN01'};
Map<String, Decimal> pricesByCode = new Map<String, Decimal>{
    'REG01' => 10000,
    'POS01' => 5000,
    'ENPOS101' => 30000,
    'SCN01' => 10000
};

List<String> nonRetailIndustries = new List<String>{
    'Technology',
    'Finance',
    'Manufacturing',
    'Healthcare',
    'Education',
    'Hospitality',
    'Recreation',
    'Not For Profit',
    'Apparel',
    'Food & Beverage',
    'Government',
    'Construction',
    'Agriculture',
    'Entertainment',
    'Other'
};

Map<String, Product2> productsByCode = new Map<String, Product2>();
for (Product2 product : [
    SELECT Id, Name, ProductCode, IsActive
    FROM Product2
    WHERE ProductCode IN :posProductCodes
]) {
    product.IsActive = true;
    productsByCode.put(product.ProductCode, product);
}
if (!productsByCode.isEmpty()) update productsByCode.values();

// Category links
Set<Id> productIds = new Set<Id>();
for (Product2 product : productsByCode.values()) productIds.add(product.Id);

Set<Id> alreadyLinkedToPos = new Set<Id>();
for (ProductCategoryProduct pcp : [
    SELECT ProductId
    FROM ProductCategoryProduct
    WHERE ProductId IN :productIds
    AND ProductCategoryId = :POS_SOLUTIONS_CAT
]) {
    alreadyLinkedToPos.add(pcp.ProductId);
}

List<ProductCategoryProduct> pcpsToInsert = new List<ProductCategoryProduct>();
for (Product2 product : productsByCode.values()) {
    if (!alreadyLinkedToPos.contains(product.Id)) {
        pcpsToInsert.add(new ProductCategoryProduct(
            ProductId = product.Id,
            ProductCategoryId = POS_SOLUTIONS_CAT
        ));
    }
}
if (!pcpsToInsert.isEmpty()) insert pcpsToInsert;

// Selling model and pricebook entries
Set<Id> activePricebookIds = new Set<Id>();
Map<Id, Pricebook2> activePricebooksById = new Map<Id, Pricebook2>();
for (Pricebook2 pricebook : [SELECT Id, Name FROM Pricebook2 WHERE IsActive = true]) {
    activePricebookIds.add(pricebook.Id);
    activePricebooksById.put(pricebook.Id, pricebook);
}

Set<Id> productsWithOneTimeModel = new Set<Id>();
for (ProductSellingModelOption psmo : [
    SELECT Product2Id
    FROM ProductSellingModelOption
    WHERE Product2Id IN :productIds
    AND ProductSellingModelId = :ONE_TIME_MODEL_ID
]) {
    productsWithOneTimeModel.add(psmo.Product2Id);
}

List<ProductSellingModelOption> psmosToInsert = new List<ProductSellingModelOption>();
for (Product2 product : productsByCode.values()) {
    if (!productsWithOneTimeModel.contains(product.Id)) {
        psmosToInsert.add(new ProductSellingModelOption(
            Product2Id = product.Id,
            ProductSellingModelId = ONE_TIME_MODEL_ID
        ));
    }
}
if (!psmosToInsert.isEmpty()) insert psmosToInsert;

Map<String, PricebookEntry> existingPbesByKey = new Map<String, PricebookEntry>();
for (PricebookEntry pbe : [
    SELECT Id, Product2Id, Product2.ProductCode, Pricebook2Id, ProductSellingModelId, UnitPrice, IsActive
    FROM PricebookEntry
    WHERE Product2Id IN :productIds
    AND Pricebook2Id IN :activePricebookIds
]) {
    existingPbesByKey.put(pbe.Product2.ProductCode + '|' + pbe.Pricebook2Id + '|' + String.valueOf(pbe.ProductSellingModelId), pbe);
}

List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
List<PricebookEntry> pbesToUpdate = new List<PricebookEntry>();
for (String code : productsByCode.keySet()) {
    Product2 product = productsByCode.get(code);
    Decimal basePrice = pricesByCode.get(code);

    for (Id pricebookId : activePricebookIds) {
        Decimal price = basePrice;
        String pricebookName = activePricebooksById.get(pricebookId).Name;
        if (pricebookName == 'TechStore Employee Pricing') price = (basePrice * 0.70).setScale(2);
        if (pricebookName == 'TechStore Partner Reseller') price = (basePrice * 0.80).setScale(2);
        if (pricebookName == 'TechStore Volume Wholesale') price = (basePrice * 0.85).setScale(2);
        if (pricebookName == 'TechStore Summer Campaign') price = (basePrice * 0.90).setScale(2);
        if (pricebookName == 'Nonprofit') price = (basePrice * 0.75).setScale(2);

        String oneTimeKey = code + '|' + pricebookId + '|' + ONE_TIME_MODEL_ID;
        if (existingPbesByKey.containsKey(oneTimeKey)) {
            PricebookEntry pbe = existingPbesByKey.get(oneTimeKey);
            pbe.UnitPrice = price;
            pbe.IsActive = true;
            pbesToUpdate.add(pbe);
        } else {
            pbesToInsert.add(new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,
                ProductSellingModelId = ONE_TIME_MODEL_ID,
                UnitPrice = price,
                IsActive = true,
                UseStandardPrice = false
            ));
        }
    }
}
if (!pbesToInsert.isEmpty()) insert pbesToInsert;
if (!pbesToUpdate.isEmpty()) update pbesToUpdate;

// ProductQualification: available by employee count, industry handled by disqualification.
Map<Id, ProductQualification> pqByProductId = new Map<Id, ProductQualification>();
for (ProductQualification pq : [
    SELECT Id, ProductId, MinNumberOfEmployees__c, MaxNumberOfEmployees__c, EffectiveFromDate, EffectiveToDate
    FROM ProductQualification
    WHERE ProductId IN :productIds
]) {
    pqByProductId.put(pq.ProductId, pq);
}

List<ProductQualification> pqsToInsert = new List<ProductQualification>();
List<ProductQualification> pqsToUpdate = new List<ProductQualification>();
for (Product2 product : productsByCode.values()) {
    if (pqByProductId.containsKey(product.Id)) {
        ProductQualification pq = pqByProductId.get(product.Id);
        pq.MinNumberOfEmployees__c = 0;
        pq.MaxNumberOfEmployees__c = 999999;
        pq.EffectiveFromDate = Date.today().addDays(-1);
        pq.EffectiveToDate = Date.newInstance(2099, 12, 31);
        pqsToUpdate.add(pq);
    } else {
        pqsToInsert.add(new ProductQualification(
            ProductId = product.Id,
            MinNumberOfEmployees__c = 0,
            MaxNumberOfEmployees__c = 999999,
            EffectiveFromDate = Date.today().addDays(-1),
            EffectiveToDate = Date.newInstance(2099, 12, 31)
        ));
    }
}
if (!pqsToInsert.isEmpty()) insert pqsToInsert;
if (!pqsToUpdate.isEmpty()) update pqsToUpdate;

// ProductDisqualification: block non-retail industries.
Map<Id, Set<String>> blockedIndustriesByProductId = new Map<Id, Set<String>>();
List<ProductDisqualification> duplicatePdqs = new List<ProductDisqualification>();
for (ProductDisqualification pdq : [
    SELECT Id, ProductId, Industry__c
    FROM ProductDisqualification
    WHERE ProductId IN :productIds
]) {
    if (!blockedIndustriesByProductId.containsKey(pdq.ProductId)) {
        blockedIndustriesByProductId.put(pdq.ProductId, new Set<String>());
    }
    if (blockedIndustriesByProductId.get(pdq.ProductId).contains(pdq.Industry__c)) {
        duplicatePdqs.add(pdq);
    } else {
        blockedIndustriesByProductId.get(pdq.ProductId).add(pdq.Industry__c);
    }
}
if (!duplicatePdqs.isEmpty()) delete duplicatePdqs;

List<ProductDisqualification> pdqsToInsert = new List<ProductDisqualification>();
for (Product2 product : productsByCode.values()) {
    if (!blockedIndustriesByProductId.containsKey(product.Id)) {
        blockedIndustriesByProductId.put(product.Id, new Set<String>());
    }
    for (String industry : nonRetailIndustries) {
        if (!blockedIndustriesByProductId.get(product.Id).contains(industry)) {
            pdqsToInsert.add(new ProductDisqualification(
                ProductId = product.Id,
                Industry__c = industry,
                Reason = product.Name + ' is intended for retail store operations. ' + industry + ' is outside the POS demo target profile.',
                EffectiveFromDate = Date.today().addDays(-1),
                EffectiveToDate = Date.newInstance(2099, 12, 31)
            ));
        }
    }
}
if (!pdqsToInsert.isEmpty()) insert pdqsToInsert;

System.debug('POS category links inserted: ' + pcpsToInsert.size());
System.debug('One Time selling model options inserted: ' + psmosToInsert.size());
System.debug('PBEs inserted=' + pbesToInsert.size() + ', updated=' + pbesToUpdate.size());
System.debug('ProductQualifications inserted=' + pqsToInsert.size() + ', updated=' + pqsToUpdate.size());
System.debug('ProductDisqualifications inserted=' + pdqsToInsert.size() + ', duplicatesRemoved=' + duplicatePdqs.size());

System.debug('======== Retail POS products ========');
for (Product2 product : [
    SELECT Id, Name, ProductCode
    FROM Product2
    WHERE ProductCode IN :posProductCodes
    ORDER BY Name
]) {
    Integer pdqCount = [SELECT COUNT() FROM ProductDisqualification WHERE ProductId = :product.Id];
    System.debug(product.ProductCode + ' | ' + product.Name + ' | Non-retail blocks=' + pdqCount);
}

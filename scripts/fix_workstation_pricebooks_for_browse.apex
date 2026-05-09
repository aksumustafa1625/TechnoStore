// Align workstation products with the pricebook shape used by Browse Catalog.
//
// The RLM catalog runtime expects active PricebookEntry rows for the quote
// pricebook, and in this org Standard/Summer also use PSM-specific PBE rows.
// This script backfills the new workstation products across all active demo
// pricebooks and creates PSM-specific rows for Standard + Summer.

final Id SELLING_MODEL_ID = '0jPaj000000EWphEAG';

Set<String> productCodes = new Set<String>{
    'COMP-WS-OFFICE',
    'COMP-WS-BUSINESS',
    'COMP-WS-HYPERSCALE',
    'COMP-WS-PREMIUM',
    'COMP-WS-STUDIO'
};

Map<String, Decimal> standardPricesByCode = new Map<String, Decimal>{
    'COMP-WS-OFFICE' => 1799,
    'COMP-WS-BUSINESS' => 2499,
    'COMP-WS-HYPERSCALE' => 8999,
    'COMP-WS-PREMIUM' => 4500,
    'COMP-WS-STUDIO' => 3800
};

Map<String, Decimal> summerPricesByCode = new Map<String, Decimal>{
    'COMP-WS-OFFICE' => 1599,
    'COMP-WS-BUSINESS' => 2199,
    'COMP-WS-HYPERSCALE' => 8499,
    'COMP-WS-PREMIUM' => 4200,
    'COMP-WS-STUDIO' => 3550
};

Map<String, Product2> productsByCode = new Map<String, Product2>();
for (Product2 product : [
    SELECT Id, Name, ProductCode, IsActive
    FROM Product2
    WHERE ProductCode IN :productCodes
]) {
    product.IsActive = true;
    productsByCode.put(product.ProductCode, product);
}
update productsByCode.values();

List<Pricebook2> pricebooks = [
    SELECT Id, Name, IsStandard, IsActive
    FROM Pricebook2
    WHERE IsActive = true
];

Map<String, PricebookEntry> existingPbesByKey = new Map<String, PricebookEntry>();
for (PricebookEntry pbe : [
    SELECT Id, Product2Id, Product2.ProductCode, Pricebook2Id, ProductSellingModelId, UnitPrice, IsActive
    FROM PricebookEntry
    WHERE Product2.ProductCode IN :productCodes
]) {
    String key = pbe.Product2.ProductCode + '|' + pbe.Pricebook2Id + '|' + String.valueOf(pbe.ProductSellingModelId);
    existingPbesByKey.put(key, pbe);
}

List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
List<PricebookEntry> pbesToUpdate = new List<PricebookEntry>();

for (String code : productsByCode.keySet()) {
    Product2 product = productsByCode.get(code);
    Decimal standardPrice = standardPricesByCode.get(code);

    for (Pricebook2 pricebook : pricebooks) {
        Decimal price = standardPrice;
        if (pricebook.Name == 'TechStore Summer Campaign') {
            price = summerPricesByCode.get(code);
        } else if (pricebook.Name == 'TechStore Employee Pricing') {
            price = (standardPrice * 0.70).setScale(2);
        } else if (pricebook.Name == 'TechStore Partner Reseller') {
            price = (standardPrice * 0.80).setScale(2);
        } else if (pricebook.Name == 'TechStore Volume Wholesale') {
            price = (standardPrice * 0.85).setScale(2);
        } else if (pricebook.Name == 'Nonprofit') {
            price = (standardPrice * 0.75).setScale(2);
        }

        String nullPsmKey = code + '|' + pricebook.Id + '|null';
        if (existingPbesByKey.containsKey(nullPsmKey)) {
            PricebookEntry pbe = existingPbesByKey.get(nullPsmKey);
            pbe.UnitPrice = price;
            pbe.IsActive = true;
            pbesToUpdate.add(pbe);
        } else {
            pbesToInsert.add(new PricebookEntry(
                Pricebook2Id = pricebook.Id,
                Product2Id = product.Id,
                UnitPrice = price,
                IsActive = true,
                UseStandardPrice = false
            ));
        }

        if (pricebook.IsStandard || pricebook.Name == 'TechStore Summer Campaign') {
            String psmKey = code + '|' + pricebook.Id + '|' + SELLING_MODEL_ID;
            if (existingPbesByKey.containsKey(psmKey)) {
                PricebookEntry pbe = existingPbesByKey.get(psmKey);
                pbe.UnitPrice = price;
                pbe.IsActive = true;
                pbesToUpdate.add(pbe);
            } else {
                pbesToInsert.add(new PricebookEntry(
                    Pricebook2Id = pricebook.Id,
                    Product2Id = product.Id,
                    ProductSellingModelId = SELLING_MODEL_ID,
                    UnitPrice = price,
                    IsActive = true,
                    UseStandardPrice = false
                ));
            }
        }
    }

    if ([SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id = :product.Id AND ProductSellingModelId = :SELLING_MODEL_ID] == 0) {
        insert new ProductSellingModelOption(Product2Id = product.Id, ProductSellingModelId = SELLING_MODEL_ID);
    }
}

if (!pbesToInsert.isEmpty()) insert pbesToInsert;
if (!pbesToUpdate.isEmpty()) update pbesToUpdate;

System.debug('Inserted PBEs: ' + pbesToInsert.size());
System.debug('Updated PBEs: ' + pbesToUpdate.size());

System.debug('======== PBE summary ========');
for (AggregateResult ar : [
    SELECT Product2.ProductCode code, Product2.Name name, COUNT(Id) cnt
    FROM PricebookEntry
    WHERE Product2.ProductCode IN :productCodes
    AND IsActive = true
    GROUP BY Product2.ProductCode, Product2.Name
    ORDER BY Product2.ProductCode
]) {
    System.debug((String) ar.get('code') + ' | ' + (String) ar.get('name') + ' | Active PBEs=' + ar.get('cnt'));
}

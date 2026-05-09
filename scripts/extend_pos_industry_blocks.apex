// Make POS products visible ONLY to Retail accounts.
// Currently they block only 4 industries (Finance, Manufacturing, Technology, Other).
// Extend the block list to cover ALL 31 non-retail industries on the picklist.
//
// Result: any non-Retail Account loses access to POS products in Browse Catalog.

Set<String> posProductCodes = new Set<String>{'POS01','ENPOS101','REG01','SCN01'};

// Pull all picklist values from ProductDisqualification.Industry__c
Schema.DescribeFieldResult d = Schema.SObjectType.ProductDisqualification.fields.getMap().get('industry__c').getDescribe();
List<String> allIndustries = new List<String>();
for (Schema.PicklistEntry pe : d.getPicklistValues()) {
    if (pe.isActive() && pe.getValue() != 'Retail') allIndustries.add(pe.getValue());
}
System.debug('Non-retail industries to block: ' + allIndustries.size() + ' total');

// Group existing PDQ industries per product
Map<Id, Set<String>> existingByProduct = new Map<Id, Set<String>>();
Map<String, Id> productIdByCode = new Map<String, Id>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :posProductCodes]) {
    productIdByCode.put(p.ProductCode, p.Id);
    existingByProduct.put(p.Id, new Set<String>());
}
for (ProductDisqualification pdq : [SELECT ProductId, Industry__c FROM ProductDisqualification WHERE ProductId IN :existingByProduct.keySet()]) {
    existingByProduct.get(pdq.ProductId).add(pdq.Industry__c);
}

// Build the list of new PDQs to insert
List<ProductDisqualification> toInsert = new List<ProductDisqualification>();
for (String code : posProductCodes) {
    Id productId = productIdByCode.get(code);
    Set<String> existingInd = existingByProduct.get(productId);
    Integer added = 0;
    for (String industry : allIndustries) {
        if (!existingInd.contains(industry)) {
            toInsert.add(new ProductDisqualification(
                ProductId = productId,
                Industry__c = industry,
                Reason = 'POS solutions are designed for retail store operations. ' + industry + ' is outside the target customer profile.',
                EffectiveFromDate = Date.today().addDays(-1),
                EffectiveToDate = Date.newInstance(2099, 12, 31)
            ));
            added++;
        }
    }
    System.debug('  ' + code + ': ' + added + ' new blocks (had ' + existingInd.size() + ' already)');
}

if (toInsert.isEmpty()) {
    System.debug('Nothing to insert — all products already blocked everywhere.');
    return;
}
insert toInsert;
System.debug('Inserted ' + toInsert.size() + ' new ProductDisqualification rows');

// Verify final per-product block count
System.debug('======== FINAL BLOCK COUNT ========');
for (AggregateResult ar : [
    SELECT Product.Name name, COUNT(Id) cnt
    FROM ProductDisqualification
    WHERE Product.ProductCode IN :posProductCodes
    GROUP BY Product.Name
    ORDER BY Product.Name
]) {
    System.debug('  ' + ar.get('name') + ' | ' + ar.get('cnt') + ' industries blocked (Retail is the only one allowed)');
}

// Smaller batch — 8 strategic non-retail industries to add to POS block list.
// Plus the existing 4 (Finance, Manufacturing, Technology, Other) = 12 total blocks per product.
// Covers all common B2B sectors and all existing demo Accounts.

Set<String> posProductCodes = new Set<String>{'POS01','ENPOS101','REG01','SCN01'};
List<String> newBlockedIndustries = new List<String>{
    'Healthcare',          // Grand Hotels (Hospitality), but also hospitals
    'Education',           // University of Arizona
    'Hospitality',         // Grand Hotels
    'Apparel',             // Burlington Textiles
    'Banking',             // common
    'Energy',              // United Oil & Gas
    'Construction',        // common B2B
    'Telecommunications'   // common B2B
};

Map<String, Id> productIdByCode = new Map<String, Id>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :posProductCodes]) {
    productIdByCode.put(p.ProductCode, p.Id);
}

Map<Id, Set<String>> existingByProduct = new Map<Id, Set<String>>();
for (Id pid : productIdByCode.values()) existingByProduct.put(pid, new Set<String>());
for (ProductDisqualification pdq : [SELECT ProductId, Industry__c FROM ProductDisqualification WHERE ProductId IN :productIdByCode.values()]) {
    existingByProduct.get(pdq.ProductId).add(pdq.Industry__c);
}

List<ProductDisqualification> toInsert = new List<ProductDisqualification>();
for (String code : posProductCodes) {
    Id pid = productIdByCode.get(code);
    Set<String> existingInd = existingByProduct.get(pid);
    for (String ind : newBlockedIndustries) {
        if (!existingInd.contains(ind)) {
            toInsert.add(new ProductDisqualification(
                ProductId = pid,
                Industry__c = ind,
                Reason = 'POS solutions are designed for retail store operations. ' + ind + ' is outside the target customer profile.',
                EffectiveFromDate = Date.today().addDays(-1),
                EffectiveToDate = Date.newInstance(2099, 12, 31)
            ));
        }
    }
}

System.debug('Inserting ' + toInsert.size() + ' new PDQ rows (8 industries x 4 products = 32 max)');
List<Database.SaveResult> srs = Database.insert(toInsert, false);
Integer ok = 0, fail = 0;
for (Integer i = 0; i < srs.size(); i++) {
    if (srs[i].isSuccess()) ok++;
    else { fail++; System.debug('FAIL: ' + srs[i].getErrors()[0].getMessage()); }
}
System.debug('Inserted: ' + ok + ' | Failed: ' + fail);

// Verify
for (AggregateResult ar : [SELECT Product.Name name, COUNT(Id) cnt FROM ProductDisqualification WHERE Product.ProductCode IN :posProductCodes GROUP BY Product.Name ORDER BY Product.Name]) {
    System.debug('  ' + ar.get('name') + ' | ' + ar.get('cnt') + ' industries blocked');
}

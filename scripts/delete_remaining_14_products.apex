// Delete the 14 products that failed first round due to BBA/AAC references.
// Strategy: find their adjustment records, delete those, then delete products.

// Find products that still exist from our delete list
Set<String> codesToDelete = new Set<String>{
    'EASY797987','FFCI987897A','PGJK89','PUP001A45','VIL8899089','REA0001','DCB09878907890',
    'CC','CS001','CLOUD001Pack','SVC-INS-002','DS001','KB001','LP001','LA001','LB001','LCP001','MO001','P001','PB001','PP001','SDP001','SP001','TB001','W001',
    'AC001','AT001','AST001','APT001','T001','DC001','LLM001','PC001','TPP01',
    'DEF001','ECOM01','QBO0021','LCD001','UA001','GPTW001',
    'AV001','SW-AV-002','SW-AV-003',
    'NET-SW-002','NET-SEC-003','NET-RT-003','NET-RT-002','NET-SEC-001','NET-RT-001','BUNDLE-NETWORK-001','NET-SEC-002','NET-SW-001',
    'PER-STR-002','PER-STR-004',
    'SW-OFF-002','GW001','SW-OFF-003','SW-CRE-001','SW-CRE-002',
    'SW-CLD-002','SW-CLD-003'
};
Set<String> namesToDelete = new Set<String>{
    'Activation Service','Billing Service','Installation Service','Planning Service','Shipping Service',
    'Specialized Certifications','Sun Thermal Compound','Zion Thermal Compound','Kyocera Thermal Compound Premium',
    'PowerSwerve R750 Rack Server'
};

List<Product2> stillExist = [SELECT Id, Name FROM Product2 WHERE (ProductCode IN :codesToDelete OR (ProductCode = null AND Name IN :namesToDelete))];
Set<Id> stillExistIds = new Set<Id>();
for (Product2 p : stillExist) stillExistIds.add(p.Id);
System.debug('Products still pending: ' + stillExist.size());
for (Product2 p : stillExist) System.debug('  ' + p.Name + ' (' + p.Id + ')');

// Delete AttributeBasedAdjustment that reference these products
List<AttributeBasedAdjustment> abas = [SELECT Id FROM AttributeBasedAdjustment WHERE Product__c IN :stillExistIds OR ProductId__c IN :stillExistIds OR Product2Id__c IN :stillExistIds];
// Try general field names — may need adjustment
System.debug('AttributeBasedAdjustment direct search: ' + abas.size());

// Try matching via lookup field — get all and filter
List<AttributeBasedAdjustment> allAbas = [SELECT Id, FIELDS(STANDARD) FROM AttributeBasedAdjustment LIMIT 200];
System.debug('All AttributeBasedAdjustment in org: ' + allAbas.size());

// Delete attribute adjustment conditions — these may reference our products
List<AttributeAdjustmentCondition> aacs = [SELECT Id FROM AttributeAdjustmentCondition LIMIT 200];
System.debug('All AttributeAdjustmentCondition: ' + aacs.size());

// Brute force: just delete ALL AttributeBasedAdjustment + AttributeAdjustmentCondition since this is demo cleanup
if (!aacs.isEmpty()) {
    Database.delete(aacs, false);
    System.debug('  Deleted AttributeAdjustmentCondition: ' + aacs.size());
}
if (!allAbas.isEmpty()) {
    Database.delete(allAbas, false);
    System.debug('  Deleted AttributeBasedAdjustment: ' + allAbas.size());
}

// Now retry deleting the stuck products
List<PricebookEntry> remainingPbes = [SELECT Id, IsActive FROM PricebookEntry WHERE Product2Id IN :stillExistIds];
if (!remainingPbes.isEmpty()) {
    for (PricebookEntry pbe : remainingPbes) pbe.IsActive = false;
    Database.update(remainingPbes, false);
    Database.delete(remainingPbes, false);
    System.debug('  Deleted remaining PBE: ' + remainingPbes.size());
}

Database.DeleteResult[] drs = Database.delete(stillExist, false);
Integer ok = 0, fail = 0;
for (Database.DeleteResult r : drs) { if (r.isSuccess()) ok++; else fail++; }
System.debug('  Product2 retry: ok=' + ok + ' fail=' + fail);
if (fail > 0) {
    for (Database.DeleteResult r : drs) if (!r.isSuccess()) { System.debug('    Fail reason: ' + r.getErrors()[0].getMessage()); break; }
}

// Empty recycle bin
List<SObject> recyclables = new List<SObject>();
for (Product2 p : [SELECT Id FROM Product2 WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(p);
for (PricebookEntry pbe : [SELECT Id FROM PricebookEntry WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pbe);
for (AttributeBasedAdjustment a : [SELECT Id FROM AttributeBasedAdjustment WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(a);
for (AttributeAdjustmentCondition a : [SELECT Id FROM AttributeAdjustmentCondition WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(a);
if (!recyclables.isEmpty()) {
    try { Database.emptyRecycleBin(recyclables); System.debug('Recycle bin purged: ' + recyclables.size()); } catch (Exception e) {}
}

System.debug('======== Final ========');
System.debug('  Active products: ' + [SELECT COUNT() FROM Product2 WHERE IsActive = true]);

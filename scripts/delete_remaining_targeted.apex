// Targeted deletion: only delete ABAs/AACs that reference the 14 remaining products,
// preserving ABAs for kept products (Laptop Pro Bundle etc.).

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
Set<Id> stillIds = new Set<Id>();
for (Product2 p : stillExist) { stillIds.add(p.Id); System.debug('Pending: ' + p.Name); }

// Delete ABAs that reference ONLY our delete-target products
List<AttributeBasedAdjustment> targetedAbas = [SELECT Id FROM AttributeBasedAdjustment WHERE ProductId IN :stillIds];
System.debug('ABAs to delete (targeted): ' + targetedAbas.size());

// Find AAC records that reference our products via the ABA Rule
Set<Id> abaRuleIds = new Set<Id>();
for (AttributeBasedAdjustment a : [SELECT AttributeBasedAdjRuleId FROM AttributeBasedAdjustment WHERE ProductId IN :stillIds]) {
    if (a.AttributeBasedAdjRuleId != null) abaRuleIds.add(a.AttributeBasedAdjRuleId);
}
List<AttributeAdjustmentCondition> targetedAacs = [SELECT Id FROM AttributeAdjustmentCondition WHERE AttributeBasedAdjRuleId IN :abaRuleIds];
System.debug('AACs to delete (targeted): ' + targetedAacs.size());

// Delete in correct order: AAC first (depends on ABA), then ABA, then ABA Rules
if (!targetedAacs.isEmpty()) {
    Database.delete(targetedAacs, false);
    System.debug('  Deleted AAC: ' + targetedAacs.size());
}
if (!targetedAbas.isEmpty()) {
    Database.delete(targetedAbas, false);
    System.debug('  Deleted ABA: ' + targetedAbas.size());
}
List<AttributeBasedAdjRule> targetedRules = [SELECT Id FROM AttributeBasedAdjRule WHERE Id IN :abaRuleIds];
if (!targetedRules.isEmpty()) {
    Database.delete(targetedRules, false);
    System.debug('  Deleted ABA Rule: ' + targetedRules.size());
}

// Retry PBE delete
List<PricebookEntry> remainingPbes = [SELECT Id, IsActive FROM PricebookEntry WHERE Product2Id IN :stillIds];
if (!remainingPbes.isEmpty()) {
    for (PricebookEntry p : remainingPbes) p.IsActive = false;
    Database.update(remainingPbes, false);
    Database.delete(remainingPbes, false);
    System.debug('  Deleted PBE: ' + remainingPbes.size());
}

// Retry Product2 delete
Database.DeleteResult[] drs = Database.delete(stillExist, false);
Integer ok = 0, fail = 0;
List<String> errMsgs = new List<String>();
for (Integer i = 0; i < drs.size(); i++) {
    if (drs[i].isSuccess()) ok++;
    else {
        fail++;
        if (errMsgs.size() < 3) errMsgs.add(stillExist[i].Name + ': ' + drs[i].getErrors()[0].getMessage());
    }
}
System.debug('Product2 retry: ok=' + ok + ' fail=' + fail);
for (String m : errMsgs) System.debug('  ' + m);

// Empty recycle bin
List<SObject> recyclables = new List<SObject>();
for (Product2 p : [SELECT Id FROM Product2 WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(p);
for (PricebookEntry pbe : [SELECT Id FROM PricebookEntry WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pbe);
for (AttributeBasedAdjustment a : [SELECT Id FROM AttributeBasedAdjustment WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(a);
for (AttributeAdjustmentCondition a : [SELECT Id FROM AttributeAdjustmentCondition WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(a);
for (AttributeBasedAdjRule a : [SELECT Id FROM AttributeBasedAdjRule WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(a);
if (!recyclables.isEmpty()) {
    try { Database.emptyRecycleBin(recyclables); System.debug('Recycle bin purged: ' + recyclables.size()); } catch (Exception e) {}
}

System.debug('======== Final ========');
System.debug('  Active products: ' + [SELECT COUNT() FROM Product2 WHERE IsActive = true]);

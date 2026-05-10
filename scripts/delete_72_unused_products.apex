// Bulk delete 72 unused products + cascading dependent records.
// Order: PCP -> PSMO -> PQ -> PDQ -> PBE (inactivate then delete) -> Product2 -> empty recycle bin.

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

List<Product2> targets = [SELECT Id FROM Product2 WHERE (ProductCode IN :codesToDelete OR (ProductCode = null AND Name IN :namesToDelete))];
Set<Id> targetIds = new Set<Id>();
for (Product2 p : targets) targetIds.add(p.Id);
System.debug('Target products: ' + targets.size());

// Step 1: Delete ProductCategoryProduct
List<ProductCategoryProduct> pcps = [SELECT Id FROM ProductCategoryProduct WHERE ProductId IN :targetIds];
if (!pcps.isEmpty()) {
    Database.delete(pcps, false);
    System.debug('  Deleted ProductCategoryProduct: ' + pcps.size());
}

// Step 2: Delete ProductSellingModelOption
List<ProductSellingModelOption> psmos = [SELECT Id FROM ProductSellingModelOption WHERE Product2Id IN :targetIds];
if (!psmos.isEmpty()) {
    Database.delete(psmos, false);
    System.debug('  Deleted ProductSellingModelOption: ' + psmos.size());
}

// Step 3: Delete ProductQualification
List<ProductQualification> pqs = [SELECT Id FROM ProductQualification WHERE ProductId IN :targetIds];
if (!pqs.isEmpty()) {
    Database.delete(pqs, false);
    System.debug('  Deleted ProductQualification: ' + pqs.size());
}

// Step 4: Delete ProductDisqualification
List<ProductDisqualification> pdqs = [SELECT Id FROM ProductDisqualification WHERE ProductId IN :targetIds];
if (!pdqs.isEmpty()) {
    Database.delete(pdqs, false);
    System.debug('  Deleted ProductDisqualification: ' + pdqs.size());
}

// Step 5: Inactivate then delete PricebookEntries
List<PricebookEntry> pbes = [SELECT Id, IsActive FROM PricebookEntry WHERE Product2Id IN :targetIds];
if (!pbes.isEmpty()) {
    for (PricebookEntry pbe : pbes) pbe.IsActive = false;
    Database.update(pbes, false);
    Database.delete(pbes, false);
    System.debug('  Deleted PricebookEntry: ' + pbes.size());
}

// Step 6: Delete Product2
Database.DeleteResult[] prDr = Database.delete(targets, false);
Integer prOk = 0, prFail = 0;
List<String> firstFails = new List<String>();
for (Integer i = 0; i < prDr.size(); i++) {
    if (prDr[i].isSuccess()) prOk++;
    else {
        prFail++;
        if (firstFails.size() < 3) firstFails.add(prDr[i].getErrors()[0].getMessage());
    }
}
System.debug('  Product2 deleted: ' + prOk + ' / Failed: ' + prFail);
if (prFail > 0) {
    for (String f : firstFails) System.debug('    Sample fail: ' + f);
}

// Step 7: Empty recycle bin for the deletes
List<SObject> recyclables = new List<SObject>();
for (Product2 p : [SELECT Id FROM Product2 WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(p);
for (PricebookEntry pbe : [SELECT Id FROM PricebookEntry WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pbe);
for (ProductCategoryProduct pcp : [SELECT Id FROM ProductCategoryProduct WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pcp);
for (ProductSellingModelOption psmo : [SELECT Id FROM ProductSellingModelOption WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(psmo);
for (ProductQualification pq : [SELECT Id FROM ProductQualification WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pq);
if (!recyclables.isEmpty()) {
    try {
        Database.emptyRecycleBin(recyclables);
        System.debug('Recycle bin purged: ' + recyclables.size());
    } catch (Exception e) {
        System.debug('Purge fail: ' + e.getMessage());
    }
}

// Final state
System.debug('======== After cleanup ========');
System.debug('  Active products: ' + [SELECT COUNT() FROM Product2 WHERE IsActive = true]);

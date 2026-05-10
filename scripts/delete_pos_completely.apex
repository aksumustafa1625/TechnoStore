// Delete all POS products and the POS Solutions category from TechStore Electronics Catalog.

// 1. Find POS products
Set<String> posCodes = new Set<String>{'POS01','ENPOS101','REG01','SCN01'};
List<Product2> posProducts = [SELECT Id, Name FROM Product2 WHERE ProductCode IN :posCodes];
Set<Id> posIds = new Set<Id>();
for (Product2 p : posProducts) { posIds.add(p.Id); System.debug('POS product: ' + p.Name + ' (' + p.Id + ')'); }
System.debug('Total POS products to delete: ' + posProducts.size());

// 2. Cascade delete dependents
Database.delete([SELECT Id FROM ProductCategoryProduct WHERE ProductId IN :posIds], false);
Database.delete([SELECT Id FROM ProductSellingModelOption WHERE Product2Id IN :posIds], false);
Database.delete([SELECT Id FROM ProductQualification WHERE ProductId IN :posIds], false);
Database.delete([SELECT Id FROM ProductDisqualification WHERE ProductId IN :posIds], false);
System.debug('Deleted dependents');

// 3. Inactivate then delete PBEs
List<PricebookEntry> pbes = [SELECT Id, IsActive FROM PricebookEntry WHERE Product2Id IN :posIds];
for (PricebookEntry pbe : pbes) pbe.IsActive = false;
Database.update(pbes, false);
Database.delete(pbes, false);
System.debug('Deleted PricebookEntry: ' + pbes.size());

// 4. Delete Product2 records
Database.DeleteResult[] drs = Database.delete(posProducts, false);
Integer ok = 0, fail = 0;
for (Database.DeleteResult r : drs) { if (r.isSuccess()) ok++; else fail++; }
System.debug('Product2 deleted: ' + ok + ' / failed: ' + fail);

// 5. Delete POS Solutions category in TechStore Electronics Catalog
List<ProductCategory> posCats = [SELECT Id, Name, Catalog.Name FROM ProductCategory WHERE Name = 'POS Solutions' AND Catalog.Name = 'TechStore Electronics Catalog'];
for (ProductCategory pc : posCats) System.debug('Deleting category: ' + pc.Name + ' in ' + pc.Catalog.Name);
if (!posCats.isEmpty()) {
    Database.DeleteResult[] catDrs = Database.delete(posCats, false);
    Integer catOk = 0;
    for (Database.DeleteResult r : catDrs) if (r.isSuccess()) catOk++;
    System.debug('Categories deleted: ' + catOk);
}

// 6. Empty recycle bin for what we deleted
List<SObject> recyclables = new List<SObject>();
for (Product2 p : [SELECT Id FROM Product2 WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(p);
for (PricebookEntry pbe : [SELECT Id FROM PricebookEntry WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pbe);
for (ProductCategoryProduct pcp : [SELECT Id FROM ProductCategoryProduct WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pcp);
for (ProductCategory pc : [SELECT Id FROM ProductCategory WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pc);
for (ProductSellingModelOption psmo : [SELECT Id FROM ProductSellingModelOption WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(psmo);
for (ProductQualification pq : [SELECT Id FROM ProductQualification WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pq);
for (ProductDisqualification pdq : [SELECT Id FROM ProductDisqualification WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclables.add(pdq);
if (!recyclables.isEmpty()) {
    try { Database.emptyRecycleBin(recyclables); System.debug('Recycle bin purged: ' + recyclables.size()); } catch (Exception e) { System.debug('Purge failed: ' + e.getMessage()); }
}

// 7. Final verification
System.debug('======== After cleanup ========');
System.debug('POS products remaining: ' + [SELECT COUNT() FROM Product2 WHERE ProductCode IN :posCodes]);
System.debug('POS Solutions categories remaining in Electronics Catalog: ' + [SELECT COUNT() FROM ProductCategory WHERE Name = 'POS Solutions' AND Catalog.Name = 'TechStore Electronics Catalog']);
System.debug('Total active products: ' + [SELECT COUNT() FROM Product2 WHERE IsActive = true]);

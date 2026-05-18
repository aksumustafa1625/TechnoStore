// Phase 5 end-to-end test — pull SAP materials, upsert to Product2.
Integer beforeCount = [SELECT COUNT() FROM Product2 WHERE SAP_Material_Number__c != null];
System.debug('Product2 with SAP_Material_Number__c BEFORE: ' + beforeCount);

SapMaterialMasterSyncService.Request req = new SapMaterialMasterSyncService.Request();
req.maxFetch = 10;
List<SapMaterialMasterSyncService.Result> results = SapMaterialMasterSyncService.sync(new List<SapMaterialMasterSyncService.Request>{ req });
for (SapMaterialMasterSyncService.Result r : results) {
    System.debug('=== Sync Result ===');
    System.debug('  totalFetched = ' + r.totalFetched);
    System.debug('  created      = ' + r.createdCount);
    System.debug('  updated      = ' + r.updatedCount);
    System.debug('  failed       = ' + r.failedCount);
    System.debug('  status       = ' + r.status);
    System.debug('  message      = ' + r.message);
}

Integer afterCount = [SELECT COUNT() FROM Product2 WHERE SAP_Material_Number__c != null];
System.debug('Product2 with SAP_Material_Number__c AFTER: ' + afterCount);

System.debug('=== Sample of SAP-synced Products ===');
for (Product2 p : [SELECT Name, SAP_Material_Number__c, SAP_Product_Description__c, SAP_Last_Synced_At__c FROM Product2 WHERE SAP_Last_Synced_At__c = TODAY ORDER BY SAP_Last_Synced_At__c DESC LIMIT 5]) {
    System.debug('  ' + p.Name + ' | SAP=' + p.SAP_Material_Number__c + ' | Desc=' + p.SAP_Product_Description__c);
}

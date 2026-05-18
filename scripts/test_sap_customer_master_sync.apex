// Phase 6 end-to-end test — pull SAP BPs, upsert to Account.
Integer beforeCount = [SELECT COUNT() FROM Account WHERE SAP_BP_Number__c != null];
System.debug('Account with SAP_BP_Number__c BEFORE: ' + beforeCount);

SapCustomerMasterSyncService.Request req = new SapCustomerMasterSyncService.Request();
req.maxFetch = 10;
List<SapCustomerMasterSyncService.Result> results = SapCustomerMasterSyncService.sync(new List<SapCustomerMasterSyncService.Request>{ req });
for (SapCustomerMasterSyncService.Result r : results) {
    System.debug('=== Sync Result ===');
    System.debug('  totalFetched = ' + r.totalFetched);
    System.debug('  created      = ' + r.createdCount);
    System.debug('  updated      = ' + r.updatedCount);
    System.debug('  failed       = ' + r.failedCount);
    System.debug('  status       = ' + r.status);
    System.debug('  message      = ' + r.message);
}

Integer afterCount = [SELECT COUNT() FROM Account WHERE SAP_BP_Number__c != null];
System.debug('Account with SAP_BP_Number__c AFTER: ' + afterCount);

System.debug('=== Sample of SAP-synced Accounts ===');
for (Account a : [SELECT Name, SAP_BP_Number__c, SAP_Customer_Category__c, SAP_Customer_Group__c, SAP_Last_Synced_At__c FROM Account WHERE SAP_Last_Synced_At__c = TODAY ORDER BY SAP_Last_Synced_At__c DESC LIMIT 5]) {
    System.debug('  ' + a.Name + ' | BP=' + a.SAP_BP_Number__c + ' | Cat=' + a.SAP_Customer_Category__c + ' | Grp=' + a.SAP_Customer_Group__c);
}

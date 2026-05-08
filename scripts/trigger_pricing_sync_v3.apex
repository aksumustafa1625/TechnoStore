// Look at existing sync records' fields and pattern, then trigger fresh syncs

System.debug('======== Recent sync records (full detail) ========');
for (ContextDefinitionSync cds : [SELECT Id, ContextDefinitionName, Status, StartDateTime, EndDateTime, SynchronizationInformation, CreatedDate
                                  FROM ContextDefinitionSync
                                  ORDER BY CreatedDate DESC LIMIT 10]) {
    System.debug(cds);
}

System.debug('======== Status picklist values ========');
Schema.DescribeFieldResult statusF = Schema.SObjectType.ContextDefinitionSync.fields.getMap().get('status').getDescribe();
for (Schema.PicklistEntry pe : statusF.getPicklistValues()) {
    System.debug('  ' + pe.getValue());
}

// Try to insert a new sync request for relevant contexts
List<String> contextNames = new List<String>{'BrowseProductsCtxDefinition', 'RevSalesTransactionContext', 'RLM_SalesTransactionContext'};
for (String name : contextNames) {
    try {
        ContextDefinitionSync newSync = new ContextDefinitionSync(
            ContextDefinitionName = name,
            Status = 'Queued',
            StartDateTime = DateTime.now()
        );
        insert newSync;
        System.debug('Inserted sync for ' + name + ': ' + newSync.Id);
    } catch (Exception e) {
        System.debug('Failed sync for ' + name + ': ' + e.getMessage());
    }
}

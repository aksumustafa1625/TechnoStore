// Try invoking the actual sync via Apex
// Based on the existing pattern, sync records are inserted with status='in_progress'
// then Salesforce processes them in the background.

// First check what user owns this — sync records seem to need owner
List<String> ctxNames = new List<String>{'BrowseProductsCtxDefinition', 'RevSalesTransactionContext'};

for (String ctxName : ctxNames) {
    try {
        ContextDefinitionSync s = new ContextDefinitionSync(
            ContextDefinitionName = ctxName,
            Status = 'in_progress',
            StartDateTime = DateTime.now()
        );
        insert s;
        System.debug('Inserted sync for ' + ctxName + ': ' + s.Id);
    } catch (Exception e) {
        System.debug('FAIL ' + ctxName + ': ' + e.getTypeName() + ' — ' + e.getMessage());
    }
}

// Wait a moment and check status
System.debug('--- Sync record states ---');
for (ContextDefinitionSync cds : [SELECT Id, ContextDefinitionName, Status, StartDateTime, EndDateTime, SynchronizationInformation
                                  FROM ContextDefinitionSync
                                  WHERE ContextDefinitionName IN :ctxNames
                                  ORDER BY CreatedDate DESC LIMIT 5]) {
    System.debug(cds);
}

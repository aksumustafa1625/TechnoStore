// Remove stuck/manual sync request records created during diagnostics.
// These are not demo business data and can block new setup rows in a storage
// limited Developer Edition org.

List<ContextDefinitionSync> contextSyncs = [
    SELECT Id, ContextDefinitionName, Status
    FROM ContextDefinitionSync
    WHERE Status = 'in_progress'
    AND ContextDefinitionName IN ('BrowseProductsCtxDefinition', 'RevSalesTransactionContext')
];
if (!contextSyncs.isEmpty()) delete contextSyncs;

List<SetupDataSynchronization> setupSyncs = [
    SELECT Id, TargetRecordType, SynchronizationStatus
    FROM SetupDataSynchronization
    WHERE SynchronizationStatus = 'InProgress'
];
if (!setupSyncs.isEmpty()) delete setupSyncs;

System.debug('Deleted ContextDefinitionSync rows: ' + contextSyncs.size());
System.debug('Deleted SetupDataSynchronization rows: ' + setupSyncs.size());

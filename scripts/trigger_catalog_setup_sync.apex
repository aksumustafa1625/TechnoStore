// Try to trigger Product Discovery catalog setup data synchronization.

Id catalogId = [SELECT Id FROM ProductCatalog WHERE Name = 'TechStore Electronics Catalog' LIMIT 1].Id;

SetupDataSynchronization sync = new SetupDataSynchronization(
    RecordIdentifierId = catalogId,
    TargetRecordType = 'Catalog',
    SynchronizationStatus = 'InProgress',
    LastSynchronizationDateTime = DateTime.now()
);
insert sync;

System.debug('Inserted SetupDataSynchronization: ' + sync.Id);

for (SetupDataSynchronization s : [
    SELECT Id, RecordIdentifierId, TargetRecordType, SynchronizationStatus, LastSynchronizationDateTime, CreatedDate
    FROM SetupDataSynchronization
    WHERE Id = :sync.Id
]) {
    System.debug(s);
}

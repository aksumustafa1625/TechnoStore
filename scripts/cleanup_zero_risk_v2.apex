// Zero-risk cleanup v2: only what's actually deletable via Apex.
// ApexLog and AsyncApexJob are platform-protected; need UI/Tooling API.

System.debug('======== Before ========');
System.debug('  ContextDefinitionSync: ' + [SELECT COUNT() FROM ContextDefinitionSync]);

// Stuck in_progress syncs (older than 1 hour)
List<ContextDefinitionSync> stuck = [SELECT Id FROM ContextDefinitionSync WHERE Status = 'in_progress' AND CreatedDate < :Datetime.now().addHours(-1) LIMIT 200];
System.debug('  stuck in_progress (>1hr): ' + stuck.size());

// Old completed/failed syncs (older than 1 day)
List<ContextDefinitionSync> oldSyncs = [SELECT Id FROM ContextDefinitionSync WHERE Status IN ('success','failed') AND CreatedDate < :Datetime.now().addDays(-1) LIMIT 200];
System.debug('  old completed/failed (>1d): ' + oldSyncs.size());

List<ContextDefinitionSync> toDelete = new List<ContextDefinitionSync>();
toDelete.addAll(stuck);
toDelete.addAll(oldSyncs);

if (!toDelete.isEmpty()) {
    Database.DeleteResult[] drs = Database.delete(toDelete, false);
    Integer ok = 0;
    for (Database.DeleteResult r : drs) if (r.isSuccess()) ok++;
    System.debug('Deleted: ' + ok + ' / ' + drs.size());

    // Hard-purge from recycle bin
    List<ContextDefinitionSync> deletedRecs = [SELECT Id FROM ContextDefinitionSync WHERE IsDeleted = true LIMIT 200 ALL ROWS];
    if (!deletedRecs.isEmpty()) {
        try {
            Database.emptyRecycleBin(deletedRecs);
            System.debug('Recycle bin purged: ' + deletedRecs.size());
        } catch (Exception e) {
            System.debug('Purge failed: ' + e.getMessage());
        }
    }
}

System.debug('======== After ========');
System.debug('  ContextDefinitionSync: ' + [SELECT COUNT() FROM ContextDefinitionSync]);

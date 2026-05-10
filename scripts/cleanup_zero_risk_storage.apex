// Zero-risk storage cleanup: ApexLog + completed AsyncApexJob + stuck ContextDefinitionSync.
// All preserve demo functionality (only deletes historical log/queue records).

System.debug('======== Before cleanup ========');
System.debug('  ApexLog: ' + [SELECT COUNT() FROM ApexLog]);
System.debug('  AsyncApexJob (Completed/Failed/Aborted): ' + [SELECT COUNT() FROM AsyncApexJob WHERE Status IN ('Completed','Failed','Aborted')]);
System.debug('  ContextDefinitionSync (in_progress > 1hr old, never completed): ' + [SELECT COUNT() FROM ContextDefinitionSync WHERE Status = 'in_progress' AND CreatedDate < :Datetime.now().addHours(-1)]);

// 1. ApexLog
List<Database.DeleteResult> drs1;
try {
    drs1 = Database.delete([SELECT Id FROM ApexLog LIMIT 200], false);
    Integer ok = 0;
    for (Database.DeleteResult r : drs1) if (r.isSuccess()) ok++;
    System.debug('Deleted ApexLog: ' + ok + ' / ' + drs1.size());
} catch (Exception e) {
    System.debug('ApexLog delete failed: ' + e.getMessage());
}

// 2. AsyncApexJob — delete completed/failed/aborted
try {
    List<AsyncApexJob> jobs = [SELECT Id FROM AsyncApexJob WHERE Status IN ('Completed','Failed','Aborted') LIMIT 200];
    Database.DeleteResult[] drs2 = Database.delete(jobs, false);
    Integer ok = 0, fail = 0;
    for (Database.DeleteResult r : drs2) {
        if (r.isSuccess()) ok++; else fail++;
    }
    System.debug('Deleted AsyncApexJob: ' + ok + ' / ' + drs2.size() + (fail > 0 ? ' (some failed - platform may protect these)' : ''));
} catch (Exception e) {
    System.debug('AsyncApexJob delete failed: ' + e.getMessage());
}

// 3. ContextDefinitionSync — stuck in_progress
try {
    List<ContextDefinitionSync> syncs = [SELECT Id FROM ContextDefinitionSync WHERE Status = 'in_progress' AND CreatedDate < :Datetime.now().addHours(-1) LIMIT 200];
    if (!syncs.isEmpty()) {
        delete syncs;
        System.debug('Deleted stuck ContextDefinitionSync: ' + syncs.size());
    }
} catch (Exception e) {
    System.debug('ContextDefinitionSync delete failed: ' + e.getMessage());
}

// Empty recycle bin for what we just deleted
List<SObject> recyclableProbe = new List<SObject>();
for (ApexLog l : [SELECT Id FROM ApexLog WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclableProbe.add(l);
for (AsyncApexJob j : [SELECT Id FROM AsyncApexJob WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclableProbe.add(j);
for (ContextDefinitionSync s : [SELECT Id FROM ContextDefinitionSync WHERE IsDeleted = true LIMIT 200 ALL ROWS]) recyclableProbe.add(s);
if (!recyclableProbe.isEmpty()) {
    try {
        Database.emptyRecycleBin(recyclableProbe);
        System.debug('Recycle bin purged: ' + recyclableProbe.size() + ' records');
    } catch (Exception e) {
        System.debug('Recycle bin purge: ' + e.getMessage());
    }
}

System.debug('======== After cleanup ========');
System.debug('  ApexLog: ' + [SELECT COUNT() FROM ApexLog]);
System.debug('  AsyncApexJob: ' + [SELECT COUNT() FROM AsyncApexJob]);
System.debug('  ContextDefinitionSync (in_progress): ' + [SELECT COUNT() FROM ContextDefinitionSync WHERE Status = 'in_progress']);

// Permanently purge recently deleted setup/link records to free Developer
// Edition data storage. These were deleted by the POS category repurpose steps.

List<SObject> deletedRecords = new List<SObject>();

for (ProductCategoryProduct pcp : [
    SELECT Id
    FROM ProductCategoryProduct
    WHERE IsDeleted = true
    LIMIT 200
    ALL ROWS
]) {
    deletedRecords.add(pcp);
}

for (ContextDefinitionSync cds : [
    SELECT Id
    FROM ContextDefinitionSync
    WHERE IsDeleted = true
    LIMIT 200
    ALL ROWS
]) {
    deletedRecords.add(cds);
}

for (SetupDataSynchronization sds : [
    SELECT Id
    FROM SetupDataSynchronization
    WHERE IsDeleted = true
    LIMIT 200
    ALL ROWS
]) {
    deletedRecords.add(sds);
}

for (ProductDisqualification pdq : [
    SELECT Id
    FROM ProductDisqualification
    WHERE IsDeleted = true
    LIMIT 200
    ALL ROWS
]) {
    deletedRecords.add(pdq);
}

if (!deletedRecords.isEmpty()) {
    Database.emptyRecycleBin(deletedRecords);
}

System.debug('Purged deleted records: ' + deletedRecords.size());

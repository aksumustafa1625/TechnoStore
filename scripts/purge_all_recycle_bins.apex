// Aggressively empty Recycle Bin across all relevant objects to free Dev Edition storage.

List<String> objectsToCheck = new List<String>{
    'ProductDisqualification', 'ProductQualification', 'ProductCategoryProduct',
    'ProductSellingModelOption', 'PricebookEntry', 'Product2',
    'ContextDefinitionSync', 'ContentVersion', 'ContentDocument',
    'ProductCategory', 'AttributeBasedAdjustment', 'AttributeAdjustmentCondition'
};

Integer totalPurged = 0;
for (String objName : objectsToCheck) {
    try {
        String soql = 'SELECT Id FROM ' + objName + ' WHERE IsDeleted = true LIMIT 200 ALL ROWS';
        List<SObject> deleted = Database.query(soql);
        if (!deleted.isEmpty()) {
            Database.emptyRecycleBin(deleted);
            System.debug('Purged ' + deleted.size() + ' from ' + objName);
            totalPurged += deleted.size();
        }
    } catch (Exception e) {
        System.debug('Skip ' + objName + ': ' + e.getMessage());
    }
}
System.debug('======== TOTAL PURGED: ' + totalPurged + ' ========');

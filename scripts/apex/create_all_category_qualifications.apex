// Create ProductCategoryQualification records for ALL product categories
// IsQualified is auto-set to true when records are inserted

// Get all categories
List<ProductCategory> allCategories = [
    SELECT Id, Name, CatalogId
    FROM ProductCategory
    ORDER BY CatalogId, Name
];
System.debug('Total categories: ' + allCategories.size());

// Get existing category IDs to avoid duplicates
Set<Id> existingCategoryIds = new Set<Id>();
for (ProductCategoryQualification existing : [SELECT CategoryId FROM ProductCategoryQualification]) {
    existingCategoryIds.add(existing.CategoryId);
}
System.debug('Existing PCQ records: ' + existingCategoryIds.size());

// Build new records for categories without PCQ records
List<ProductCategoryQualification> toInsert = new List<ProductCategoryQualification>();
for (ProductCategory cat : allCategories) {
    if (!existingCategoryIds.contains(cat.Id)) {
        ProductCategoryQualification pcq = new ProductCategoryQualification();
        pcq.CategoryId = cat.Id;
        pcq.EffectiveFromDate = Date.valueOf('2026-01-01');
        pcq.EffectiveToDate = Date.valueOf('2026-12-31');
        toInsert.add(pcq);
    }
}

System.debug('Records to create: ' + toInsert.size());

if (!toInsert.isEmpty()) {
    insert toInsert;
    System.debug('SUCCESS: Created ' + toInsert.size() + ' ProductCategoryQualification records');
} else {
    System.debug('All categories already have qualification records');
}

// Verify final state
Integer finalCount = [SELECT COUNT() FROM ProductCategoryQualification WHERE IsQualified = true];
System.debug('Total qualified categories now: ' + finalCount);

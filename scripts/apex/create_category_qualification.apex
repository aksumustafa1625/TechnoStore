// Create ProductCategoryQualification records for ALL product categories
// This enables the EPC to show products when browsing catalog categories

// First, query all ProductCategory records
List<ProductCategory> allCategories = [
    SELECT Id, Name, CatalogId
    FROM ProductCategory
    ORDER BY CatalogId, Name
];

System.debug('Total categories found: ' + allCategories.size());

// Check if any ProductCategoryQualification records already exist
Integer existingCount = [SELECT COUNT() FROM ProductCategoryQualification];
System.debug('Existing ProductCategoryQualification records: ' + existingCount);

// Get existing CategoryIds to avoid duplicates
Set<Id> existingCategoryIds = new Set<Id>();
for (ProductCategoryQualification existing : [SELECT CategoryId FROM ProductCategoryQualification]) {
    existingCategoryIds.add(existing.CategoryId);
}

// Create ProductCategoryQualification records for categories that don't have one
List<ProductCategoryQualification> newRecords = new List<ProductCategoryQualification>();

for (ProductCategory cat : allCategories) {
    if (!existingCategoryIds.contains(cat.Id)) {
        ProductCategoryQualification pcq = new ProductCategoryQualification();
        pcq.CategoryId = cat.Id;
        pcq.IsQualified = true;
        pcq.EffectiveFromDate = Date.valueOf('2026-01-01');
        pcq.EffectiveToDate = Date.valueOf('2026-12-31');
        newRecords.add(pcq);
        System.debug('Creating PCQ for category: ' + cat.Name + ' (' + cat.Id + ')');
    }
}

System.debug('Records to create: ' + newRecords.size());

if (!newRecords.isEmpty()) {
    insert newRecords;
    System.debug('Successfully created ' + newRecords.size() + ' ProductCategoryQualification records');
} else {
    System.debug('No new records needed - all categories already have qualification records');
}

// Verify
Integer finalCount = [SELECT COUNT() FROM ProductCategoryQualification WHERE IsQualified = true];
System.debug('Final ProductCategoryQualification (IsQualified=true) count: ' + finalCount);

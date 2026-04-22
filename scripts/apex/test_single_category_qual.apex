// Test: Create ONE ProductCategoryQualification record for Laptop category
// and check if IsQualified gets auto-set

// Laptop category ID in TechStore Electronics: 0ZGaj000000LPRdGAO
String laptopCategoryId = '0ZGaj000000LPRdGAO';

// Create the record
ProductCategoryQualification pcq = new ProductCategoryQualification();
pcq.CategoryId = laptopCategoryId;
pcq.EffectiveFromDate = Date.valueOf('2026-01-01');
pcq.EffectiveToDate = Date.valueOf('2026-12-31');
// Note: IsQualified is read-only, not setting it

try {
    insert pcq;
    System.debug('Successfully created ProductCategoryQualification: ' + pcq.Id);

    // Read back to check IsQualified value
    ProductCategoryQualification created = [
        SELECT Id, CategoryId, IsQualified, EffectiveFromDate, EffectiveToDate
        FROM ProductCategoryQualification
        WHERE Id = :pcq.Id
    ];
    System.debug('Created record - IsQualified: ' + created.IsQualified);
    System.debug('Created record - CategoryId: ' + created.CategoryId);
    System.debug('Created record - EffectiveFromDate: ' + created.EffectiveFromDate);
    System.debug('Created record - EffectiveToDate: ' + created.EffectiveToDate);
} catch (Exception e) {
    System.debug('ERROR creating PCQ: ' + e.getMessage());
    System.debug('Error type: ' + e.getTypeName());
}

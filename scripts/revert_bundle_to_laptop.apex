// Revert bundle to original working state (Laptop BasedOn)
// This brings back the laptop attribute UI for demo purposes

Id bundleId = '01taj00000Qp7IFAAZ';
Id laptopClassId = '11Baj000015O78DEAS'; // Laptop classification

// Step 1: Revert BasedOn to Laptop
Product2 bundle = new Product2(Id = bundleId, BasedOnId = laptopClassId);
update bundle;
System.debug('STEP 1: Reverted bundle BasedOn to Laptop');

// Step 2: Find or recreate the original "Office Components" group
ProductComponentGroup officeGroup;
List<ProductComponentGroup> existing = [
    SELECT Id, Name FROM ProductComponentGroup
    WHERE Name = 'Office Components' AND ParentProductId = :bundleId LIMIT 1
];
if (!existing.isEmpty()) {
    officeGroup = existing[0];
    System.debug('STEP 2: Reusing Office Components group = ' + officeGroup.Id);
} else {
    officeGroup = new ProductComponentGroup(
        Name = 'Office Components',
        Code = 'OFFICE_COMPONENTS',
        ParentProductId = bundleId,
        Sequence = 1
    );
    insert officeGroup;
    System.debug('STEP 2: Recreated Office Components group = ' + officeGroup.Id);
}

// Step 3: Move all 5 PRCs back to Office Components group
List<ProductRelatedComponent> prcsToUpdate = new List<ProductRelatedComponent>();
for (ProductRelatedComponent prc : [
    SELECT Id, ProductComponentGroupId
    FROM ProductRelatedComponent
    WHERE ParentProductId = :bundleId
]) {
    if (prc.ProductComponentGroupId != officeGroup.Id) {
        prcsToUpdate.add(new ProductRelatedComponent(
            Id = prc.Id,
            ProductComponentGroupId = officeGroup.Id
        ));
    }
}
update prcsToUpdate;
System.debug('STEP 3: Moved ' + prcsToUpdate.size() + ' components back to Office Components group');

// Step 4: Optionally delete the 5 dedicated groups (cleanup)
List<ProductComponentGroup> groupsToDelete = [
    SELECT Id, Name FROM ProductComponentGroup
    WHERE ParentProductId = :bundleId
      AND Name IN ('Laptop Group','Monitor Group','Keyboard Group','Software Group','Warranty Group')
];
if (!groupsToDelete.isEmpty()) {
    delete groupsToDelete;
    System.debug('STEP 4: Deleted ' + groupsToDelete.size() + ' unused groups');
}

System.debug('=== REVERT COMPLETE ===');
System.debug('Bundle is back to original working state. Run Pricing Setup Sync.');

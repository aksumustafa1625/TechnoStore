// ============================================================
// FIX BUNDLE MULTI-COMPONENT UI ISSUE
// ============================================================
// 1. Create neutral "Office Bundle Container" classification
// 2. Change Home Office Bundle BasedOn to neutral classification
// 3. Create 5 separate ProductComponentGroups
// 4. Reassign each ProductRelatedComponent to its dedicated group

Id bundleId = '01taj00000Qp7IFAAZ';

// Component Id -> Group Name mapping
Map<Id, String> componentGroupMap = new Map<Id, String>{
    '01taj00000QnnlNAAR' => 'Laptop Group',     // TechNova ProBook 15
    '01taj00000QnnlwAAB' => 'Monitor Group',    // Monitor 24" IPS
    '01taj00000QnnmWAAR' => 'Keyboard Group',   // Wireless Combo Set
    '01taj00000QnnmjAAB' => 'Software Group',   // Microsoft 365 Personal
    '01taj00000QnnmuAAB' => 'Warranty Group'    // TechCover 1 Yıl
};

// =============================================================
// STEP 1: Create neutral "Office Bundle Container" classification
// =============================================================
ProductClassification neutralClass;
List<ProductClassification> existing = [
    SELECT Id, Name FROM ProductClassification WHERE Name = 'Office Bundle Container' LIMIT 1
];
if (!existing.isEmpty()) {
    neutralClass = existing[0];
    System.debug('STEP 1: Using existing Office Bundle Container = ' + neutralClass.Id);
} else {
    neutralClass = new ProductClassification(
        Name = 'Office Bundle Container',
        Code = 'OFFICE_BUNDLE_CONTAINER',
        Status = 'Active'
    );
    insert neutralClass;
    System.debug('STEP 1: Created Office Bundle Container = ' + neutralClass.Id);
}

// =============================================================
// STEP 2: Update bundle's BasedOnId to neutral classification
// =============================================================
Product2 bundle = new Product2(Id = bundleId, BasedOnId = neutralClass.Id);
update bundle;
System.debug('STEP 2: Updated bundle BasedOn to neutral classification');

// =============================================================
// STEP 3: Create 5 separate ProductComponentGroups
// =============================================================
Set<String> groupNames = new Set<String>(componentGroupMap.values());

Map<String, ProductComponentGroup> groupByName = new Map<String, ProductComponentGroup>();
for (ProductComponentGroup g : [
    SELECT Id, Name FROM ProductComponentGroup WHERE Name IN :groupNames AND ParentProductId = :bundleId
]) {
    groupByName.put(g.Name, g);
}

List<ProductComponentGroup> groupsToInsert = new List<ProductComponentGroup>();
Integer seq = 1;
for (String gName : groupNames) {
    if (groupByName.containsKey(gName)) continue;
    groupsToInsert.add(new ProductComponentGroup(
        Name = gName,
        Code = gName.replace(' ', '_').toUpperCase(),
        ParentProductId = bundleId,
        Sequence = seq++
    ));
}
if (!groupsToInsert.isEmpty()) {
    insert groupsToInsert;
    for (ProductComponentGroup g : groupsToInsert) {
        groupByName.put(g.Name, g);
    }
    System.debug('STEP 3: Created ' + groupsToInsert.size() + ' new ProductComponentGroups');
} else {
    System.debug('STEP 3: All 5 groups already exist');
}

// =============================================================
// STEP 4: Reassign ProductRelatedComponents to new groups
// =============================================================
List<ProductRelatedComponent> prcsToUpdate = new List<ProductRelatedComponent>();

for (ProductRelatedComponent prc : [
    SELECT Id, ChildProductId, ProductComponentGroupId
    FROM ProductRelatedComponent
    WHERE ParentProductId = :bundleId
]) {
    String targetGroupName = componentGroupMap.get(prc.ChildProductId);
    if (targetGroupName == null) continue;

    ProductComponentGroup targetGroup = groupByName.get(targetGroupName);
    if (targetGroup == null) {
        System.debug('Missing target group: ' + targetGroupName);
        continue;
    }

    if (prc.ProductComponentGroupId != targetGroup.Id) {
        prcsToUpdate.add(new ProductRelatedComponent(
            Id = prc.Id,
            ProductComponentGroupId = targetGroup.Id
        ));
    }
}

if (!prcsToUpdate.isEmpty()) {
    update prcsToUpdate;
    System.debug('STEP 4: Reassigned ' + prcsToUpdate.size() + ' components to dedicated groups');
} else {
    System.debug('STEP 4: All components already in correct groups');
}

System.debug('=== FIX COMPLETE ===');
System.debug('Next: Run Salesforce Pricing Setup Sync from Setup UI, then test bundle Configure UI');

// Create missing ProductConfigFlowAssignment records for Keyboard and Software
// These two classifications don't have ConfigFlowAssignment yet (External Monitor + Warranty Service do).

// Get the active default ProductConfigurationFlow
List<ProductConfigurationFlow> flows = [
    SELECT Id, Name FROM ProductConfigurationFlow LIMIT 1
];
if (flows.isEmpty()) {
    System.debug('NO ProductConfigurationFlow exists - cannot create assignments');
    return;
}
Id flowId = flows[0].Id;
System.debug('Using flow: ' + flows[0].Name + ' / ' + flowId);

// Classifications to add
Map<String, Id> targetClasses = new Map<String, Id>{
    'Keyboard' => '11Baj000014WD4LEAW',
    'Software' => '11Baj000014WD4AEAW'
};

// Check what's already there
Set<Id> existing = new Set<Id>();
for (ProductConfigFlowAssignment a : [
    SELECT ProductClassificationId FROM ProductConfigFlowAssignment
    WHERE ProductClassificationId IN :targetClasses.values()
]) {
    existing.add(a.ProductClassificationId);
}

// Discover required fields by reading existing assignment
ProductConfigFlowAssignment template;
try {
    template = [SELECT Name, ProductConfigurationFlowId, ProductClassificationId FROM ProductConfigFlowAssignment LIMIT 1];
    System.debug('Template name: ' + template.Name);
} catch (Exception e) {
    System.debug('No template found');
}

// Create new assignments
List<ProductConfigFlowAssignment> toInsert = new List<ProductConfigFlowAssignment>();
for (String name : targetClasses.keySet()) {
    Id classId = targetClasses.get(name);
    if (existing.contains(classId)) continue;

    ProductConfigFlowAssignment a = new ProductConfigFlowAssignment();
    a.ProductConfigurationFlowId = flowId;
    a.ProductClassificationId = classId;
    toInsert.add(a);
}

if (toInsert.isEmpty()) {
    System.debug('No new assignments needed');
} else {
    Database.SaveResult[] results = Database.insert(toInsert, false);
    for (Integer i = 0; i < results.size(); i++) {
        Database.SaveResult sr = results[i];
        if (sr.isSuccess()) {
            System.debug('Created assignment for classification: ' + targetClasses.values()[i]);
        } else {
            System.debug('FAILED for ' + targetClasses.values()[i] + ': ' + sr.getErrors()[0].getMessage());
        }
    }
}

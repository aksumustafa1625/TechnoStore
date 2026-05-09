// Clean up duplicate PricebookEntry records on the new tiered workstations.
// For each (Product2, Pricebook2) pair with multiple PBEs, keep the OLDEST and
// delete the rest. Inactivate before delete (Salesforce constraint).

Set<String> affectedCodes = new Set<String>{
    'COMP-WS-OFFICE','COMP-WS-BUSINESS','COMP-WS-HYPERSCALE','COMP-WS-PREMIUM','COMP-WS-STUDIO'
};

// Bucket all PBEs by (productId, pricebookId)
Map<String, List<PricebookEntry>> grouped = new Map<String, List<PricebookEntry>>();
for (PricebookEntry pbe : [
    SELECT Id, Product2Id, Product2.Name, Pricebook2Id, Pricebook2.Name, UnitPrice, IsActive, CreatedDate
    FROM PricebookEntry
    WHERE Product2.ProductCode IN :affectedCodes
    ORDER BY Product2Id, Pricebook2Id, CreatedDate ASC
]) {
    String key = pbe.Product2Id + '|' + pbe.Pricebook2Id;
    if (!grouped.containsKey(key)) grouped.put(key, new List<PricebookEntry>());
    grouped.get(key).add(pbe);
}

// Identify duplicates: keep PBE[0] (oldest), mark PBE[1..] for deletion
List<PricebookEntry> toInactivate = new List<PricebookEntry>();
List<PricebookEntry> toDelete = new List<PricebookEntry>();
for (String key : grouped.keySet()) {
    List<PricebookEntry> bucket = grouped.get(key);
    if (bucket.size() > 1) {
        System.debug('DUPLICATE GROUP: ' + bucket[0].Product2.Name + ' | ' + bucket[0].Pricebook2.Name + ' | count=' + bucket.size());
        for (Integer i = 1; i < bucket.size(); i++) {
            System.debug('  Keeping ' + bucket[0].Id + ' (' + bucket[0].CreatedDate + '), deleting ' + bucket[i].Id + ' (' + bucket[i].CreatedDate + ')');
            PricebookEntry dup = bucket[i];
            dup.IsActive = false;
            toInactivate.add(dup);
            toDelete.add(dup);
        }
    }
}

if (toInactivate.isEmpty()) {
    System.debug('No duplicates found.');
    return;
}

// Step 1: inactivate (required before delete)
update toInactivate;
System.debug('Inactivated ' + toInactivate.size() + ' duplicate PBEs');

// Step 2: delete with allOrNone=false to bypass any platform issue on individual rows
List<Database.DeleteResult> drs = Database.delete(toDelete, false);
Integer ok = 0, fail = 0;
for (Integer i = 0; i < drs.size(); i++) {
    if (drs[i].isSuccess()) ok++;
    else {
        fail++;
        System.debug('Failed delete ' + toDelete[i].Id + ': ' + drs[i].getErrors()[0].getMessage());
    }
}
System.debug('Deleted: ' + ok + ' | Failed: ' + fail);

// Verify final state
System.debug('======== FINAL PBE COUNT PER PRODUCT ========');
Map<String, Integer> countByProduct = new Map<String, Integer>();
for (PricebookEntry pbe : [SELECT Product2.Name FROM PricebookEntry WHERE Product2.ProductCode IN :affectedCodes]) {
    Integer c = countByProduct.containsKey(pbe.Product2.Name) ? countByProduct.get(pbe.Product2.Name) : 0;
    countByProduct.put(pbe.Product2.Name, c + 1);
}
for (String name : countByProduct.keySet()) {
    System.debug('  ' + name + ' | ' + countByProduct.get(name) + ' PBEs');
}

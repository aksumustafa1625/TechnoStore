// Step 1: Delete existing SfContract AppUsageAssignment
List<AppUsageAssignment> existing = [SELECT Id, AppUsageType FROM AppUsageAssignment WHERE RecordId='800aj00002Z2VIfAAN'];
System.debug('Existing assignments: ' + existing.size());
for (AppUsageAssignment a : existing) {
    System.debug('  - ' + a.AppUsageType + ' (' + a.Id + ')');
}
try {
    delete existing;
    System.debug('Deleted existing assignments');
} catch (Exception e) {
    System.debug('DELETE ERROR: ' + e.getMessage());
}

// Step 2: Insert RevenueLifecycleManagement
AppUsageAssignment rlm = new AppUsageAssignment();
rlm.RecordId = '800aj00002Z2VIfAAN';
rlm.AppUsageType = 'RevenueLifecycleManagement';
try {
    insert rlm;
    System.debug('RLM inserted: ' + rlm.Id);
} catch (Exception e) {
    System.debug('RLM INSERT ERROR: ' + e.getMessage());
}

// Step 3: Create AssetContractRelationship
AssetContractRelationship acr = new AssetContractRelationship();
acr.AssetId = '02iaj000002VUyLAAW';
acr.ContractId = '800aj00002Z2VIfAAN';
acr.StartDate = System.now();
try {
    insert acr;
    System.debug('Junction created: ' + acr.Id);
} catch (Exception e) {
    System.debug('JUNCTION ERROR: ' + e.getMessage());
}

// Verify
Integer cnt = [SELECT COUNT() FROM AssetContractRelationship WHERE ContractId='800aj00002Z2VIfAAN'];
System.debug('Final relationships: ' + cnt);

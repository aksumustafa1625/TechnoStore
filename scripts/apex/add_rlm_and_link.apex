AppUsageAssignment rlm = new AppUsageAssignment();
rlm.RecordId = '800aj00002Z2VIfAAN';
rlm.AppUsageType = 'RevenueLifecycleManagement';
try {
    insert rlm;
    System.debug('RLM AppUsageAssignment created: ' + rlm.Id);
} catch (Exception e) {
    System.debug('RLM insert ERROR: ' + e.getMessage());
}

AssetContractRelationship acr = new AssetContractRelationship();
acr.AssetId = '02iaj000002VUyLAAW';
acr.ContractId = '800aj00002Z2VIfAAN';
acr.StartDate = System.now();
try {
    insert acr;
    System.debug('Link created: ' + acr.Id);
} catch (Exception e) {
    System.debug('Link ERROR: ' + e.getMessage());
}
Integer cnt = [SELECT COUNT() FROM AssetContractRelationship WHERE ContractId='800aj00002Z2VIfAAN'];
System.debug('Relationships: ' + cnt);

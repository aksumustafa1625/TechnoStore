AssetContractRelationship acr = new AssetContractRelationship();
acr.AssetId = '02iaj000002VUyLAAW';
acr.ContractId = '800aj00002Z2VIfAAN';
acr.StartDate = System.now();
try {
    insert acr;
    System.debug('Link created: ' + acr.Id);
} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
}
Integer cnt = [SELECT COUNT() FROM AssetContractRelationship WHERE ContractId='800aj00002Z2VIfAAN'];
System.debug('Relationships on Contract 00000269: ' + cnt);

Id cid = '800aj00002YgcnSAAR';
System.debug('Lines: ' + [SELECT COUNT() FROM SalesContractLine WHERE ContractId = :cid]);
for (SalesContractLine scl : [SELECT Id, Name, Product2.Name, Quantity FROM SalesContractLine WHERE ContractId = :cid]) {
    System.debug('LINE: Name="'+scl.Name+'" product='+scl.Product2.Name+' qty='+scl.Quantity);
}
System.debug('---');
// Compare Opp vs Quote Use Case Mappings
for (ContextUseCaseMapping m : [SELECT Id, DeveloperName, MasterLabel, ReferenceObjectName, ReferenceObjectRecordTypeId, TargetObjectName, TargetObjectRecordTypeId, TargetObjectCustomFieldName, ContextDefinitionName, MappingName, MappingType, UseCaseType FROM ContextUseCaseMapping WHERE ReferenceObjectName IN ('Opportunity','Quote') ORDER BY ReferenceObjectName, MappingType, DeveloperName]) {
    System.debug(m.ReferenceObjectName + ' | ' + m.MappingType + ' | ' + m.MappingName + ' | CD=' + m.ContextDefinitionName + ' | RT=' + m.TargetObjectRecordTypeId + ' | CustomField=' + m.TargetObjectCustomFieldName + ' | Dev=' + m.DeveloperName);
}
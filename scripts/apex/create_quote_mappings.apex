ContextUseCaseMapping hyd = new ContextUseCaseMapping();
hyd.DeveloperName = 'QuoteToCntrHydrationMapping';
hyd.MasterLabel = 'QuoteToCntrHydrationMapping';
hyd.ReferenceObjectName = 'Quote';
hyd.TargetObjectName = 'Contract';
hyd.ContextDefinitionName = 'ContractsContextDefinition__stdctx';
hyd.MappingName = 'QuoteToCntrHydrationMapping';
hyd.MappingType = 'Hydration';
hyd.UseCaseType = 'ContractCreationOrUpdation';

ContextUseCaseMapping per = new ContextUseCaseMapping();
per.DeveloperName = 'QuoteToCntrPersistenceMapping';
per.MasterLabel = 'QuoteToCntrPersistenceMapping';
per.ReferenceObjectName = 'Quote';
per.TargetObjectName = 'Contract';
per.TargetObjectCustomFieldName = 'SourceQuoteId';
per.ContextDefinitionName = 'ContractsContextDefinition__stdctx';
per.MappingName = 'QuoteToCntrPersistenceMapping';
per.MappingType = 'Persistence';
per.UseCaseType = 'ContractCreationOrUpdation';

insert new List<ContextUseCaseMapping>{ hyd, per };

for (ContextUseCaseMapping m : [SELECT Id, DeveloperName, ReferenceObjectName, MappingType FROM ContextUseCaseMapping WHERE ReferenceObjectName = 'Quote']) {
    System.debug('CREATED: ' + m.Id + ' ' + m.DeveloperName + ' ' + m.MappingType);
}
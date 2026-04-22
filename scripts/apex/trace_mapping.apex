// Where are the QuoteToCntr ContextMapping title records? Under which ContextDefinition?
for (ContextMapping cm : [SELECT Id, Title, ContextDefinitionVersion.ContextDefinition.DeveloperName, ContextDefinitionVersion.VersionNumber, ContextDefinitionVersion.IsActive FROM ContextMapping WHERE Title LIKE 'QuoteToCntr%' OR Title LIKE 'OrderToCntr%' OR Title LIKE 'OppToCntr%']) {
    System.debug(cm.Title + ' | CD=' + cm.ContextDefinitionVersion.ContextDefinition.DeveloperName + ' | v=' + cm.ContextDefinitionVersion.VersionNumber + ' | active=' + cm.ContextDefinitionVersion.IsActive);
}

// Is there a 'ContractsContextDefinition' (without suffix) ContextDefinition?
for (ContextDefinition cd : [SELECT Id, DeveloperName FROM ContextDefinition]) {
    System.debug('CD: ' + cd.DeveloperName);
}
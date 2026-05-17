// Verify both Quote approval processes exist + which is active
for (ProcessDefinition pd : [SELECT Id, DeveloperName, Name, State FROM ProcessDefinition WHERE TableEnumOrId = 'Quote']) {
    System.debug('Process: ' + pd.DeveloperName + ' | Label=' + pd.Name + ' | State=' + pd.State);
}
